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

import { Receiver } from "solady/src/accounts/Receiver.sol";
import { SentinelListLib } from "sentinellist/src/SentinelList.sol";

import { Storage } from "./Storage.sol";
import { IHook } from "../interfaces/modules/IHook.sol";
import { IExecutor } from "../interfaces/modules/IExecutor.sol";
import { IFallback } from "../interfaces/modules/IFallback.sol";
import { IValidator } from "../interfaces/modules/IValidator.sol";
import { CallType, CALLTYPE_SINGLE, CALLTYPE_STATIC } from "../lib/ModeLib.sol";
import { IModuleManagerEventsAndErrors } from "../interfaces/base/IModuleManagerEventsAndErrors.sol";
import { RegistryAdapter } from "./RegistryAdapter.sol";
import { MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK, MODULE_TYPE_HOOK } from "../types/Constants.sol";

/// @title Nexus - ModuleManager
/// @notice Manages Validator, Executor, Hook, and Fallback modules within the Nexus suite, supporting
/// @dev Implements SentinelList for managing modules via a linked list structure, adhering to ERC-7579.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract ModuleManager is Storage, Receiver, IModuleManagerEventsAndErrors, RegistryAdapter {
    using SentinelListLib for SentinelListLib.SentinelList;

    /// @notice Ensures the message sender is a registered executor module.
    modifier onlyExecutorModule() virtual {
        require(_getAccountStorage().executors.contains(msg.sender), InvalidModule(msg.sender));
        _;
    }

    /// @notice Does pre-checks and post-checks using an installed hook on the account.
    /// @dev sender, msg.data and msg.value is passed to the hook to implement custom flows.
    modifier withHook() {
        address hook = _getHook();
        if (hook == address(0)) {
            _;
        } else {
            bytes memory hookData = IHook(hook).preCheck(msg.sender, msg.value, msg.data);
            _;
            IHook(hook).postCheck(hookData);
        }
    }

    /// @dev Fallback function to manage incoming calls using designated handlers based on the call type.
    fallback() external payable override(Receiver) receiverFallback {
        FallbackHandler storage $fallbackHandler = _getAccountStorage().fallbacks[msg.sig];
        address handler = $fallbackHandler.handler;
        CallType calltype = $fallbackHandler.calltype;
        require(handler != address(0), MissingFallbackHandler(msg.sig));

        if (calltype == CALLTYPE_STATIC) {
            assembly {
                calldatacopy(0, 0, calldatasize())

                // The msg.sender address is shifted to the left by 12 bytes to remove the padding
                // Then the address without padding is stored right after the calldata
                mstore(calldatasize(), shl(96, caller()))

                if iszero(staticcall(gas(), handler, 0, add(calldatasize(), 20), 0, 0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                returndatacopy(0, 0, returndatasize())
                return(0, returndatasize())
            }
        }
        if (calltype == CALLTYPE_SINGLE) {
            assembly {
                calldatacopy(0, 0, calldatasize())

                // The msg.sender address is shifted to the left by 12 bytes to remove the padding
                // Then the address without padding is stored right after the calldata
                mstore(calldatasize(), shl(96, caller()))

                if iszero(call(gas(), handler, 0, 0, add(calldatasize(), 20), 0, 0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                returndatacopy(0, 0, returndatasize())
                return(0, returndatasize())
            }
        }
    }

    /// @dev Retrieves a paginated list of validator addresses from the linked list.
    /// This utility function is not defined by the ERC-7579 standard and is implemented to facilitate
    /// easier management and retrieval of large sets of validator modules.
    /// @param cursor The address to start pagination from, or zero to start from the first entry.
    /// @param size The number of validator addresses to return.
    /// @return array An array of validator addresses.
    /// @return next The address to use as a cursor for the next page of results.
    function getValidatorsPaginated(address cursor, uint256 size) external view returns (address[] memory array, address next) {
        (array, next) = _paginate(_getAccountStorage().validators, cursor, size);
    }

    /// @dev Retrieves a paginated list of executor addresses from the linked list.
    /// This utility function is not defined by the ERC-7579 standard and is implemented to facilitate
    /// easier management and retrieval of large sets of executor modules.
    /// @param cursor The address to start pagination from, or zero to start from the first entry.
    /// @param size The number of executor addresses to return.
    /// @return array An array of executor addresses.
    /// @return next The address to use as a cursor for the next page of results.
    function getExecutorsPaginated(address cursor, uint256 size) external view returns (address[] memory array, address next) {
        (array, next) = _paginate(_getAccountStorage().executors, cursor, size);
    }

    /// @notice Retrieves the currently active hook address.
    /// @return hook The address of the active hook module.
    function getActiveHook() external view returns (address hook) {
        return _getHook();
    }

    /// @notice Fetches the fallback handler for a specific selector.
    /// @param selector The function selector to query.
    /// @return calltype The type of call that the handler manages.
    /// @return handler The address of the fallback handler.
    function getFallbackHandlerBySelector(bytes4 selector) external view returns (CallType, address) {
        FallbackHandler memory handler = _getAccountStorage().fallbacks[selector];
        return (handler.calltype, handler.handler);
    }

    /// @dev Initializes the module manager by setting up default states for validators and executors.
    function _initModuleManager() internal virtual {
        // account module storage
        AccountStorage storage ams = _getAccountStorage();
        ams.executors.init();
        ams.validators.init();
    }

    /// @dev Installs a new validator module after checking if it matches the required module type.
    /// @param validator The address of the validator module to be installed.
    /// @param data Initialization data to configure the validator upon installation.
    function _installValidator(address validator, bytes calldata data) internal virtual withRegistry(validator, MODULE_TYPE_VALIDATOR) {
        _getAccountStorage().validators.push(validator);
        IValidator(validator).onInstall(data);
    }

    /// @dev Uninstalls a validator module /!\ ensuring the account retains at least one validator.
    /// @param validator The address of the validator to be uninstalled.
    /// @param data De-initialization data to configure the validator upon uninstallation.
    function _uninstallValidator(address validator, bytes calldata data) internal virtual {
        SentinelListLib.SentinelList storage validators = _getAccountStorage().validators;

        (address prev, bytes memory disableModuleData) = abi.decode(data, (address, bytes));

        // Check if the account has at least one validator installed before proceeding
        // Having at least one validator is a requirement for the account to function properly
        require(!(prev == address(0x01) && validators.getNext(validator) == address(0x01)), CannotRemoveLastValidator());

        validators.pop(prev, validator);
        IValidator(validator).onUninstall(disableModuleData);
    }

    /// @dev Installs a new executor module after checking if it matches the required module type.
    /// @param executor The address of the executor module to be installed.
    /// @param data Initialization data to configure the executor upon installation.
    function _installExecutor(address executor, bytes calldata data) internal virtual withRegistry(executor, MODULE_TYPE_EXECUTOR) {
        _getAccountStorage().executors.push(executor);
        IExecutor(executor).onInstall(data);
    }

    /// @dev Uninstalls an executor module by removing it from the executors list.
    /// @param executor The address of the executor to be uninstalled.
    /// @param data De-initialization data to configure the executor upon uninstallation.
    function _uninstallExecutor(address executor, bytes calldata data) internal virtual {
        (address prev, bytes memory disableModuleData) = abi.decode(data, (address, bytes));
        _getAccountStorage().executors.pop(prev, executor);
        IExecutor(executor).onUninstall(disableModuleData);
    }

    /// @dev Installs a hook module, ensuring no other hooks are installed before proceeding.
    /// @param hook The address of the hook to be installed.
    /// @param data Initialization data to configure the hook upon installation.
    function _installHook(address hook, bytes calldata data) internal virtual withRegistry(hook, MODULE_TYPE_HOOK) {
        address currentHook = _getHook();
        require(currentHook == address(0), HookAlreadyInstalled(currentHook));
        _setHook(hook);
        IHook(hook).onInstall(data);
    }

    /// @dev Uninstalls a hook module, ensuring the current hook matches the one intended for uninstallation.
    /// @param hook The address of the hook to be uninstalled.
    /// @param data De-initialization data to configure the hook upon uninstallation.
    function _uninstallHook(address hook, bytes calldata data) internal virtual {
        _setHook(address(0));
        IHook(hook).onUninstall(data);
    }

    /// @dev Sets the current hook in the storage to the specified address.
    /// @param hook The new hook address.
    function _setHook(address hook) internal virtual {
        _getAccountStorage().hook = IHook(hook);
    }

    /// @dev Installs a fallback handler for a given selector with initialization data.
    /// @param handler The address of the fallback handler to install.
    /// @param params The initialization parameters including the selector and call type.
    function _installFallbackHandler(address handler, bytes calldata params) internal virtual withRegistry(handler, MODULE_TYPE_FALLBACK) {
        // Extract the function selector from the provided parameters.
        bytes4 selector = bytes4(params[0:4]);

        // Extract the call type from the provided parameters.
        CallType calltype = CallType.wrap(bytes1(params[4]));

        // Extract the initialization data from the provided parameters.
        bytes memory initData = params[5:];

        // Revert if the selector is either `onInstall(bytes)` (0x6d61fe70) or `onUninstall(bytes)` (0x8a91b0e3).
        // These selectors are explicitly forbidden to prevent security vulnerabilities.
        // Allowing these selectors would enable unauthorized users to uninstall and reinstall critical modules.
        // If a validator module is uninstalled and reinstalled without proper authorization, it can compromise
        // the account's security and integrity. By restricting these selectors, we ensure that the fallback handler
        // cannot be manipulated to disrupt the expected behavior and security of the account.
        require(!(selector == bytes4(0x6d61fe70) || selector == bytes4(0x8a91b0e3)), FallbackSelectorForbidden());

        // Revert if a fallback handler is already installed for the given selector.
        // This check ensures that we do not overwrite an existing fallback handler, which could lead to unexpected behavior.
        require(!_isFallbackHandlerInstalled(selector), FallbackAlreadyInstalledForSelector(selector));

        // Store the fallback handler and its call type in the account storage.
        // This maps the function selector to the specified fallback handler and call type.
        _getAccountStorage().fallbacks[selector] = FallbackHandler(handler, calltype);

        // Invoke the `onInstall` function of the fallback handler with the provided initialization data.
        // This step allows the fallback handler to perform any necessary setup or initialization.
        IFallback(handler).onInstall(initData);
    }

    /// @dev Uninstalls a fallback handler for a given selector.
    /// @param fallbackHandler The address of the fallback handler to uninstall.
    /// @param data The de-initialization data containing the selector.
    function _uninstallFallbackHandler(address fallbackHandler, bytes calldata data) internal virtual {
        _getAccountStorage().fallbacks[bytes4(data[0:4])] = FallbackHandler(address(0), CallType.wrap(0x00));
        IFallback(fallbackHandler).onUninstall(data[4:]);
    }

    /// @dev Checks if a fallback handler is set for a given selector.
    /// @param selector The function selector to check.
    /// @return True if a fallback handler is set, otherwise false.
    function _isFallbackHandlerInstalled(bytes4 selector) internal view virtual returns (bool) {
        FallbackHandler storage handler = _getAccountStorage().fallbacks[selector];
        return handler.handler != address(0);
    }

    /// @dev Checks if the expected fallback handler is installed for a given selector.
    /// @param selector The function selector to check.
    /// @param expectedHandler The address of the handler expected to be installed.
    /// @return True if the installed handler matches the expected handler, otherwise false.
    function _isFallbackHandlerInstalled(bytes4 selector, address expectedHandler) internal view returns (bool) {
        FallbackHandler storage handler = _getAccountStorage().fallbacks[selector];
        return handler.handler == expectedHandler;
    }

    /// @dev Checks if a validator is currently installed.
    /// @param validator The address of the validator to check.
    /// @return True if the validator is installed, otherwise false.
    function _isValidatorInstalled(address validator) internal view virtual returns (bool) {
        return _getAccountStorage().validators.contains(validator);
    }

    /// @dev Checks if an executor is currently installed.
    /// @param executor The address of the executor to check.
    /// @return True if the executor is installed, otherwise false.
    function _isExecutorInstalled(address executor) internal view virtual returns (bool) {
        return _getAccountStorage().executors.contains(executor);
    }

    /// @dev Checks if a hook is currently installed.
    /// @param hook The address of the hook to check.
    /// @return True if the hook is installed, otherwise false.
    function _isHookInstalled(address hook) internal view returns (bool) {
        return _getHook() == hook;
    }

    /// @dev Retrieves the current hook from the storage.
    /// @return hook The address of the current hook.
    function _getHook() internal view returns (address hook) {
        hook = address(_getAccountStorage().hook);
    }

    /// @dev Helper function to paginate entries in a SentinelList.
    /// @param list The SentinelList to paginate.
    /// @param cursor The cursor to start paginating from.
    /// @param size The number of entries to return.
    /// @return array The array of addresses in the list.
    /// @return nextCursor The cursor for the next page of entries.
    function _paginate(
        SentinelListLib.SentinelList storage list,
        address cursor,
        uint256 size
    ) private view returns (address[] memory array, address nextCursor) {
        (array, nextCursor) = list.getEntriesPaginated(cursor, size);
    }
}
