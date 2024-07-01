// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../../shared/TestModuleManagement_Base.t.sol";

/// @title Gas benchmark tests for NexusAccountFactory
contract TestGas_NexusAccountFactory is TestModuleManagement_Base {
    function setUp() public {
        init();
    }

    /// @notice Tests gas usage for deploying a new account
    function test_Gas_DeployAccount() public {
        uint256 initialGas = gasleft();
        address payable newAccount = FACTORY.createAccount(getInitData(address(VALIDATOR_MODULE), address(this)), keccak256("deploy_account_test"));
        uint256 gasUsed = initialGas - gasleft();
        console.log("Gas used for deploying a new account: ", gasUsed);

        // Verifying the account was deployed correctly
        assertTrue(isContract(newAccount), "New account should be a contract");
        assertValidCreation(Nexus(newAccount));
    }

    /// @notice Tests gas usage for deploying a new account with different parameters
    function test_Gas_DeployAccountWithDifferentParams() public {
        uint256 initialGas = gasleft();
        address payable newAccount =
            FACTORY.createAccount(getInitData(address(VALIDATOR_MODULE), address(mockExecutor)), keccak256("deploy_account_with_diff_params_test"));
        uint256 gasUsed = initialGas - gasleft();
        console.log("Gas used for deploying a new account with different parameters: ", gasUsed);

        // Verifying the account was deployed correctly
        assertTrue(isContract(newAccount), "New account should be a contract");
        assertValidCreation(Nexus(newAccount));
    }

    /// @notice Tests gas usage for deploying multiple accounts
    function test_Gas_DeployMultipleAccounts() public {
        for (uint256 i = 0; i < 5; i++) {
            uint256 initialGas = gasleft();
            address payable newAccount = FACTORY.createAccount(
                getInitData(address(VALIDATOR_MODULE), address(this)), keccak256(abi.encodePacked("deploy_multiple_accounts", i))
            );
            uint256 gasUsed = initialGas - gasleft();
            console.log("Gas used per deployment while deploying multiple accounts: ", gasUsed);
            assertTrue(isContract(newAccount), "New account should be a contract");
            assertValidCreation(Nexus(newAccount));
        }
    }

    /// @notice Tests gas usage for deploying an account and verifying module installation
    function test_Gas_DeployAccountAndVerifyModuleInstallation() public {
        uint256 initialGas = gasleft();
        address payable newAccount =
            FACTORY.createAccount(getInitData(address(VALIDATOR_MODULE), address(this)), keccak256("deploy_account_verify_module"));
        uint256 gasUsed = initialGas - gasleft();
        console.log("Gas used for deploying a new account and verifying module installation: ", gasUsed);

        // Verifying the account was deployed correctly
        assertTrue(isContract(newAccount), "New account should be a contract");
        assertValidCreation(Nexus(newAccount));
    }

    /// @notice Helper function to get the initialization data for account creation
    function getInitData(address validator, address owner) internal view returns (bytes memory) {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(validator, abi.encodePacked(owner));
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        return BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);
    }

    /// @notice Validates the creation of a new account.
    /// @param _account The new account address.
    function assertValidCreation(Nexus _account) internal {
        string memory expected = "biconomy.nexus.1.0.0-beta";
        assertEq(_account.accountId(), expected, "AccountConfig should return the expected account ID.");
        assertTrue(
            _account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""), "Account should have the validation module installed"
        );
    }
}
