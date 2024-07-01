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
// Learn more at https://biconomy.io. For security issues, contact: security@biconomy.io

import { ModuleManager } from "../base/ModuleManager.sol";
import { IModule } from "../interfaces/modules/IModule.sol";
import { IERC7484 } from "../interfaces/IERC7484.sol";

/// @title Bootstrap Configuration for Nexus
/// @notice Provides configuration and initialization for Nexus smart accounts.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
struct BootstrapConfig {
    address module;
    bytes data;
}

/// @title Bootstrap
/// @notice Manages the installation of modules into Nexus smart accounts using delegatecalls.
contract Bootstrap is ModuleManager {
    /// @notice Initializes the Nexus account with a single validator.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validator The address of the validator module.
    /// @param data The initialization data for the validator module.
    function initNexusWithSingleValidator(
        IModule validator,
        bytes calldata data,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external {
        _installValidator(address(validator), data);
        _configureRegistry(registry, attesters, threshold);
    }

    /// @notice Initializes the Nexus account with multiple modules.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validators The configuration array for validator modules.
    /// @param executors The configuration array for executor modules.
    /// @param hook The configuration for the hook module.
    /// @param fallbacks The configuration array for fallback handler modules.
    function initNexus(
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external {
        // Initialize validators
        for (uint256 i = 0; i < validators.length; i++) {
            _installValidator(validators[i].module, validators[i].data);
        }

        // Initialize executors
        for (uint256 i = 0; i < executors.length; i++) {
            if (executors[i].module == address(0)) continue;
            _installExecutor(executors[i].module, executors[i].data);
        }

        // Initialize hook
        if (hook.module != address(0)) {
            _installHook(hook.module, hook.data);
        }

        // Initialize fallback handlers
        for (uint256 i = 0; i < fallbacks.length; i++) {
            if (fallbacks[i].module == address(0)) continue;
            _installFallbackHandler(fallbacks[i].module, fallbacks[i].data);
        }

        _configureRegistry(registry, attesters, threshold);
    }

    /// @notice Initializes the Nexus account with a scoped set of modules.
    /// @dev Intended to be called by the Nexus with a delegatecall.
    /// @param validators The configuration array for validator modules.
    /// @param hook The configuration for the hook module.
    function initNexusScoped(
        BootstrapConfig[] calldata validators,
        BootstrapConfig calldata hook,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external {
        // Initialize validators
        for (uint256 i = 0; i < validators.length; i++) {
            _installValidator(validators[i].module, validators[i].data);
        }

        // Initialize hook
        if (hook.module != address(0)) {
            _installHook(hook.module, hook.data);
        }

        _configureRegistry(registry, attesters, threshold);
    }

    /// @notice Prepares calldata for the initNexus function.
    /// @param validators The configuration array for validator modules.
    /// @param executors The configuration array for executor modules.
    /// @param hook The configuration for the hook module.
    /// @param fallbacks The configuration array for fallback handler modules.
    /// @return init The prepared calldata for initNexus.
    function getInitNexusCalldata(
        BootstrapConfig[] calldata validators,
        BootstrapConfig[] calldata executors,
        BootstrapConfig calldata hook,
        BootstrapConfig[] calldata fallbacks,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external view returns (bytes memory init) {
        init = abi.encode(address(this), abi.encodeCall(this.initNexus, (validators, executors, hook, fallbacks, registry, attesters, threshold)));
    }

    /// @notice Prepares calldata for the initNexusScoped function.
    /// @param validators The configuration array for validator modules.
    /// @param hook The configuration for the hook module.
    /// @return init The prepared calldata for initNexusScoped.
    function getInitNexusScopedCalldata(
        BootstrapConfig[] calldata validators,
        BootstrapConfig calldata hook,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external view returns (bytes memory init) {
        init = abi.encode(address(this), abi.encodeCall(this.initNexusScoped, (validators, hook, registry, attesters, threshold)));
    }

    /// @notice Prepares calldata for the initNexusWithSingleValidator function.
    /// @param validator The configuration for the validator module.
    /// @return init The prepared calldata for initNexusWithSingleValidator.
    function getInitNexusWithSingleValidatorCalldata(
        BootstrapConfig calldata validator,
        IERC7484 registry,
        address[] calldata attesters,
        uint8 threshold
    ) external view returns (bytes memory init) {
        init = abi.encode(
            address(this),
            abi.encodeCall(this.initNexusWithSingleValidator, (IModule(validator.module), validator.data, registry, attesters, threshold))
        );
    }
}
