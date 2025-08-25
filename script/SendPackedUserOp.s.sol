// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";

contract SendPackedUserOpScript is Script {
    using MessageHashUtils for bytes32;

    uint256 private constant LOCAL_CHAIN_ID = 31337;
    uint256 private constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        address destination = config.usdc;
        uint256 value = 0;
        // 0xbD7f8Cb7963B11078fc8e06ca5043815Ed93b16A -> My Dev Wallet Account_1
        bytes memory functionData =
            abi.encodeWithSelector(IERC20.approve.selector, 0xbD7f8Cb7963B11078fc8e06ca5043815Ed93b16A, 1e18);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, destination, value, functionData);
        PackedUserOperation memory userOp = generateSignedUserOperation(executeCallData, config, address(1));
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.startBroadcast();
        IEntryPoint(config.entryPoint).handleOps(userOps, payable(config.account));
        vm.stopBroadcast();
    }

    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minimalAccount
    ) public view returns (PackedUserOperation memory) {
        // 1. Generate unsigned data
        uint256 nonce = vm.getNonce(minimalAccount) - 1;
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, minimalAccount, nonce);

        // 2. Get the userOp hash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        // keccak256 digest of an ERC-191 signed data with version `0x45` (`personal_sign` messages).
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // 3. Sign the data and return it
        uint8 v;
        bytes32 r;
        bytes32 s;

        if (block.chainid == LOCAL_CHAIN_ID) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else {
            // If `config.account` is unlocked, Foundry is able to use the privateKey related to it
            (v, r, s) = vm.sign(config.account, digest);
        }
        // The order is IMPORTANT
        userOp.signature = abi.encodePacked(r, s, v);

        return userOp;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16_777_216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            // 1. uint256(verificationGasLimit) -> Ensures verificationGasLimit is treated as a 256-bit unsigned integer
            // 2. << 128 -> Shifts the value of verificationGasLimit 128 bits to the left.
            // 3. The bitwise OR operation merges the shifted verificationGasLimit (upper 128 bits) and callGasLimit (assumed to be <= 128 bits) into a single 256-bit word.
            // 4. Casts the result of the OR operation into a fixed-size 32-byte array
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
