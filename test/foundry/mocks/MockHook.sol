// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IHook, MODULE_TYPE_HOOK } from "contracts/interfaces/modules/IERC7579Modules.sol";
import { IModule } from "contracts/interfaces/modules/IModule.sol";
import { EncodedModuleTypes } from "contracts/lib/ModuleTypeLib.sol";

contract MockHook is IHook {
    /// @inheritdoc IModule
    function onInstall(bytes calldata data) external override {}

    /// @inheritdoc IModule
    function onUninstall(bytes calldata data) external override {}

    /// @inheritdoc IHook
    function preCheck(address msgSender, bytes calldata msgData) external returns (bytes memory hookData) {}

    /// @inheritdoc IHook
    function postCheck(bytes calldata hookData) external returns (bool success) {}

    /// @inheritdoc IModule
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK;
    }

    /*function isInitialized(address smartAccount) external view returns (bool) {
        return false;
    }*/

    /// @inheritdoc IModule
    function getModuleTypes() external view override returns (EncodedModuleTypes) {}

    // Review
    function test(uint256 a) public {
        a;
    }
}
