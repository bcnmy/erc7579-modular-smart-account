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

import { LibClone } from "solady/src/utils/LibClone.sol";
import { INexus } from "../interfaces/INexus.sol";
import { BootstrapLib } from "../lib/BootstrapLib.sol";
import { Bootstrap, BootstrapConfig } from "../utils/RegistryBootstrap.sol";
import { Stakeable } from "../common/Stakeable.sol";
import { IERC7484 } from "../interfaces/IERC7484.sol";

/// @title K1ValidatorFactory for Nexus Account
/// @notice Manages the creation of Modular Smart Accounts compliant with ERC-7579 and ERC-4337 using a K1 validator.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
contract K1ValidatorFactory is Stakeable {
    /// @notice Stores the implementation contract address used to create new Nexus instances.
    /// @dev This address is set once upon deployment and cannot be changed afterwards.
    address public immutable ACCOUNT_IMPLEMENTATION;

    /// @notice Stores the K1 Validator module address.
    /// @dev This address is set once upon deployment and cannot be changed afterwards.
    address public immutable K1_VALIDATOR;

    /// @notice Stores the Bootstrapper module address.
    /// @dev This address is set once upon deployment and cannot be changed afterwards.
    Bootstrap public immutable BOOTSTRAPPER;

    IERC7484 public immutable REGISTRY;

    /// @notice Emitted when a new Smart Account is created, capturing the account details and associated module configurations.
    event AccountCreated(address indexed account, address indexed owner, uint256 indexed index);

    /// @notice Error thrown when a zero address is provided for the implementation, K1 validator, or bootstrapper.
    error ZeroAddressNotAllowed();

    /// @notice Constructor to set the immutable variables.
    /// @param implementation The address of the Nexus implementation to be used for all deployments.
    /// @param factoryOwner The address of the factory owner.
    /// @param k1Validator The address of the K1 Validator module to be used for all deployments.
    /// @param bootstrapper The address of the Bootstrapper module to be used for all deployments.
    constructor(
        address implementation,
        address factoryOwner,
        address k1Validator,
        Bootstrap bootstrapper,
        IERC7484 registry
    ) Stakeable(factoryOwner) {
        require(!(implementation == address(0) || k1Validator == address(0) || address(bootstrapper) == address(0)), ZeroAddressNotAllowed());
        ACCOUNT_IMPLEMENTATION = implementation;
        K1_VALIDATOR = k1Validator;
        BOOTSTRAPPER = bootstrapper;
        REGISTRY = registry;
    }

    /// @notice Creates a new Nexus with a specific validator and initialization data.
    /// @param eoaOwner The address of the EOA owner of the Nexus.
    /// @param index The index of the Nexus.
    /// @return The address of the newly created Nexus.
    function createAccount(
        address eoaOwner,
        uint256 index,
        address[] calldata attesters,
        uint8 threshold
    ) external payable returns (address payable) {
        // Compute the actual salt for deterministic deployment
        bytes32 actualSalt;
        assembly {
            let ptr := mload(0x40)
            let calldataLength := sub(calldatasize(), 0x04)
            mstore(0x40, add(ptr, calldataLength))
            calldatacopy(ptr, 0x04, calldataLength)
            actualSalt := keccak256(ptr, calldataLength)
        }

        // Deploy the Nexus contract using the computed salt
        (bool alreadyDeployed, address account) = LibClone.createDeterministicERC1967(msg.value, ACCOUNT_IMPLEMENTATION, actualSalt);

        // Create the validator configuration using the Bootstrap library
        BootstrapConfig memory validator = BootstrapLib.createSingleConfig(K1_VALIDATOR, abi.encodePacked(eoaOwner));
        bytes memory initData = BOOTSTRAPPER.getInitNexusWithSingleValidatorCalldata(validator, REGISTRY, attesters, threshold);

        // Initialize the account if it was not already deployed
        if (!alreadyDeployed) {
            INexus(account).initializeAccount(initData);
            emit AccountCreated(account, eoaOwner, index);
        }
        return payable(account);
    }

    /// @notice Computes the expected address of a Nexus contract using the factory's deterministic deployment algorithm.
    /// @param - The address of the EOA owner of the Nexus.
    /// @param - The index of the Nexus.
    /// @return expectedAddress The expected address at which the Nexus contract will be deployed if the provided parameters are used.
    function computeAccountAddress(address, uint256, address[] calldata, uint8) external view returns (address payable expectedAddress) {
        // Compute the actual salt for deterministic deployment
        bytes32 actualSalt;
        assembly {
            let ptr := mload(0x40)
            let calldataLength := sub(calldatasize(), 0x04)
            mstore(0x40, add(ptr, calldataLength))
            calldatacopy(ptr, 0x04, calldataLength)
            actualSalt := keccak256(ptr, calldataLength)
        }

        // Predict the deterministic address using the LibClone library
        expectedAddress = payable(LibClone.predictDeterministicAddressERC1967(ACCOUNT_IMPLEMENTATION, actualSalt, address(this)));
    }
}
