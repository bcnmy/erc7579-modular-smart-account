// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/Imports.sol";
import { InvariantBaseTest } from "./base/InvariantBaseTest.t.sol";
import { ExecutionHandlerTest } from "./handlers/ExecutionHandlerTest.t.sol";
import { AccountCreationHandlerTest } from "./handlers/AccountCreationHandlerTest.t.sol";
import { ModuleManagementHandlerTest } from "./handlers/ModuleManagementHandlerTest.t.sol";
import { DepositManagementHandlerTest } from "./handlers/DepositManagementHandlerTest.t.sol";

/// @title ActorManagerInvariantTest
/// @notice Coordinates test actions across different actors using handlers.
/// @dev Actors represent different user accounts, and handlers manage the specific actions they perform in the invariant tests.
contract ActorManagerInvariantTest is InvariantBaseTest {
    struct ActorHandlers {
        DepositManagementHandlerTest depositHandler;
        ModuleManagementHandlerTest moduleHandler;
        ExecutionHandlerTest executionHandler;
        AccountCreationHandlerTest accountCreationHandler;
    }

    ActorHandlers[] public actorHandlers;
    address public validationModule;

    /// @notice Initializes handlers for each actor.
    /// @dev Actors represent different user accounts participating in the tests, and handlers manage the actions they perform.
    function setUp() public override {
        super.setUp();
        setUpActors();
    }

    /// @notice Initializes handlers for each actor.
    function setUpActors() internal {
        Vm.Wallet[3] memory actors = [ALICE, BOB, CHARLIE];
        Nexus[3] memory actorAccounts = [ALICE_ACCOUNT, BOB_ACCOUNT, CHARLIE_ACCOUNT];
        validationModule = address(VALIDATOR_MODULE);

        for (uint i = 0; i < actors.length; i++) {
            DepositManagementHandlerTest depositHandler = new DepositManagementHandlerTest(actorAccounts[i], actors[i], address(VALIDATOR_MODULE));
            ModuleManagementHandlerTest moduleHandler = new ModuleManagementHandlerTest(actorAccounts[i], actors[i]);
            AccountCreationHandlerTest accountCreationHandler = new AccountCreationHandlerTest(FACTORY, validationModule, actors[i].addr);
            ExecutionHandlerTest executionHandler = new ExecutionHandlerTest(actorAccounts[i], actors[i]);

            actorHandlers.push(
                ActorHandlers({
                    depositHandler: depositHandler,
                    executionHandler: executionHandler,
                    moduleHandler: moduleHandler,
                    accountCreationHandler: accountCreationHandler
                })
            );
        }

        // Target contracts for fuzzing
        for (uint i = 0; i < actorHandlers.length; i++) {
            targetContract(address(actorHandlers[i].moduleHandler));
            targetContract(address(actorHandlers[i].executionHandler));
            targetContract(address(actorHandlers[i].depositHandler));
            targetContract(address(actorHandlers[i].accountCreationHandler));
        }
    }

    //--------------------------------------------------------------
    // Account Creation Tests
    //--------------------------------------------------------------

    /// @notice Test account creation across all actors.
    function invariant_CreateAccount() public {
        uint256 index = 0;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].accountCreationHandler.invariant_createAccount((index++));
        }
    }

    /// @notice Test nonce consistency across all actors.
    function invariant_testNonceConsistency() public {
        uint256 index = 1;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].accountCreationHandler.invariant_nonceConsistency((index++));
        }
    }

    /// @notice Test nonce reset on account creation across all actors.
    function invariant_testNonceResetOnCreation() public {
        uint256 index = 1;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].accountCreationHandler.invariant_nonceResetOnCreation((index++));
        }
    }

    /// @notice Test multiple account creation with unique indices across all actors.
    function invariant_testMultipleAccountCreationWithUniqueIndices() public {
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].accountCreationHandler.invariant_multipleAccountCreationWithUniqueIndices();
        }
    }

    //--------------------------------------------------------------
    // Deposit Management Tests
    //--------------------------------------------------------------

    /// @notice Test deposits across all actors.
    function invariant_Deposits() public {
        uint256 depositAmount = 1 ether;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].depositHandler.invariant_handleDeposit(depositAmount);
        }
    }

    /// @notice Test withdrawals across all actors.
    function invariant_Withdrawals() public {
        uint256 withdrawalAmount = 0.5 ether;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].depositHandler.invariant_handleWithdrawal(withdrawalAmount);
        }
    }

    //--------------------------------------------------------------
    // Module Management Tests
    //--------------------------------------------------------------

    /// @notice Ensure each actor can handle module installation correctly.
    function invariant_testAllModuleInstallations() public {
        uint256 moduleType = MODULE_TYPE_VALIDATOR;
        address moduleAddress = validationModule;

        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].moduleHandler.invariant_installModule(moduleType, moduleAddress);
        }
    }

    /// @notice Ensure each actor can handle invalid module installation.
    function invariant_testAllModuleInstallationsInvalidModule() public {
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].moduleHandler.invariant_installInvalidModule();
        }
    }

    /// @notice Ensure each actor can handle module uninstallation correctly.
    function invariant_testAllModuleUninstallations() public {
        uint256 moduleType = MODULE_TYPE_VALIDATOR;
        address moduleAddress = validationModule;

        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].moduleHandler.invariant_uninstallModule(moduleType, moduleAddress);
        }
    }

    /// @notice Ensure each actor can handle uninstallation of a non-existent module.
    function invariant_testAllModuleUninstallationsNonExistentModule() public {
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].moduleHandler.invariant_uninstallNonExistentModule();
        }
    }

    //--------------------------------------------------------------
    // Execution Tests
    //--------------------------------------------------------------

    /// @notice Adds testing methods for increment operations across all actors.
    function invariant_testAllIncrementOperations() public {
        uint256 amount = 1 ether;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].executionHandler.invariant_handleIncrement(amount);
        }
    }

    /// @notice Tests failure handling for decrement operations across all actors.
    function invariant_testAllDecrementFailures() public {
        uint256 amount = 1 ether;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].executionHandler.invariant_handleShouldFail(amount);
        }
    }

    /// @notice Tests bounded deposit operations across all actors.
    function invariant_testAllBoundedDeposits() public {
        uint256 amount = 500 ether;
        for (uint i = 0; i < actorHandlers.length; i++) {
            actorHandlers[i].executionHandler.invariant_handleBoundedDeposit(amount);
        }
    }
}
