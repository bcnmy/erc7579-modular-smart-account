// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC7484 } from "../interfaces/IERC7484.sol";

/**
 * IERC7484 Registry adapter.
 * this feature is opt-in. The smart account owner can choose to use the registry and which
 * attesters to trust
 */
abstract contract RegistryAdapter {
    IERC7484 public registry;

    event ERC7484RegistryConfigured(IERC7484 indexed registry);

    modifier withRegistry(address module, uint256 moduleType) {
        _checkRegistry(module, moduleType);
        _;
    }

    /**
     * Configure ERC7484 Registry for Account
     */
    function _configureRegistry(IERC7484 newRegistry, address[] calldata attesters, uint8 threshold) internal {
        registry = newRegistry;
        if (address(newRegistry) != address(0)) {
            newRegistry.trustAttesters(threshold, attesters);
        }
        emit ERC7484RegistryConfigured(newRegistry);
    }

    /**
     * Check on ERC7484 Registry, if suffcient attestations were made
     * This will revert, if not succicient valid attestations are on the registry
     */
    function _checkRegistry(address module, uint256 moduleType) internal view {
        IERC7484 moduleRegistry = registry;
        if (address(moduleRegistry) != address(0)) {
            // this will revert if attestations / threshold are not met
            moduleRegistry.check(module, moduleType);
        }
    }
}
