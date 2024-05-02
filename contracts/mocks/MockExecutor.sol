// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IModule } from "contracts/interfaces/modules/IModule.sol";
import { EncodedModuleTypes } from "contracts/lib/ModuleTypeLib.sol";
import { INexus } from "contracts/interfaces/INexus.sol";
import { MODULE_TYPE_EXECUTOR } from "contracts/types/Constants.sol";
import { ModeLib } from "contracts/lib/ModeLib.sol";
import { ExecLib } from "contracts/lib/ExecLib.sol";
import { IExecutor } from "../../contracts/interfaces/modules/IExecutor.sol";
import "../../contracts/types/DataTypes.sol";

contract MockExecutor is IExecutor {
    function onInstall(bytes calldata data) external override {}

    function onUninstall(bytes calldata data) external override {}

    function executeViaAccount(INexus account, address target, uint256 value, bytes calldata callData) external returns (bytes[] memory returnData) {
        return account.executeFromExecutor(ModeLib.encodeSimpleSingle(), ExecLib.encodeSingle(target, value, callData));
    }

    function executeBatchViaAccount(INexus account, Execution[] calldata execs) external returns (bytes[] memory returnData) {
        return account.executeFromExecutor(ModeLib.encodeSimpleBatch(), ExecLib.encodeBatch(execs));
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    function getModuleTypes() external view returns (EncodedModuleTypes) {}

    function test_() public pure {
        // This function is used to ignore file in coverage report
    }

    function isInitialized(address) external pure override returns (bool) {
        return false;
    }
}
