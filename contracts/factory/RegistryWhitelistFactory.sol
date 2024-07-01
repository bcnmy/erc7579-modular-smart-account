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

import { LibClone } from "solady/src/utils/LibClone.sol";
import { BytesLib } from "../lib/BytesLib.sol";
import { INexus } from "../interfaces/INexus.sol";
import { BootstrapConfig } from "../utils/RegistryBootstrap.sol";
import { AbstractNexusFactory } from "./AbstractNexusFactory.sol";
import { IERC7484 } from "../interfaces/IERC7484.sol";
import { MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK, MODULE_TYPE_HOOK } from "../types/Constants.sol";

/// @title RegistryFactory
/// @notice Factory for creating Nexus accounts with whitelisted modules. Ensures compliance with ERC-7579 and ERC-4337 standards.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract RegistryFactory is AbstractNexusFactory {
    IERC7484 public immutable REGISTRY;
    address[] public attesters;
    uint8 public threshold;

    /// @notice Error thrown when a non-whitelisted module is used.
    /// @param module The module address that is not whitelisted.
    error ModuleNotWhitelisted(address module);

    /// @notice Error thrown when a zero address is provided.
    error ZeroAddressNotAllowed();

    /// @notice Constructor to set the smart account implementation address and owner.
    /// @param implementation_ The address of the Nexus implementation to be used for all deployments.
    /// @param owner_ The address of the owner of the factory.
    constructor(
        address implementation_,
        address owner_,
        IERC7484 registry_,
        address[] memory attesters_,
        uint8 threshold_
    ) AbstractNexusFactory(implementation_, owner_) {
        require(owner_ != address(0), ZeroAddressNotAllowed());
        REGISTRY = registry_;
        attesters = attesters_;
        threshold = threshold_;
    }

    function addAttester(address attester) external onlyOwner {
        attesters.push(attester);
    }

    function removeAttester(address attester) external onlyOwner {
        for (uint256 i = 0; i < attesters.length; i++) {
            if (attesters[i] == attester) {
                attesters[i] = attesters[attesters.length - 1];
                attesters.pop();
                break;
            }
        }
    }

    function setThreshold(uint8 newThreshold) external onlyOwner {
        threshold = newThreshold;
    }

    /// @notice Creates a new Nexus account with the provided initialization data.
    /// @param initData Initialization data to be called on the new Smart Account.
    /// @param salt Unique salt for the Smart Account creation.
    /// @return The address of the newly created Nexus.
    function createAccount(bytes calldata initData, bytes32 salt) external payable override returns (address payable) {
        // Decode the initData to extract the call target and call data
        (, bytes memory callData) = abi.decode(initData, (address, bytes));

        // Extract the inner data by removing the first 4 bytes (the function selector)
        bytes memory innerData = BytesLib.slice(callData, 4, callData.length - 4);

        // Decode the call data to extract the parameters passed to initNexus
        (
            BootstrapConfig[] memory validators,
            BootstrapConfig[] memory executors,
            BootstrapConfig memory hook,
            BootstrapConfig[] memory fallbacks,
            ,

        ) = abi.decode(innerData, (BootstrapConfig[], BootstrapConfig[], BootstrapConfig, BootstrapConfig[], address[], uint8));

        // Ensure all modules are whitelisted
        for (uint256 i = 0; i < validators.length; i++) {
            require(isModuleAllowed(validators[i].module, MODULE_TYPE_VALIDATOR), ModuleNotWhitelisted(validators[i].module));
        }

        for (uint256 i = 0; i < executors.length; i++) {
            require(isModuleAllowed(executors[i].module, MODULE_TYPE_EXECUTOR), ModuleNotWhitelisted(executors[i].module));
        }

        require(isModuleAllowed(hook.module, MODULE_TYPE_HOOK), ModuleNotWhitelisted(hook.module));

        for (uint256 i = 0; i < fallbacks.length; i++) {
            require(isModuleAllowed(fallbacks[i].module, MODULE_TYPE_FALLBACK), ModuleNotWhitelisted(fallbacks[i].module));
        }

        // Compute the actual salt for deterministic deployment
        bytes32 actualSalt;
        assembly {
            let ptr := mload(0x40)
            let calldataLength := sub(calldatasize(), 0x04)
            mstore(0x40, add(ptr, calldataLength))
            calldatacopy(ptr, 0x04, calldataLength)
            actualSalt := keccak256(ptr, calldataLength)
        }

        // Deploy the account using the deterministic address
        (bool alreadyDeployed, address account) = LibClone.createDeterministicERC1967(msg.value, ACCOUNT_IMPLEMENTATION, actualSalt);

        if (!alreadyDeployed) {
            INexus(account).initializeAccount(initData);
            emit AccountCreated(account, initData, salt);
        }
        return payable(account);
    }

    /// @notice Computes the expected address of a Nexus contract using the factory's deterministic deployment algorithm.
    /// @param - Initialization data to be called on the new Smart Account.
    /// @param - Unique salt for the Smart Account creation.
    /// @return expectedAddress The expected address at which the Nexus contract will be deployed if the provided parameters are used.
    function computeAccountAddress(bytes calldata, bytes32) external view override returns (address payable expectedAddress) {
        bytes32 actualSalt;
        assembly {
            let ptr := mload(0x40)
            let calldataLength := sub(calldatasize(), 0x04)
            mstore(0x40, add(ptr, calldataLength))
            calldatacopy(ptr, 0x04, calldataLength)
            actualSalt := keccak256(ptr, calldataLength)
        }
        expectedAddress = payable(LibClone.predictDeterministicAddressERC1967(ACCOUNT_IMPLEMENTATION, actualSalt, address(this)));
    }

    /// @notice Checks if a module is whitelisted.
    /// @param module The address of the module to check.
    /// @return True if the module is whitelisted, false otherwise.
    function isModuleAllowed(address module, uint256 moduleType) public view returns (bool) {
        REGISTRY.check(module, moduleType, attesters, threshold);
        return true;
    }
}
