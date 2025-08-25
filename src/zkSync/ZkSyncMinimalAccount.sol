// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "foundry-era-contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "foundry-era-contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "foundry-era-contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "foundry-era-contracts/Constants.sol";
import {INonceHolder} from "foundry-era-contracts/interfaces/INonceHolder.sol";
import {Utils} from "foundry-era-contracts/libraries/Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Lifecycle of a type 113(0x71) transaction
 * @notice When a type 113 transaction is sent, the __msg.sender__ is the Bootloader(=super-admin) system contract
 *
 * @dev Phase 1: Validation
 *      1. The user sends the transaction to the zkSync API client (sort of light node)
 *      2. The zkSync API client checks to see if the nonce is unique by querying the NonceHolder system contract
 *      3. The zkSync API client calls __validateTransaction__, which MUST update the nonce
 *      4. The zkSync API client checks the nonce is updated
 *      5. The zkSync API client calls __payForTransaction__ OR __prepareForPaymaster__ AND __validateAndPayForPaymasterTransaction__
 *      6. The zkSync API client verifies that the Bootloader system contract gets paid
 *
 * @dev Phase 2: Execution
 *      7. The zkSync API client passes the validated transaction to the main node/sequencer
 *      8. The main node calls __executeTransaction__
 *      9. If a Paymaster was used, the __postTransaction__ is called
 */
contract ZkSyncMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkSyncMinimalAccount__NotEnoughBalance();
    error ZkSyncMinimalAccount__NotFromBootloader();
    error ZkSyncMinimalAccount__NotFromBootloaderOrOwner();
    error ZkSyncMinimalAccount__ExecutionFailed();
    error ZkSyncMinimalAccount__FailedToPay();
    error ZkSyncMinimalAccount__InvalidSignature();

    /*//////////////////////////////////////////////////////////////
                           MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkSyncMinimalAccount__NotFromBootloader();
        }
        _;
    }

    modifier requireFromBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkSyncMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                       EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice check if we have enough money in our account
     */
    function validateTransaction(
        bytes32, /*_txHash*/
        bytes32, /*_suggestedSignedHash*/
        Transaction calldata _transaction
    ) external payable requireFromBootloader returns (bytes4 magic) {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32, /*_txHash*/
        bytes32, /*_suggestedSignedHash*/
        Transaction calldata _transaction
    ) external payable requireFromBootloaderOrOwner {
        _executeTransaction(_transaction);
    }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method, since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if(magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZkSyncMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction calldata _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkSyncMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable
    {}

    /*//////////////////////////////////////////////////////////////
                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice check if we have enough money in our account
     */
    function _validateTransaction(Transaction calldata _transaction) internal returns (bytes4 magic) {
        // 1. Call NonceHolder to increment nonce
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // 2. Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();

        if (totalRequiredBalance > address(this).balance) {
            revert ZkSyncMinimalAccount__NotEnoughBalance();
        }

        // 3. Check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);

        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        // 4. Return the "magic" number
        return magic;
    }

    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }

            if (!success) {
                revert ZkSyncMinimalAccount__ExecutionFailed();
            }
        }
    }
}
