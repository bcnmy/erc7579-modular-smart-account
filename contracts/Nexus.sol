// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// ──────────────────────────────────────────────────────────────────────────────
//     _   __    _  __
//    / | / /__ | |/ /_  _______
//   /  |/ / _ \|   / / / / ___/
//  / /|  /  __/   / /_/ (__  )
// /_/ |_/\___/_/|_\__,_/____/
//
// ──────────────────────────────────────────────────────────────────────────────
// Nexus: A suite of contracts for Modular Smart Accounts compliant with ERC-7579 and ERC-4337, developed by Biconomy.
// Learn more at https://biconomy.io. To report security issues, please contact us at: security@biconomy.io

import { UUPSUpgradeable } from "solady/src/utils/UUPSUpgradeable.sol";
import { EIP712 } from "solady/src/utils/EIP712.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import { ExecLib } from "./lib/ExecLib.sol";
import { Execution } from "./types/DataTypes.sol";
import { INexus } from "./interfaces/INexus.sol";
import { IModule } from "./interfaces/modules/IModule.sol";
import { BaseAccount } from "./base/BaseAccount.sol";
import { IERC7484 } from "./interfaces/IERC7484.sol";
import { ModuleManager } from "./base/ModuleManager.sol";
import { ExecutionHelper } from "./base/ExecutionHelper.sol";
import { IValidator } from "./interfaces/modules/IValidator.sol";
import { MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK, MODULE_TYPE_HOOK, VALIDATION_FAILED } from "./types/Constants.sol";
import { ModeLib, ExecutionMode, ExecType, CallType, CALLTYPE_BATCH, CALLTYPE_SINGLE, EXECTYPE_DEFAULT, EXECTYPE_TRY } from "./lib/ModeLib.sol";

