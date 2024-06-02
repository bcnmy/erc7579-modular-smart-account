// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { BytesLib } from "../lib/BytesLib.sol";
import { INexus } from "../interfaces/INexus.sol";
import { BootstrapConfig } from "../utils/Bootstrap.sol";
import { AbstractNexusFactory } from "./AbstractNexusFactory.sol";

/// @title ModuleWhitelistFactory
/// @notice Factory for creating Nexus accounts with whitelisted modules. Ensures compliance with ERC-7579 and ERC-4337 standards.
contract ModuleWhitelistFactory is AbstractNexusFactory {
    /// @notice Mapping to store the addresses of whitelisted modules.
    mapping(address => bool) public moduleWhitelist;

    /// @notice Error thrown when a non-whitelisted module is used.
    /// @param module The module address that is not whitelisted.
    error ModuleNotWhitelisted(address module);

    /// @notice Error thrown when a zero address is provided.
    error ZeroAddressNotAllowed();

    /// @notice Constructor to set the smart account implementation address and owner.
    /// @param implementation_ The address of the Nexus implementation to be used for all deployments.
    /// @param owner_ The address of the owner of the factory.
    constructor(address implementation_, address owner_) AbstractNexusFactory(implementation_, owner_) {
        if (owner_ == address(0)) {
            revert ZeroAddressNotAllowed();
        }
    }

    /// @notice Adds an address to the module whitelist.
    /// @param module The address to be whitelisted.
    function addModuleToWhitelist(address module) external onlyOwner {
        if (module == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        moduleWhitelist[module] = true;
    }

    /// @notice Removes an address from the module whitelist.
    /// @param module The address to be removed from the whitelist.
    function removeModuleFromWhitelist(address module) external onlyOwner {
        moduleWhitelist[module] = false;
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
            BootstrapConfig[] memory fallbacks
        ) = abi.decode(innerData, (BootstrapConfig[], BootstrapConfig[], BootstrapConfig, BootstrapConfig[]));

        // Ensure all modules are whitelisted
        for (uint256 i = 0; i < validators.length; i++) {
            if (!isModuleWhitelisted(validators[i].module)) {
                revert ModuleNotWhitelisted(validators[i].module);
            }
        }

        for (uint256 i = 0; i < executors.length; i++) {
            if (!isModuleWhitelisted(executors[i].module)) {
                revert ModuleNotWhitelisted(executors[i].module);
            }
        }

        if (!isModuleWhitelisted(hook.module)) {
            revert ModuleNotWhitelisted(hook.module);
        }

        for (uint256 i = 0; i < fallbacks.length; i++) {
            if (!isModuleWhitelisted(fallbacks[i].module)) {
                revert ModuleNotWhitelisted(fallbacks[i].module);
            }
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
    function isModuleWhitelisted(address module) public view returns (bool) {
        return moduleWhitelist[module];
    }
}
