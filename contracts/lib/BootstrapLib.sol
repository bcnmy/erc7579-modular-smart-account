// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BootstrapConfig } from "../utils/RegistryBootstrap.sol";

/// @title Bootstrap Configuration Library
/// @notice Provides utility functions to create and manage BootstrapConfig structures.
/// @author @livingrockrises | Biconomy | chirag@biconomy.io
/// @author @aboudjem | Biconomy | adam.boudjemaa@biconomy.io
/// @author @filmakarov | Biconomy | filipp.makarov@biconomy.io
/// @author @zeroknots | Rhinestone.wtf | zeroknots.eth
/// Special thanks to the Solady team for foundational contributions: https://github.com/Vectorized/solady
library BootstrapLib {
    /// @notice Creates a single BootstrapConfig structure.
    /// @param module The address of the module.
    /// @param data The initialization data for the module.
    /// @return config A BootstrapConfig structure containing the module and its data.
    function createSingleConfig(address module, bytes memory data) public pure returns (BootstrapConfig memory config) {
        config.module = module;
        config.data = data;
    }

    /// @notice Creates an array with a single BootstrapConfig structure.
    /// @param module The address of the module.
    /// @param data The initialization data for the module.
    /// @return config An array containing a single BootstrapConfig structure.
    function createArrayConfig(address module, bytes memory data) public pure returns (BootstrapConfig[] memory config) {
        config = new BootstrapConfig[](1);
        config[0].module = module;
        config[0].data = data;
    }

    /// @notice Creates an array of BootstrapConfig structures.
    /// @param modules An array of module addresses.
    /// @param datas An array of initialization data for each module.
    /// @return configs An array of BootstrapConfig structures.
    function createMultipleConfigs(address[] memory modules, bytes[] memory datas) public pure returns (BootstrapConfig[] memory configs) {
        require(modules.length == datas.length, "BootstrapLib: length mismatch");
        configs = new BootstrapConfig[](modules.length);

        for (uint256 i = 0; i < modules.length; i++) {
            configs[i] = createSingleConfig(modules[i], datas[i]);
        }
    }
}
