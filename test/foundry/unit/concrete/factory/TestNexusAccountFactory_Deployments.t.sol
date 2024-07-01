// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../../utils/NexusTest_Base.t.sol";

/// @title TestNexusAccountFactory_Deployments
/// @notice Tests for deploying accounts using the NexusAccountFactory.
contract TestNexusAccountFactory_Deployments is NexusTest_Base {
    Vm.Wallet public user;
    bytes initData;

    /// @notice Sets up the testing environment.
    function setUp() public {
        super.setupTestEnvironment();
        user = newWallet("user");
        vm.deal(user.addr, 1 ether);
        initData = abi.encodePacked(user.addr);
    }

    /// @notice Tests deploying an account using the factory directly.
    function test_DeployAccount_CreateAccount() public {
        // Prepare bootstrap configuration for validators
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        vm.expectEmit(true, true, true, true);
        emit AccountCreated(expectedAddress, _initData, salt);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        address payable deployedAccountAddress = META_FACTORY.deployWithFactory(address(FACTORY), factoryData);

        // Validate that the account was deployed correctly
        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address mismatch");
    }

    /// @notice Tests that the constructor reverts if the implementation address is zero.
    function test_Constructor_RevertIf_ImplementationIsZero() public {
        address zeroAddress = address(0);

        // Expect the contract deployment to revert with the correct error message
        vm.expectRevert(ImplementationAddressCanNotBeZero.selector);

        // Try deploying the NexusAccountFactory with an implementation address of zero
        new NexusAccountFactory(zeroAddress, address(this));
    }

    /// @notice Tests that deploying an account returns the same address with the same arguments.
    function test_DeployAccount_CreateAccount_SameAddress() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        vm.expectEmit(true, true, true, true);
        emit AccountCreated(expectedAddress, _initData, salt);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        address payable deployedAccountAddress = META_FACTORY.deployWithFactory(address(FACTORY), factoryData);

        address payable deployedAccountAddress2 = META_FACTORY.deployWithFactory(address(FACTORY), factoryData);
        assertEq(deployedAccountAddress, deployedAccountAddress2, "Deployed account address mismatch");
    }

    /// @notice Tests deploying an account using handleOps method.
    function test_DeployAccount_HandleOps_Success() public {
        address payable accountAddress = calculateAccountAddress(user.addr, address(VALIDATOR_MODULE));
        bytes memory initCode = buildInitCode(user.addr, address(VALIDATOR_MODULE));
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildUserOpWithInitAndCalldata(user, initCode, "", address(VALIDATOR_MODULE));
        ENTRYPOINT.depositTo{ value: 1 ether }(address(accountAddress));
        ENTRYPOINT.handleOps(userOps, payable(user.addr));
        assertEq(IAccountConfig(accountAddress).accountId(), "biconomy.nexus.1.0.0-beta", "Not deployed properly");
    }

    /// @notice Tests that deploying an account fails if it already exists.
    function test_RevertIf_HandleOps_AccountExists() public {
        address payable accountAddress = calculateAccountAddress(user.addr, address(VALIDATOR_MODULE));
        bytes memory initCode = buildInitCode(user.addr, address(VALIDATOR_MODULE));
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildUserOpWithInitAndCalldata(user, initCode, "", address(VALIDATOR_MODULE));
        ENTRYPOINT.depositTo{ value: 1 ether }(address(accountAddress));
        ENTRYPOINT.handleOps(userOps, payable(user.addr));
        vm.expectRevert(abi.encodeWithSelector(FailedOp.selector, 0, "AA10 sender already constructed"));
        ENTRYPOINT.handleOps(userOps, payable(user.addr));
    }

    /// @notice Tests that a deployed account is initialized and cannot be reinitialized.
    function test_DeployAccount_CannotReinitialize() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        address payable firstAccountAddress = FACTORY.createAccount(_initData, salt);

        vm.prank(user.addr); // Even owner cannot reinitialize the account
        vm.expectRevert(LinkedList_AlreadyInitialized.selector);
        INexus(firstAccountAddress).initializeAccount(factoryData);
    }

    /// @notice Tests creating accounts with different indexes.
    function test_DeployAccount_DifferentIndexes() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes memory factoryData1 = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);
        bytes memory factoryData2 = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, keccak256("1"));

        address payable accountAddress1 = META_FACTORY.deployWithFactory(address(FACTORY), factoryData1);
        address payable accountAddress2 = META_FACTORY.deployWithFactory(address(FACTORY), factoryData2);

        // Validate that the deployed addresses are different
        assertTrue(accountAddress1 != accountAddress2, "Accounts with different indexes should have different addresses");
    }

    /// @notice Tests creating accounts with an invalid validator module.
    function test_DeployAccount_InvalidValidatorModule() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        // Should revert if the validator module is invalid
        BootstrapConfig[] memory validatorsInvalid = BootstrapLib.createArrayConfig(address(0), initData);
        bytes memory _initDataInvalidModule = BOOTSTRAPPER.getInitNexusScopedCalldata(validatorsInvalid, hook, REGISTRY, ATTESTERS, THRESHOLD);

        vm.expectRevert();
        address payable accountAddress = FACTORY.createAccount(_initDataInvalidModule, salt);
        assertTrue(expectedAddress != accountAddress, "Account address should be different for invalid module");
    }

    /// @notice Tests creating accounts without enough gas.
    function test_RevertIf_DeployAccount_InsufficientGas() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        vm.expectRevert();
        // Should revert if there is not enough gas
        FACTORY.createAccount{ gas: 1000 }(_initData, salt);
    }

    /// @notice Tests that the Nexus contract constructor reverts if the entry point address is zero.
    function test_Constructor_RevertIf_EntryPointIsZero() public {
        address zeroAddress = address(0);

        // Expect the contract deployment to revert with the correct error message
        vm.expectRevert(EntryPointCanNotBeZero.selector);

        // Try deploying the Nexus contract with an entry point address of zero
        new Nexus(zeroAddress);
    }

    /// @notice Tests BootstrapLib.createArrayConfig function for multiple modules and data in BootstrapLib and uses it to deploy an account.
    function test_createArrayConfig_MultipleModules_DeployAccount() public {
        address[] memory modules = new address[](2);
        bytes[] memory datas = new bytes[](2);

        modules[0] = address(VALIDATOR_MODULE);
        modules[1] = address(EXECUTOR_MODULE);
        datas[0] = abi.encodePacked(user.addr);
        datas[1] = abi.encodePacked(user.addr, "executor");

        BootstrapConfig[] memory configArray = BootstrapLib.createMultipleConfigs(modules, datas);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(configArray, hook, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        address payable deployedAccountAddress = META_FACTORY.deployWithFactory(address(FACTORY), factoryData);
        // Validate that the account was deployed correctly
        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address mismatch");
    }

    /// @notice Tests initNexusScoped function in Bootstrap and uses it to deploy an account with a hook module.
    function test_initNexusScoped_WithHook_DeployAccount() public {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(HOOK_MODULE), abi.encodePacked(user.addr));

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        address payable deployedAccountAddress = META_FACTORY.deployWithFactory(address(FACTORY), factoryData);

        // Validate that the account was deployed correctly
        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address mismatch");

        // Verify that the validators and hook were installed
        assertTrue(
            INexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""), "Validator should be installed"
        );
        assertTrue(
            INexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), abi.encodePacked(user.addr)),
            "Hook should be installed"
        );
    }
}
