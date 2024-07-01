// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../../utils/NexusTest_Base.t.sol";
import "../../../../../contracts/factory/ModuleWhitelistFactory.sol";

/// @title TestModuleWhitelistFactory_Deployments
/// @notice Tests for deploying accounts using the ModuleWhitelistFactory and various methods.
contract TestModuleWhitelistFactory_Deployments is NexusTest_Base {
    Vm.Wallet public user;
    bytes initData;
    ModuleWhitelistFactory public whitelistFactory;
    bytes4 public constant GENERIC_FALLBACK_SELECTOR = 0xcb5baf0f;

    /// @notice Sets up the testing environment.
    function setUp() public {
        init();
        user = newWallet("user");
        vm.deal(user.addr, 1 ether);
        initData = abi.encodePacked(user.addr);
        whitelistFactory = new ModuleWhitelistFactory(address(ACCOUNT_IMPLEMENTATION), address(FACTORY_OWNER.addr));
        vm.startPrank(FACTORY_OWNER.addr);
        whitelistFactory.addModuleToWhitelist(address(VALIDATOR_MODULE));
        whitelistFactory.addModuleToWhitelist(address(EXECUTOR_MODULE));
        whitelistFactory.addModuleToWhitelist(address(HANDLER_MODULE));
        whitelistFactory.addModuleToWhitelist(address(HOOK_MODULE));
        vm.stopPrank();
    }

    /// @notice Tests the constructor sets the implementation address correctly.
    function test_Constructor_SetsImplementation() public {
        address implementation = address(0x123);
        ModuleWhitelistFactory factory = new ModuleWhitelistFactory(implementation, address(this));
        assertEq(factory.ACCOUNT_IMPLEMENTATION(), implementation, "Implementation address mismatch");
    }

    /// @notice Tests that the constructor reverts if the owner address is zero.
    function test_Constructor_RevertIf_OwnerIsZero() public {
        address implementation = address(0x123);
        vm.expectRevert(ZeroAddressNotAllowed.selector);
        new ModuleWhitelistFactory(implementation, address(0));
    }

    /// @notice Tests that the constructor reverts if the implementation address is zero.
    function test_Constructor_RevertIf_ImplementationIsZero() public {
        vm.expectRevert(ImplementationAddressCanNotBeZero.selector);
        new ModuleWhitelistFactory(address(0), address(this));
    }

    /// @notice Tests adding and removing modules from the whitelist.
    function test_ModuleWhitelist_AddRemoveModule() public {
        address module = address(0x456);
        vm.startPrank(FACTORY_OWNER.addr);
        whitelistFactory.addModuleToWhitelist(module);
        assertTrue(whitelistFactory.moduleWhitelist(module), "Module should be whitelisted");

        whitelistFactory.removeModuleFromWhitelist(module);
        assertFalse(whitelistFactory.moduleWhitelist(module), "Module should be removed from whitelist");
        vm.stopPrank();
    }

    /// @notice Tests adding a module to the whitelist with a zero address.
    function test_ModuleWhitelist_RevertIf_ModuleIsZero() public {
        vm.startPrank(FACTORY_OWNER.addr);
        vm.expectRevert(ZeroAddressNotAllowed.selector);
        whitelistFactory.addModuleToWhitelist(address(0));
        vm.stopPrank();
    }

    /// @notice Tests deploying an account using the whitelist factory directly.
    function test_DeployAccount_WhitelistFactory_CreateAccount() public payable {
        // Prepare bootstrap configuration for validators
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig[] memory executors = BootstrapLib.createArrayConfig(address(EXECUTOR_MODULE), "");
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(HOOK_MODULE), "");
        BootstrapConfig[] memory fallbacks = BootstrapLib.createArrayConfig(address(HANDLER_MODULE), abi.encode(bytes4(GENERIC_FALLBACK_SELECTOR)));
        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        address payable expectedAddress = whitelistFactory.computeAccountAddress(_initData, salt);

        address payable deployedAccountAddress = whitelistFactory.createAccount{ value: 1 ether }(_initData, salt);

        // Validate that the account was deployed correctly
        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address mismatch");

        assertEq(
            Nexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""),
            true,
            "Validator should be installed"
        );
        assertEq(
            Nexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(EXECUTOR_MODULE), ""), true, "Executor should be installed"
        );
        assertEq(Nexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""), true, "Hook should be installed");
        assertEq(
            Nexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_FALLBACK, address(HANDLER_MODULE), abi.encode(GENERIC_FALLBACK_SELECTOR)),
            true,
            "Fallback should be installed for selector"
        );
    }

    /// @notice Tests that creating an account fails if a module is not whitelisted.
    function test_DeployAccount_FailsIfModuleNotWhitelisted() public payable {
        // Prepare bootstrap configuration with a non-whitelisted module
        address nonWhitelistedModule = address(0x789);
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(nonWhitelistedModule, initData);
        BootstrapConfig[] memory executors;
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        BootstrapConfig[] memory fallbacks;

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        // Expect the account creation to revert
        vm.expectRevert(abi.encodeWithSelector(ModuleNotWhitelisted.selector, nonWhitelistedModule));
        whitelistFactory.createAccount{ value: 1 ether }(_initData, salt);
    }

    /// @notice Tests creating accounts with different indexes.
    function test_DeployAccount_DifferentIndexes() public payable {
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig[] memory executors = BootstrapLib.createArrayConfig(address(EXECUTOR_MODULE), "");
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(HOOK_MODULE), "");
        BootstrapConfig[] memory fallbacks = BootstrapLib.createArrayConfig(address(HANDLER_MODULE), abi.encode(bytes4(GENERIC_FALLBACK_SELECTOR)));
        bytes memory saDeploymentIndex0 = "0";
        bytes memory saDeploymentIndex1 = "1";
        bytes32 salt0 = keccak256(saDeploymentIndex0);
        bytes32 salt1 = keccak256(saDeploymentIndex1);

        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        address payable accountAddress0 = whitelistFactory.createAccount{ value: 1 ether }(_initData, salt0);
        address payable accountAddress1 = whitelistFactory.createAccount{ value: 1 ether }(_initData, salt1);

        // Validate that the deployed addresses are different
        assertTrue(accountAddress0 != accountAddress1, "Accounts with different indexes should have different addresses");
    }

    /// @notice Tests that creating an account fails if an executor module is not whitelisted.
    function test_DeployAccount_FailsIfExecutorNotWhitelisted() public payable {
        // Prepare bootstrap configuration with a non-whitelisted executor module
        address nonWhitelistedExecutor = address(0x789);
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig[] memory executors = BootstrapLib.createArrayConfig(nonWhitelistedExecutor, "");
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        BootstrapConfig[] memory fallbacks;

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        // Expect the account creation to revert
        vm.expectRevert(abi.encodeWithSelector(ModuleNotWhitelisted.selector, nonWhitelistedExecutor));
        whitelistFactory.createAccount{ value: 1 ether }(_initData, salt);
    }

    /// @notice Tests that creating an account fails if a hook module is not whitelisted.
    function test_DeployAccount_FailsIfHookNotWhitelisted() public payable {
        // Prepare bootstrap configuration with a non-whitelisted hook module
        address nonWhitelistedHook = address(0x789);
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig[] memory executors;
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(nonWhitelistedHook, "");
        BootstrapConfig[] memory fallbacks;

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        // Expect the account creation to revert
        vm.expectRevert(abi.encodeWithSelector(ModuleNotWhitelisted.selector, nonWhitelistedHook));
        whitelistFactory.createAccount{ value: 1 ether }(_initData, salt);
    }

    /// @notice Tests that creating an account fails if a fallback module is not whitelisted.
    function test_DeployAccount_FailsIfFallbackNotWhitelisted() public payable {
        // Prepare bootstrap configuration with a non-whitelisted fallback module
        address nonWhitelistedFallback = address(0x789);
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), initData);
        BootstrapConfig[] memory executors;
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(HOOK_MODULE), "");
        BootstrapConfig[] memory fallbacks = BootstrapLib.createArrayConfig(nonWhitelistedFallback, abi.encode(bytes4(0x11223344)));

        bytes memory saDeploymentIndex = "0";
        bytes32 salt = keccak256(saDeploymentIndex);

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);

        // Expect the account creation to revert
        vm.expectRevert(abi.encodeWithSelector(ModuleNotWhitelisted.selector, nonWhitelistedFallback));
        whitelistFactory.createAccount{ value: 1 ether }(_initData, salt);
    }

    /// @notice Tests that the ACCOUNT_IMPLEMENTATION is correctly set and not zero.
    function test_AccountImplementation_IsNotZero() public {
        assertTrue(whitelistFactory.ACCOUNT_IMPLEMENTATION() != address(0), "ACCOUNT_IMPLEMENTATION should not be zero");
    }

    /// @notice Tests if a module is whitelisted.
    function test_IsModuleWhitelisted() public {
        assertTrue(whitelistFactory.isModuleWhitelisted(address(VALIDATOR_MODULE)), "Validator should be whitelisted");
        assertFalse(whitelistFactory.isModuleWhitelisted(address(0x123)), "Non-whitelisted module should not be whitelisted");
    }
}
