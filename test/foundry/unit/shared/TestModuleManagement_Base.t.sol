// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../utils/Imports.sol";
import "../../utils/SmartAccountTestLab.t.sol";
import {MockValidator} from "../../mocks/MockValidator.sol";
import {MockExecutor} from "../../mocks/MockExecutor.sol";

event ModuleInstalled(uint256 moduleTypeId, address module);
event ModuleUninstalled(uint256 moduleTypeId, address module);
event UserOperationRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason);

abstract contract TestModuleManagement_Base is Test, SmartAccountTestLab {
    MockValidator public mockValidator;
    MockExecutor public mockExecutor;

    address constant INVALID_MODULE_ADDRESS = address(0);
    uint256 constant INVALID_MODULE_TYPE = 999;
    // More shared state variables if needed

    function setUpModuleManagement_Base() internal {
        init(); // Initialize the testing environment if necessary

        // Setup mock validator and executor, different from those possibly already used
        mockValidator = new MockValidator();
        mockExecutor = new MockExecutor();
        // Additional shared setup can go here
    }

    // Shared utility and helper functions to install/uninstall modules
    function installModule(
        bytes memory callData,
        uint256 moduleTypeId,
        address moduleAddress,
        ExecType execType
    ) internal {


        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(BOB_ACCOUNT), 0, callData);

        PackedUserOperation[] memory userOps = prepareUserOperation(
            BOB,
            BOB_ACCOUNT,
            execType,
            execution
        );

        vm.expectEmit(true, true, true, true);
        emit ModuleInstalled(moduleTypeId, moduleAddress);

        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));
    }

    function uninstallModule(bytes memory callData, uint256 moduleTypeId, address moduleAddress, ExecType execType) internal {

        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(BOB_ACCOUNT), 0, callData);

        // Similar to installModule but for uninstallation
        PackedUserOperation[] memory userOps = prepareUserOperation(
            BOB,
            BOB_ACCOUNT,
            execType,
            execution
        );

        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));
    }
}
