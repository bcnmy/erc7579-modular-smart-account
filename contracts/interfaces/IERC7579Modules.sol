// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IModule } from "./IModule.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

uint256 constant VALIDATION_SUCCESS = 0;
uint256 constant VALIDATION_FAILED = 1;

uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;

interface IValidator is IModule {
    error InvalidTargetAddress(address target);

    /**
     * @dev Validates a transaction on behalf of the account.
     *         This function is intended to be called by the MSA during the ERC-4337 validaton phase
     *         Note: solely relying on bytes32 hash and signature is not suffcient for some
     * validation implementations (i.e. SessionKeys often need access to userOp.calldata)
     * @param userOp The user operation to be validated. The userOp MUST NOT contain any metadata.
     * The MSA MUST clean up the userOp before sending it to the validator.
     * @param userOpHash The hash of the user operation to be validated
     * @return return value according to ERC-4337
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external returns (uint256);

    /**
     * Validator can be used for ERC-1271 validation
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        returns (bytes4);
}

interface IExecutor is IModule {
// solhint-disable-previous-line no-empty-blocks
}

interface IHook is IModule {
    function preCheck(address msgSender, bytes calldata msgData) external returns (bytes memory hookData);
    function postCheck(bytes calldata hookData) external returns (bool success);
}

interface IFallback is IModule {
// solhint-disable-previous-line no-empty-blocks
}