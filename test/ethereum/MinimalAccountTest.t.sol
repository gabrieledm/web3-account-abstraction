// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "../../src/ethereum/MinimalAccount.sol";
import {DeployMinimalAccountScript} from "../../script/DeployMinimalAccount.s.sol";
import {SendPackedUserOpScript, PackedUserOperation} from "../../script/SendPackedUserOp.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig private helperConfig;
    HelperConfig.NetworkConfig private config;
    MinimalAccount private minimalAccount;
    ERC20Mock private usdc;
    address private randomUser = makeAddr("randomUser");
    SendPackedUserOpScript private sendPackedUserOpScript;

    uint256 private constant AMOUNT = 1e18;

    function prepareUserOp()
        internal
        view
        returns (PackedUserOperation memory packedUserOperation, bytes32 packedUserOperationHash)
    {
        address destination = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, destination, value, functionData);

        //        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        packedUserOperation =
            sendPackedUserOpScript.generateSignedUserOperation(executeCallData, config, address(minimalAccount));
        packedUserOperationHash = IEntryPoint(config.entryPoint).getUserOpHash(packedUserOperation);
    }

    function setUp() public {
        DeployMinimalAccountScript deployMinimalAccountScript = new DeployMinimalAccountScript();
        (helperConfig, minimalAccount) = deployMinimalAccountScript.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOpScript = new SendPackedUserOpScript();
        config = helperConfig.getConfig();
    }

    function test_ownerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address destination = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(destination, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function test_nonOwnerCannotExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address destination = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);

        // Act
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(destination, value, functionData);
    }

    function test_recoverSignedOp() public view {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        (PackedUserOperation memory packedUserOperation, bytes32 packedUserOperationHash) = prepareUserOp();

        // Act
        // keccak256 digest of an ERC-191 signed data with version `0x45` (`personal_sign` messages).
        bytes32 packedUserOperationHashSignedMessage = packedUserOperationHash.toEthSignedMessageHash();
        address actualSigner = ECDSA.recover(packedUserOperationHashSignedMessage, packedUserOperation.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    /**
     * @dev 1. Sign userOp
     * @dev 2. Call validateUserOps
     * @dev 3. Assert the return is correct
     */
    function test_validationOfUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        (PackedUserOperation memory packedUserOperation, bytes32 packedUserOperationHash) = prepareUserOp();
        uint256 missingAccountFunds = AMOUNT;

        // Act
        vm.prank(config.entryPoint);
        uint256 validationData =
            minimalAccount.validateUserOp(packedUserOperation, packedUserOperationHash, missingAccountFunds);

        // Assert
        assertEq(validationData, 0);
    }

    function test_entryPointCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        (PackedUserOperation memory packedUserOperation,) = prepareUserOp();

        vm.deal(address(minimalAccount), AMOUNT);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOperation;

        // Act
        // Simulate an account of AltMemPool that actually calls the EntryPoint
        vm.prank(randomUser);
        IEntryPoint(config.entryPoint).handleOps(ops, payable(randomUser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}
