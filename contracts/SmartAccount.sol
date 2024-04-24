// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ExecutionHelper } from "./base/ExecutionHelper.sol";
import { ModuleManager } from "./base/ModuleManager.sol";
import { BaseAccount } from "./base/BaseAccount.sol";
import { UUPSUpgradeable } from "solady/src/utils/UUPSUpgradeable.sol";
import { EIP712 } from "solady/src/utils/EIP712.sol";
import { Execution } from "./interfaces/modules/IERC7579Modules.sol";
import { IValidator, MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK, MODULE_TYPE_HOOK, VALIDATION_FAILED } from "./interfaces/modules/IERC7579Modules.sol";
import { IBicoMSA } from "./interfaces/IBicoMSA.sol";
import { ModeLib, ExecutionMode, ExecType, CallType, CALLTYPE_BATCH, CALLTYPE_SINGLE, EXECTYPE_DEFAULT, EXECTYPE_TRY } from "./lib/ModeLib.sol";
import { ExecLib } from "./lib/ExecLib.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

// Review.. ERC1271
contract SmartAccount is IBicoMSA, EIP712, BaseAccount, ExecutionHelper, ModuleManager, UUPSUpgradeable {
    using ModeLib for ExecutionMode;
    using ExecLib for bytes;

    /// @dev Precomputed `typeHash` used to produce EIP-712 compliant hash when applying the anti
    ///      cross-account-replay layer.
    ///
    ///      The original hash must either be:
    ///         - An EIP-191 hash: keccak256("\x19Ethereum Signed Message:\n" || len(someMessage) || someMessage)
    ///         - An EIP-712 hash: keccak256("\x19\x01" || someDomainSeparator || hashStruct(someStruct))
    bytes32 private constant _MESSAGE_TYPEHASH = keccak256("BiconomyNexusMessage(bytes32 hash)");

    constructor() {
        _initModuleManager();
        // Review
        // disble initializers
    }

    function accountId() external pure virtual returns (string memory) {
        return _ACCOUNT_IMPLEMENTATION_ID;
    }

    // Todo: Change version
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Nexus";
        version = "0.0.1-beta";
    }

    /// @dev expects IValidator module address to be encoded in the nonce
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external virtual override payPrefund(missingAccountFunds) onlyEntryPoint returns (uint256) {
        address validator;
        uint256 nonce = userOp.nonce;
        assembly {
            validator := shr(96, nonce)
        }
        // check if validator is enabled. If terminate the validation phase.
        if (!_isValidatorInstalled(validator)) return VALIDATION_FAILED;

        // bubble up the return value of the validator module
        uint256 validationData = IValidator(validator).validateUserOp(userOp, userOpHash);
        return validationData;
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) public payable virtual override {
        UUPSUpgradeable.upgradeToAndCall(newImplementation, data);
    }

    /**
     * Executes a transaction or a batch of transactions with specified execution mode.
     * This function handles both single and batch transactions, supporting default execution and try/catch logic.
     */
    function execute(ExecutionMode mode, bytes calldata executionCalldata) external payable onlyEntryPointOrSelf {
        (address hook, bytes memory hookData) = _preCheck();
        (CallType callType, ExecType execType, , ) = mode.decode();
        if (callType == CALLTYPE_SINGLE) {
            _handleSingleExecution(executionCalldata, execType);
        } else if (callType == CALLTYPE_BATCH) {
            _handleBatchExecution(executionCalldata, execType);
        } else {
            revert UnsupportedCallType(callType);
        }
        _postCheck(hook, hookData, true, new bytes(0));
    }

    /**
     * @dev this function is only callable by an installed executor module
     * @dev this function demonstrates how to implement
     * CallType SINGLE and BATCH and ExecType DEFAULT and TRY
     * @dev this function could implement hook support (modifier)
     */
    function executeFromExecutor(
        ExecutionMode mode,
        bytes calldata executionCalldata
    )
        external
        payable
        onlyExecutorModule
        returns (
            bytes[] memory returnData // TODO returnData is not used
        )
    {
        (address hook, bytes memory hookData) = _preCheck();
        (CallType callType, ExecType execType, , ) = mode.decode();

        // check if calltype is batch or single
        if (callType == CALLTYPE_SINGLE) {
            // destructure executionCallData according to single exec
            (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
            returnData = new bytes[](1);
            bool success;
            // check if execType is revert(default) or try
            if (execType == EXECTYPE_DEFAULT) {
                returnData[0] = _execute(target, value, callData);
            }
            // TODO: implement event emission for tryExecute singleCall
            else if (execType == EXECTYPE_TRY) {
                (success, returnData[0]) = _tryExecute(target, value, callData);
                if (!success) emit TryExecuteUnsuccessful(0, returnData[0]);
            } else {
                revert UnsupportedExecType(execType);
            }
        } else if (callType == CALLTYPE_BATCH) {
            // destructure executionCallData according to batched exec
            Execution[] calldata executions = executionCalldata.decodeBatch();
            // check if execType is revert or try
            if (execType == EXECTYPE_DEFAULT) returnData = _executeBatch(executions);
            else if (execType == EXECTYPE_TRY) returnData = _tryExecute(executions);
            else revert UnsupportedExecType(execType);
        } else {
            revert UnsupportedCallType(callType);
        }
        _postCheck(hook, hookData, true, new bytes(0));
    }

    /**
     */
    function executeUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /*userOpHash*/
    ) external payable virtual onlyEntryPoint {
        bytes calldata callData = userOp.callData[4:];
        (bool success, ) = address(this).delegatecall(callData);
        if (!success) revert ExecutionFailed();
    }

    /**
     */
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) external payable onlyEntryPointOrSelf {
        (address hook, bytes memory hookData) = _preCheck();
        if (module == address(0)) revert ModuleAddressCanNotBeZero();
        if (_isModuleInstalled(moduleTypeId, module, initData)) {
            revert ModuleAlreadyInstalled(moduleTypeId, module);
        }
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            _installValidator(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            _installExecutor(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            _installFallbackHandler(module, initData);
        } else if (moduleTypeId == MODULE_TYPE_HOOK) {
            _installHook(module, initData);
        } else {
            revert InvalidModuleTypeId(moduleTypeId);
        }
        emit ModuleInstalled(moduleTypeId, module);
        _postCheck(hook, hookData, true, new bytes(0));
    }

    /**
     */
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    ) external payable onlyEntryPointOrSelf {
        if (!_isModuleInstalled(moduleTypeId, module, deInitData)) {
            revert ModuleNotInstalled(moduleTypeId, module);
        }
        // Note: Should be able to validate passed moduleTypeId agaisnt the provided module address and interface?
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) _uninstallValidator(module, deInitData);
        else if (moduleTypeId == MODULE_TYPE_EXECUTOR) _uninstallExecutor(module, deInitData);
        else if (moduleTypeId == MODULE_TYPE_FALLBACK) _uninstallFallbackHandler(module, deInitData);
        else if (moduleTypeId == MODULE_TYPE_HOOK) _uninstallHook(module, deInitData);
        else revert UnsupportedModuleType(moduleTypeId);
        emit ModuleUninstalled(moduleTypeId, module);
    }

    // TODO // Review for initialize modifiers
    // Review natspec
    /**
     * @dev Initializes the account. Function might be called directly, or by a Factory
     * @param initData. encoded data that can be used during the initialization phase
     */
    function initialize(address firstValidator, bytes calldata initData) external payable virtual {
        // checks if already initialized and reverts before setting the state to initialized
        _initModuleManager();
        _installValidator(firstValidator, initData);
    }

    // TODO
    // isValidSignature
    // by base contract ERC1271 or a method like below..
    /**
     * @dev ERC-1271 isValidSignature
     *         This function is intended to be used to validate a smart account signature
     * and may forward the call to a validator module
     *
     * @param hash The hash of the data that is signed
     * @param data The data that is signed
     */
    function isValidSignature(bytes32 hash, bytes calldata data) external view virtual override returns (bytes4) {
        address validator = address(bytes20(data[0:20]));
        if (!_isValidatorInstalled(validator)) revert InvalidModule(validator);
        return IValidator(validator).isValidSignatureWithSender(msg.sender, _eip712Hash(hash), data[20:]);
    }

    /// @notice Returns the EIP-712 typed hash of the `BiconomyNexusMessage(bytes32 hash)` data structure.
    ///
    /// @dev Implements encode(domainSeparator : 𝔹²⁵⁶, message : 𝕊) = "\x19\x01" || domainSeparator ||
    ///      hashStruct(message).
    /// @dev See https://eips.ethereum.org/EIPS/eip-712#specification.
    ///
    /// @param hash The `BiconomyNexusMessage.hash` field to hash.
    ////
    /// @return The resulting EIP-712 hash.
    function _eip712Hash(bytes32 hash) internal view virtual returns (bytes32) {
        return
            keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(_MESSAGE_TYPEHASH, hash))));
    }

    /// @notice Wrapper around `_eip712Hash()` to produce a replay-safe hash fron the given `hash`.
    ///
    /// @dev The returned EIP-712 compliant replay-safe hash is the result of:
    ///      keccak256(
    ///         \x19\x01 ||
    ///         this.domainSeparator ||
    ///         hashStruct(CoinbaseSmartWalletMessage({ hash: `hash`}))
    ///      )
    ///
    /// @param hash The original hash.
    ///
    /// @return The corresponding replay-safe hash.
    function replaySafeHash(bytes32 hash) public view virtual returns (bytes32) {
        return _eip712Hash(hash);
    }

    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
    }

    /**
     */
    function supportsModule(uint256 modulTypeId) external view virtual returns (bool) {
        if (modulTypeId == MODULE_TYPE_VALIDATOR) return true;
        else if (modulTypeId == MODULE_TYPE_EXECUTOR) return true;
        else if (modulTypeId == MODULE_TYPE_FALLBACK) return true;
        else if (modulTypeId == MODULE_TYPE_HOOK) return true;
        else return false;
    }

    /**
     */
    function supportsExecutionMode(ExecutionMode mode) external view virtual returns (bool isSupported) {
        (CallType callType, ExecType execType, , ) = mode.decode();
        if (callType == CALLTYPE_BATCH) {
            isSupported = true;
        } else if (callType == CALLTYPE_SINGLE) {
            isSupported = true;
        }
        // if callType is not single or batch return false
        // CALLTYPE_DELEGATECALL not supported
        else {
            return false;
        }

        if (execType == EXECTYPE_DEFAULT) {
            isSupported = true;
        } else if (execType == EXECTYPE_TRY) {
            isSupported = true;
        }
        // if execType is not default or try, return false
        else {
            return false;
        }
    }

    /**
     */
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    ) external view override returns (bool) {
        return _isModuleInstalled(moduleTypeId, module, additionalContext);
    }

    // Review the need for interface
    // Add natspec
    /// @dev To ensure that the account itself can upgrade the implementation.
    function _authorizeUpgrade(address) internal virtual override(UUPSUpgradeable) onlyEntryPointOrSelf {
        // solhint-disable-previous-line no-empty-blocks
    }

    function _handleBatchExecution(bytes calldata executionCalldata, ExecType execType) private {
        Execution[] calldata executions = executionCalldata.decodeBatch();
        if (execType == EXECTYPE_DEFAULT) _executeBatch(executions);
        else if (execType == EXECTYPE_TRY) _tryExecute(executions);
        else revert UnsupportedExecType(execType);
    }

    function _handleSingleExecution(bytes calldata executionCalldata, ExecType execType) private {
        (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
        if (execType == EXECTYPE_DEFAULT) _execute(target, value, callData);
        else if (execType == EXECTYPE_TRY) _tryExecute(target, value, callData);
        else revert UnsupportedExecType(execType);
    }

    /**
     * @notice Checks if a module is installed on the smart account.
     * @param moduleTypeId The module type ID.
     * @param module The module address.
     * @param additionalContext Additional context for checking installation.
     * @return True if the module is installed, false otherwise.
     */
    function _isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    ) private view returns (bool) {
        additionalContext;
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) return _isValidatorInstalled(module);
        else if (moduleTypeId == MODULE_TYPE_EXECUTOR) return _isExecutorInstalled(module);
        else if (moduleTypeId == MODULE_TYPE_FALLBACK)
            return _isFallbackHandlerInstalled(abi.decode(additionalContext, (bytes4)), module);
        else if (moduleTypeId == MODULE_TYPE_HOOK) return _isHookInstalled(module);
        else return false;
    }
}
