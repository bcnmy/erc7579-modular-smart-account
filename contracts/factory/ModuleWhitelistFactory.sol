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
import { BootstrapConfig } from "../utils/Bootstrap.sol";
import { Stakeable } from "../common/Stakeable.sol";
import { INexusFactory } from "../interfaces/factory/INexusFactory.sol";

/// @title ModuleWhitelistFactory
/// @notice Factory for creating Nexus accounts with whitelisted modules. Ensures compliance with ERC-7579 and ERC-4337 standards.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract ModuleWhitelistFactory is Stakeable, INexusFactory {
    /// @notice Address of the implementation contract used to create new Nexus instances.
    /// @dev This address is immutable and set upon deployment, ensuring the implementation cannot be changed.
    address public immutable ACCOUNT_IMPLEMENTATION;

    /// @notice Mapping to store the addresses of whitelisted modules.
    mapping(address => bool) public moduleWhitelist;

    /// @notice Error thrown when a non-whitelisted module is used.
    /// @param module The module address that is not whitelisted.
    error ModuleNotWhitelisted(address module);

    /// @notice Constructor to set the smart account implementation address and the factory owner.
    /// @param implementation_ The address of the Nexus implementation to be used for all deployments.
    /// @param owner_ The address of the owner of the factory.
    constructor(address implementation_, address owner_) Stakeable(owner_) {
        require(implementation_ != address(0), ImplementationAddressCanNotBeZero());
        require(owner_ != address(0), ZeroAddressNotAllowed());
        ACCOUNT_IMPLEMENTATION = implementation_;
    }
    /// @notice Adds an address to the module whitelist.
    /// @param module The address to be whitelisted.
    function addModuleToWhitelist(address module) external onlyOwner {
        require(module != address(0), ZeroAddressNotAllowed());
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
            require(isModuleWhitelisted(validators[i].module), ModuleNotWhitelisted(validators[i].module));
        }

        for (uint256 i = 0; i < executors.length; i++) {
            require(isModuleWhitelisted(executors[i].module), ModuleNotWhitelisted(executors[i].module));
        }

        require(isModuleWhitelisted(hook.module), ModuleNotWhitelisted(hook.module));

        for (uint256 i = 0; i < fallbacks.length; i++) {
            require(isModuleWhitelisted(fallbacks[i].module), ModuleNotWhitelisted(fallbacks[i].module));
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