/// @title Nexus - Smart Account
/// @notice This contract integrates various functionalities to handle modular smart accounts compliant with ERC-7579 and ERC-4337 standards.
/// @dev Comprehensive suite of methods for managing smart accounts, integrating module management, execution management, and upgradability via UUPS.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract Nexus is INexus, EIP712, BaseAccount, ExecutionHelper, ModuleManager, UUPSUpgradeable {
    using ModeLib for ExecutionMode;
    using ExecLib for bytes;

    /// @dev Precomputed `typeHash` used to produce EIP-712 compliant hash when applying the anti
    ///      cross-account-replay layer.
    ///
    ///      The original hash must either be:
    ///         - An EIP-191 hash: keccak256("\x19Ethereum Signed Message:\n" || len(someMessage) || someMessage)
    ///         - An EIP-712 hash: keccak256("\x19\x01" || someDomainSeparator || hashStruct(someStruct))
    bytes32 private constant _MESSAGE_TYPEHASH = keccak256("BiconomyNexusMessage(bytes32 hash)");

    address private immutable _SELF;

    /// @dev `keccak256("PersonalSign(bytes prefixed)")`.
    bytes32 internal constant _PERSONAL_SIGN_TYPEHASH = 0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de;

    /// @notice Initializes the smart account with the specified entry point.
    constructor(address anEntryPoint) {
        _SELF = address(this);
        require(address(anEntryPoint) != address(0), EntryPointCanNotBeZero());
        _ENTRYPOINT = anEntryPoint;
        _initModuleManager();
    }

    /// Validates a user operation against a specified validator, extracted from the operation's nonce.
    /// The entryPoint calls this only if validation succeeds. Fails by returning `VALIDATION_FAILED` for invalid signatures.
    /// Other validation failures (e.g., nonce mismatch) should revert.
    /// @param userOp The operation to validate, encapsulating all transaction details.
    /// @param userOpHash Hash of the operation data, used for signature validation.
    /// @param missingAccountFunds Funds missing from the account's deposit necessary for transaction execution.
    /// This can be zero if covered by a paymaster or sufficient deposit exists.
    /// @return validationData Encoded validation result or failure, propagated from the validator module.
    /// - Encoded format in validationData:
    ///     - First 20 bytes: Validator address, 0x0 for valid or specific failure modes.
    ///     - `SIG_VALIDATION_FAILED` (1) denotes signature validation failure allowing simulation calls without a valid signature.
    /// @dev Expects the validator's address to be encoded in the upper 96 bits of the userOp's nonce.
    /// This method forwards the validation task to the extracted validator module address.
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external virtual payPrefund(missingAccountFunds) onlyEntryPoint returns (uint256 validationData) {
        address validator;
        uint256 userOpnonce = userOp.nonce;
        assembly {
            validator := shr(96, userOpnonce)
        }
        // Check if validator is not enabled. If not, return VALIDATION_FAILED.

        if (!_isValidatorInstalled(validator)) return VALIDATION_FAILED;

        // bubble up the return value of the validator module
        validationData = IValidator(validator).validateUserOp(userOp, userOpHash);
    }

    /// @notice Executes transactions in single or batch modes as specified by the execution mode.
    /// @param mode The execution mode detailing how transactions should be handled (single, batch, default, try/catch).
    /// @param executionCalldata The encoded transaction data to execute.
    /// @dev This function handles transaction execution flexibility and is protected by the `onlyEntryPointOrSelf` modifier.
    /// @dev This function also goes through hook checks via withHook modifier.
    function execute(ExecutionMode mode, bytes calldata executionCalldata) external payable onlyEntryPointOrSelf withHook {
        (CallType callType, ExecType execType) = mode.decodeBasic();
        if (callType == CALLTYPE_SINGLE) {
            _handleSingleExecution(executionCalldata, execType);
        } else if (callType == CALLTYPE_BATCH) {
            _handleBatchExecution(executionCalldata, execType);
        } else {
            revert UnsupportedCallType(callType);
        }
    }

    /// @notice Executes transactions from an executor module, supporting both single and batch transactions.
    /// @param mode The execution mode (single or batch, default or try).
    /// @param executionCalldata The transaction data to execute.
    /// @return returnData The results of the transaction executions, which may include errors in try mode.
    /// @dev This function is callable only by an executor module and goes through hook checks.
    function executeFromExecutor(
        ExecutionMode mode,
        bytes calldata executionCalldata
    ) external payable onlyExecutorModule withHook withRegistry(msg.sender, MODULE_TYPE_EXECUTOR) returns (bytes[] memory returnData) {
        (CallType callType, ExecType execType) = mode.decodeBasic();

        // check if calltype is batch or single
        if (callType == CALLTYPE_SINGLE) {
            // destructure executionCallData according to single exec
            (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
            returnData = new bytes[](1);
            bool success;
            // check if execType is revert(default) or try
            if (execType == EXECTYPE_DEFAULT) {
                returnData[0] = _execute(target, value, callData);
            } else if (execType == EXECTYPE_TRY) {
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
            else if (execType == EXECTYPE_TRY) returnData = _tryExecuteBatch(executions);
            else revert UnsupportedExecType(execType);
        } else {
            revert UnsupportedCallType(callType);
        }
    }

    /// @notice Executes a user operation via a call using the contract's context.
    /// @param userOp The user operation to execute, containing transaction details.
    /// @param - Hash of the user operation.
    /// @dev Only callable by the EntryPoint. Decodes the user operation calldata, skipping the first four bytes, and executes the inner call.
    function executeUserOp(PackedUserOperation calldata userOp, bytes32) external payable virtual onlyEntryPoint {
        // Extract inner call data from user operation, skipping the first 4 bytes.
        bytes calldata innerCall = userOp.callData[4:];
        bytes memory innerCallRet = "";

        // Check and execute the inner call if data exists.
        if (innerCall.length > 0) {
            // Decode target address and call data from inner call.
            (address target, bytes memory data) = abi.decode(innerCall, (address, bytes));
            bool success;
            // Perform the call to the target contract with the decoded data.
            (success, innerCallRet) = target.call(data);
            // Ensure the call was successful.
            require(success, InnerCallFailed());
        }

        // Emit the Executed event with the user operation and inner call return data.
        emit Executed(userOp, innerCallRet);
    }

    /// @notice Installs a new module to the smart account.
    /// @param moduleTypeId The type identifier of the module being installed, which determines its role:
    /// - 1 for Validator
    /// - 2 for Executor
    /// - 3 for Fallback
    /// - 4 for Hook
    /// @param module The address of the module to install.
    /// @param initData Initialization data for the module.
    /// @dev This function can only be called by the EntryPoint or the account itself for security reasons.
    /// @dev This function also goes through hook checks via withHook modifier.
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external payable onlyEntryPointOrSelf withHook {
        require(module != address(0), ModuleAddressCanNotBeZero());
        require(IModule(module).isModuleType(moduleTypeId), MismatchModuleTypeId(moduleTypeId));
        require(!_isModuleInstalled(moduleTypeId, module, initData), ModuleAlreadyInstalled(moduleTypeId, module));

        emit ModuleInstalled(moduleTypeId, module);

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
    }

    /// @notice Uninstalls a module from the smart account.
    /// @param moduleTypeId The type ID of the module to be uninstalled, matching the installation type:
    /// - 1 for Validator
    /// - 2 for Executor
    /// - 3 for Fallback
    /// - 4 for Hook
    /// @param module The address of the module to uninstall.
    /// @param deInitData De-initialization data for the module.
    /// @dev Ensures that the operation is authorized and valid before proceeding with the uninstallation.
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external payable onlyEntryPointOrSelf {
        require(IModule(module).isModuleType(moduleTypeId), MismatchModuleTypeId(moduleTypeId));
        require(_isModuleInstalled(moduleTypeId, module, deInitData), ModuleNotInstalled(moduleTypeId, module));

        emit ModuleUninstalled(moduleTypeId, module);

        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            _uninstallValidator(module, deInitData);
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            _uninstallExecutor(module, deInitData);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            _uninstallFallbackHandler(module, deInitData);
        } else if (moduleTypeId == MODULE_TYPE_HOOK) {
            _uninstallHook(module, deInitData);
        }
    }

    function initializeAccount(bytes calldata initData) external payable virtual {
        _initModuleManager();
        (address bootstrap, bytes memory bootstrapCall) = abi.decode(initData, (address, bytes));
        (bool success, ) = bootstrap.delegatecall(bootstrapCall);
        require(success, NexusInitializationFailed());
    }

    function setRegistry(IERC7484 newRegistry, address[] calldata attesters, uint8 threshold) external onlyEntryPointOrSelf {
        _configureRegistry(newRegistry, attesters, threshold);
    }

    /// @notice Validates a signature according to ERC-1271 standards.
    /// @param hash The hash of the data being validated.
    /// @param data Signature data that needs to be validated.
    /// @return The status code of the signature validation (`0x1626ba7e` if valid).
    /// bytes4(keccak256("isValidSignature(bytes32,bytes)") = 0x1626ba7e
    /// @dev Delegates the validation to a validator module specified within the signature data.
    function isValidSignature(bytes32 hash, bytes calldata data) external view virtual override returns (bytes4) {
        // First 20 bytes of data will be validator address and rest of the bytes is complete signature.
        address validator = address(bytes20(data[0:20]));
        require(_isValidatorInstalled(validator), InvalidModule(validator));
        (bytes32 computeHash, bytes calldata truncatedSignature) = _erc1271HashForIsValidSignatureViaNestedEIP712(hash, data[20:]);
        return IValidator(validator).isValidSignatureWithSender(msg.sender, computeHash, truncatedSignature);
    }

    /// @notice Retrieves the address of the current implementation from the EIP-1967 slot.
    /// @notice Checks the 1967 implementation slot, if not found then checks the slot defined by address (Biconomy V2 smart account)
    /// @return implementation The address of the current contract implementation.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(_ERC1967_IMPLEMENTATION_SLOT)
        }
        if (implementation == address(0)) {
            assembly {
                implementation := sload(address())
            }
        }
    }

    /// @notice Checks if a specific module type is supported by this smart account.
    /// @param moduleTypeId The identifier of the module type to check.
    /// @return True if the module type is supported, false otherwise.
    function supportsModule(uint256 moduleTypeId) external view virtual returns (bool) {
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) return true;
        else if (moduleTypeId == MODULE_TYPE_EXECUTOR) return true;
        else if (moduleTypeId == MODULE_TYPE_FALLBACK) return true;
        else if (moduleTypeId == MODULE_TYPE_HOOK) return true;
        else return false;
    }

    /// @notice Determines if a specific execution mode is supported.
    /// @param mode The execution mode to evaluate.
    /// @return isSupported True if the execution mode is supported, false otherwise.
    function supportsExecutionMode(ExecutionMode mode) external view virtual returns (bool isSupported) {
        (CallType callType, ExecType execType) = mode.decodeBasic();

        // Return true if both the call type and execution type are supported.
        return (callType == CALLTYPE_SINGLE || callType == CALLTYPE_BATCH) && (execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY);
    }

    /// @notice Determines whether a module is installed on the smart account.
    /// @param moduleTypeId The ID corresponding to the type of module (Validator, Executor, Fallback, Hook).
    /// @param module The address of the module to check.
    /// @param additionalContext Optional context that may be needed for certain checks.
    /// @return True if the module is installed, false otherwise.
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) external view returns (bool) {
        return _isModuleInstalled(moduleTypeId, module, additionalContext);
    }

    /// @dev EIP712 hashTypedData method.
    function hashTypedData(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedData(structHash);
    }

    /// @dev EIP712 domain separator.
    // solhint-disable func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /// Returns the account's implementation ID.
    /// @return The unique identifier for this account implementation.
    function accountId() external pure virtual returns (string memory) {
        return _ACCOUNT_IMPLEMENTATION_ID;
    }

    /// Upgrades the contract to a new implementation and calls a function on the new contract.
    /// @notice Updates two slots 1. ERC1967 slot and
    /// 2. address() slot in case if it's potentially upgraded earlier from Biconomy V2 account,
    /// as Biconomy v2 Account (proxy) reads implementation from the slot that is defined by its address
    /// @param newImplementation The address of the new contract implementation.
    /// @param data The calldata to be sent to the new implementation.
    function upgradeToAndCall(address newImplementation, bytes calldata data) public payable virtual override onlyEntryPointOrSelf {
        require(newImplementation != address(0), InvalidImplementationAddress());
        bool res;
        assembly {
            res := gt(extcodesize(newImplementation), 0)
        }
        require(res, InvalidImplementationAddress());
        // update the address() storage slot as well.
        assembly {
            sstore(address(), newImplementation)
        }
        UUPSUpgradeable.upgradeToAndCall(newImplementation, data);
    }

    /// @notice Wrapper around `_eip712Hash()` to produce a replay-safe hash fron the given `hash`.
    ///
    /// @dev The returned EIP-712 compliant replay-safe hash is the result of:
    ///      keccak256(
    ///         \x19\x01 ||
    ///         this.domainSeparator ||
    ///         hashStruct(BiconomyNexusMessage({ hash: `hash`}))
    ///      )
    ///
    /// @param hash The original hash.
    ///
    /// @return The corresponding replay-safe hash.
    function replaySafeHash(bytes32 hash) public view virtual returns (bytes32) {
        return _eip712Hash(hash);
    }

    /// @dev For automatic detection that the smart account supports the nested EIP-712 workflow.
    /// By default, it returns `bytes32(bytes4(keccak256("supportsNestedTypedDataSign()")))`,
    /// denoting support for the default behavior, as implemented in
    /// `_erc1271IsValidSignatureViaNestedEIP712`, which is called in `isValidSignature`.
    /// Future extensions should return a different non-zero `result` to denote different behavior.
    /// This method intentionally returns bytes32 to allow freedom for future extensions.
    function supportsNestedTypedDataSign() public pure virtual returns (bytes32 result) {
        result = bytes4(0xd620c85a);
    }

    /// @dev Ensures that only authorized callers can upgrade the smart contract implementation.
    /// This is part of the UUPS (Universal Upgradeable Proxy Standard) pattern.
    /// @param newImplementation The address of the new implementation to upgrade to.
    function _authorizeUpgrade(address newImplementation) internal virtual override(UUPSUpgradeable) onlyEntryPointOrSelf {}

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
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), keccak256(abi.encode(_MESSAGE_TYPEHASH, hash))));
    }

    /// @dev ERC1271 signature validation (Nested EIP-712 workflow).
    ///
    /// This implementation uses a nested EIP-712 approach to
    /// prevent signature replays when a single signer owns multiple smart contract accounts,
    /// while still enabling wallet UIs (e.g. Metamask) to show the EIP-712 values.
    ///
    /// Crafted for phishing resistance, efficiency, flexibility.
    /// __________________________________________________________________________________________
    ///
    /// Glossary:
    ///
    /// - `APP_DOMAIN_SEPARATOR`: The domain separator of the `hash`.
    ///   Provided by the front end. Intended to be the domain separator of the contract
    ///   that will call `isValidSignature` on this account.
    ///
    /// - `ACCOUNT_DOMAIN_SEPARATOR`: The domain separator of this account.
    ///   See: `EIP712._domainSeparator()`.
    /// __________________________________________________________________________________________
    ///
    /// For the `TypedDataSign` workflow, the final hash will be:
    /// ```
    ///     keccak256(\x19\x01 ‖ APP_DOMAIN_SEPARATOR ‖
    ///         hashStruct(TypedDataSign({
    ///             contents: hashStruct(originalStruct),
    ///             name: keccak256(bytes(eip712Domain().name)),
    ///             version: keccak256(bytes(eip712Domain().version)),
    ///             chainId: eip712Domain().chainId,
    ///             verifyingContract: eip712Domain().verifyingContract,
    ///             salt: eip712Domain().salt
    ///             extensions: keccak256(abi.encodePacked(eip712Domain().extensions))
    ///         }))
    ///     )
    /// ```
    /// where `‖` denotes the concatenation operator for bytes.
    /// The order of the fields is important: `contents` comes before `name`.
    ///
    /// The signature will be `r ‖ s ‖ v ‖
    ///     APP_DOMAIN_SEPARATOR ‖ contents ‖ contentsType ‖ uint16(contentsType.length)`,
    /// where `contents` is the bytes32 struct hash of the original struct.
    ///
    /// The `APP_DOMAIN_SEPARATOR` and `contents` will be used to verify if `hash` is indeed correct.
    /// __________________________________________________________________________________________
    ///
    /// For the `PersonalSign` workflow, the final hash will be:
    /// ```
    ///     keccak256(\x19\x01 ‖ ACCOUNT_DOMAIN_SEPARATOR ‖
    ///         hashStruct(PersonalSign({
    ///             prefixed: keccak256(bytes(\x19Ethereum Signed Message:\n ‖
    ///                 base10(bytes(someString).length) ‖ someString))
    ///         }))
    ///     )
    /// ```
    /// where `‖` denotes the concatenation operator for bytes.
    ///
    /// The `PersonalSign` type hash will be `keccak256("PersonalSign(bytes prefixed)")`.
    /// The signature will be `r ‖ s ‖ v`.
    /// __________________________________________________________________________________________
    ///
    /// For demo and typescript code, see:
    /// - https://github.com/junomonster/nested-eip-712
    /// - https://github.com/frangio/eip712-wrapper-for-eip1271
    ///
    /// Their nomenclature may differ from ours, although the high-level idea is similar.
    ///
    /// Of course, if you have control over the codebase of the wallet client(s) too,
    /// you can choose a more minimalistic signature scheme like
    /// `keccak256(abi.encode(address(this), hash))` instead of all these acrobatics.
    /// All these are just for widespread out-of-the-box compatibility with other wallet clients.
    function _erc1271HashForIsValidSignatureViaNestedEIP712(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bytes32, bytes calldata) {
        assembly {
            // Unwraps the ERC6492 wrapper if it exists.
            // See: https://eips.ethereum.org/EIPS/eip-6492
            if eq(
                calldataload(add(signature.offset, sub(signature.length, 0x20))),
                mul(0x6492, div(not(mload(0x60)), 0xffff)) // `0x6492...6492`.
            ) {
                let o := add(signature.offset, calldataload(add(signature.offset, 0x40)))
                signature.length := calldataload(o)
                signature.offset := add(o, 0x20)
            }
        }

        bool result;
        bytes32 t = _typedDataSignFields();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            // Length of the contents type.
            let c := and(0xffff, calldataload(add(signature.offset, sub(signature.length, 0x20))))
            for {

            } 1 {

            } {
                let l := add(0x42, c) // Total length of appended data (32 + 32 + c + 2).
                let o := add(signature.offset, sub(signature.length, l))
                calldatacopy(0x20, o, 0x40) // Copy the `APP_DOMAIN_SEPARATOR` and contents struct hash.
                mstore(0x00, 0x1901) // Store the "\x19\x01" prefix.
                // Use the `PersonalSign` workflow if the reconstructed contents hash doesn't match,
                // or if the appended data is invalid (length too long, or empty contents type).
                if or(xor(keccak256(0x1e, 0x42), hash), or(lt(signature.length, l), iszero(c))) {
                    mstore(0x00, _PERSONAL_SIGN_TYPEHASH)
                    mstore(0x20, hash) // Store the `prefixed`.
                    hash := keccak256(0x00, 0x40) // Compute the `PersonalSign` struct hash.
                    break
                }
                // Else, use the `TypedDataSign` workflow.
                mstore(m, "TypedDataSign(") // To construct `TYPED_DATA_SIGN_TYPEHASH` on-the-fly.
                let p := add(m, 0x0e) // Advance 14 bytes.
                calldatacopy(p, add(o, 0x40), c) // Copy the contents type.
                let d := byte(0, mload(p)) // For denoting if the contents name is invalid.
                d := or(gt(26, sub(d, 97)), eq(40, d)) // Starts with lowercase or '('.
                // Store the end sentinel '(', and advance `p` until we encounter a '(' byte.
                for {
                    mstore(add(p, c), 40)
                } 1 {
                    p := add(p, 1)
                } {
                    let b := byte(0, mload(p))
                    if eq(40, b) {
                        break
                    }
                    d := or(d, shr(b, 0x120100000001)) // Has a byte in ", )\x00".
                }
                mstore(p, " contents,bytes1 fields,string n")
                mstore(add(p, 0x20), "ame,string version,uint256 chain")
                mstore(add(p, 0x40), "Id,address verifyingContract,byt")
                mstore(add(p, 0x60), "es32 salt,uint256[] extensions)")
                calldatacopy(add(p, 0x7f), add(o, 0x40), c) // Copy the contents type.
                // Fill in the missing fields of the `TypedDataSign`.
                calldatacopy(t, o, 0x40) // Copy `contents` to `add(t, 0x20)`.
                mstore(t, keccak256(m, sub(add(add(p, 0x7f), c), m))) // `TYPED_DATA_SIGN_TYPEHASH`.
                // The "\x19\x01" prefix is already at 0x00.
                // `APP_DOMAIN_SEPARATOR` is already at 0x20.
                mstore(0x40, keccak256(t, 0x120)) // `hashStruct(typedDataSign)`.
                // Compute the final hash, corrupted if the contents name is invalid.
                hash := keccak256(0x1e, add(0x42, and(1, d)))
                result := 1 // Use `result` to temporarily denote if we will use `APP_DOMAIN_SEPARATOR`.
                signature.length := sub(signature.length, l) // Truncate the signature.
                break
            }
            mstore(0x40, m) // Restore the free memory pointer.
        }
        if (!result) hash = _hashTypedData(hash);
        return (hash, signature);
    }

    /// @dev EIP712 domain name and version.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Nexus";
        version = "1.0.0-beta";
    }

    /// @dev Executes a single transaction based on the specified execution type.
    /// @param executionCalldata The calldata containing the transaction details (target address, value, and data).
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    function _handleSingleExecution(bytes calldata executionCalldata, ExecType execType) private {
        (address target, uint256 value, bytes calldata callData) = executionCalldata.decodeSingle();
        if (execType == EXECTYPE_DEFAULT) _execute(target, value, callData);
        else if (execType == EXECTYPE_TRY) _tryExecute(target, value, callData);
        else revert UnsupportedExecType(execType);
    }

    /// @dev Executes a batch of transactions based on the specified execution type.
    /// @param executionCalldata The calldata for a batch of transactions.
    /// @param execType The execution type, which can be DEFAULT (revert on failure) or TRY (return on failure).
    function _handleBatchExecution(bytes calldata executionCalldata, ExecType execType) private {
        Execution[] calldata executions = executionCalldata.decodeBatch();
        if (execType == EXECTYPE_DEFAULT) _executeBatch(executions);
        else if (execType == EXECTYPE_TRY) _tryExecuteBatch(executions);
        else revert UnsupportedExecType(execType);
    }

    /// @notice Checks if a module is installed on the smart account.
    /// @param moduleTypeId The module type ID.
    /// @param module The module address.
    /// @param additionalContext Additional context for checking installation.
    /// @return True if the module is installed, false otherwise.
    function _isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext) private view returns (bool) {
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            return _isValidatorInstalled(module);
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            return _isExecutorInstalled(module);
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            if (additionalContext.length < 4) return false;
            return _isFallbackHandlerInstalled(bytes4(additionalContext[0:4]), module);
        } else if (moduleTypeId == MODULE_TYPE_HOOK) {
            return _isHookInstalled(module);
        } else {
            return false;
        }
    }

    /// @dev For use in `_erc1271HashForIsValidSignatureViaNestedEIP712`,
    function _typedDataSignFields() private view returns (bytes32 m) {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = eip712Domain();
        /// @solidity memory-safe-assembly
        assembly {
            m := mload(0x40) // Grab the free memory pointer.
            mstore(0x40, add(m, 0x120)) // Allocate the memory.
            // Skip 2 words: `TYPED_DATA_SIGN_TYPEHASH, contents`.
            mstore(add(m, 0x40), shl(248, byte(0, fields)))
            mstore(add(m, 0x60), keccak256(add(name, 0x20), mload(name)))
            mstore(add(m, 0x80), keccak256(add(version, 0x20), mload(version)))
            mstore(add(m, 0xa0), chainId)
            mstore(add(m, 0xc0), shr(96, shl(96, verifyingContract)))
            mstore(add(m, 0xe0), salt)
            mstore(add(m, 0x100), keccak256(add(extensions, 0x20), shl(5, mload(extensions))))
        }
    }
}
