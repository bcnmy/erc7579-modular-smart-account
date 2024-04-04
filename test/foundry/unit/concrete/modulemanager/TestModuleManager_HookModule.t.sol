// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../../utils/Imports.sol";
import "../../../utils/SmartAccountTestLab.t.sol";
import "../../shared/TestModuleManagement_Base.t.sol";

/**
 * @title TestHookModule
 * @dev Tests for installing and uninstalling the hook module in a smart account.
 */
contract TestHookModule is Test, TestModuleManagement_Base {

    function setUp() public {
        setUpModuleManagement_Base();
    }

    /**
     * @notice Tests the successful installation of the hook module.
     */
    function test_InstallHookModule_Success() public {
        // Ensure the hook module is not installed initially
        assertFalse(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook module should not be installed initially"
        );

        // Prepare call data for installing the hook module
        bytes memory callData = abi.encodeWithSelector(
            IModuleManager.installModule.selector,
            MODULE_TYPE_HOOK,
            address(HOOK_MODULE),
            ""
        );

        // Install the hook module
        installModule(callData, MODULE_TYPE_HOOK, address(HOOK_MODULE), EXECTYPE_DEFAULT);

        // Assert that the hook module is now installed
        assertTrue(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook module should be installed"
        );
    }

    function test_InstallHookModule_ReinstallationFailure() public {
       assertFalse(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook Module should not be installed initially"
        );
        test_InstallHookModule_Success();
        assertTrue(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook Module should be installed"
        );

        bytes memory callData = abi.encodeWithSelector(
            IModuleManager.installModule.selector, MODULE_TYPE_HOOK, address(HOOK_MODULE), ""
        );

        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(BOB_ACCOUNT), 0, callData);

        PackedUserOperation[] memory userOps = prepareUserOperation(BOB, BOB_ACCOUNT, EXECTYPE_DEFAULT, execution);

        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);

        bytes memory expectedRevertReason = abi.encodeWithSignature(
            "HookAlreadyInstalled(address)", MODULE_TYPE_HOOK, address(HOOK_MODULE)
        );

        // Expect the UserOperationRevertReason event
        vm.expectEmit(true, true, true, true);

        emit UserOperationRevertReason(
            userOpHash, // userOpHash
            address(BOB_ACCOUNT), // sender
            userOps[0].nonce, // nonce
            expectedRevertReason
        );

        ENTRYPOINT.handleOps(userOps, payable(address(BOB.addr)));

    }

    function test_UninstallHookModule_NotInstalledFailure() public {
        // Ensure the hook module is not installed
        assertFalse(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook module should not be installed initially"
        );

        // Attempt to uninstall the hook module
        bytes memory callData = abi.encodeWithSelector(
            IModuleManager.uninstallModule.selector,
            MODULE_TYPE_HOOK,
            address(HOOK_MODULE),
            ""
        );

        // Expect revert due to module not being installed
        vm.expectRevert("ModuleNotInstalled");
        uninstallHook(callData, address(HOOK_MODULE), EXECTYPE_DEFAULT);
    }

    function test_UninstallHookModule_Success() public {
        // Ensure the module is installed first
        test_InstallHookModule_Success();

        // Uninstall the hook module
        bytes memory callData = abi.encodeWithSelector(
            IModuleManager.uninstallModule.selector,
            MODULE_TYPE_HOOK,
            address(HOOK_MODULE),
            ""
        );
        uninstallHook(callData, address(HOOK_MODULE), EXECTYPE_DEFAULT);

        // Verify hook module is uninstalled
        assertFalse(
            BOB_ACCOUNT.isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""),
            "Hook module should be uninstalled"
        );
    }


    function uninstallHook(bytes memory callData, address module, ExecType execType) internal {
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(BOB_ACCOUNT), 0, callData);

        PackedUserOperation[] memory userOps = prepareUserOperation(BOB, BOB_ACCOUNT, execType, execution);

        // Emitting an event to capture the uninstallation attempt for assertion in tests
        vm.expectEmit(true, true, true, true);
        emit ModuleUninstalled(MODULE_TYPE_HOOK, module);

        // Handling the operation which includes calling the uninstallModule function on the smart account
        ENTRYPOINT.handleOps(userOps, payable(address(BOB.addr)));
    }
}