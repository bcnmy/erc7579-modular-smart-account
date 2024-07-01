// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../../utils/NexusTest_Base.t.sol";
import "../../../../../contracts/factory/K1ValidatorFactory.sol";
import "../../../../../contracts/utils/RegistryBootstrap.sol";
import "../../../../../contracts/interfaces/INexus.sol";

/// @title TestK1ValidatorFactory_Deployments
/// @notice Tests for deploying accounts using the K1ValidatorFactory and various methods.
contract TestK1ValidatorFactory_Deployments is NexusTest_Base {
    Vm.Wallet public user;
    bytes initData;
    K1ValidatorFactory public validatorFactory;
    Bootstrap public bootstrapper;

    /// @notice Sets up the testing environment.
    function setUp() public {
        init();
        user = newWallet("user");
        vm.deal(user.addr, 1 ether);
        initData = abi.encodePacked(user.addr);
        bootstrapper = new Bootstrap();
        validatorFactory =
            new K1ValidatorFactory(address(ACCOUNT_IMPLEMENTATION), address(FACTORY_OWNER.addr), address(VALIDATOR_MODULE), bootstrapper, REGISTRY);
    }

    /// @notice Tests if the constructor correctly initializes the factory with the given implementation, K1 Validator, and Bootstrapper addresses.
    function test_ConstructorInitializesFactory() public {
        address implementation = address(0x123);
        address k1Validator = address(0x456);
        Bootstrap bootstrapperInstance = new Bootstrap();
        K1ValidatorFactory factory = new K1ValidatorFactory(implementation, FACTORY_OWNER.addr, k1Validator, bootstrapperInstance, REGISTRY);

        // Verify the implementation address is set correctly
        assertEq(factory.ACCOUNT_IMPLEMENTATION(), implementation, "Implementation address mismatch");

        // Verify the K1 Validator address is set correctly
        assertEq(factory.K1_VALIDATOR(), k1Validator, "K1 Validator address mismatch");

        // Verify the bootstrapper address is set correctly
        assertEq(address(factory.BOOTSTRAPPER()), address(bootstrapperInstance), "Bootstrapper address mismatch");

        // Ensure the factory contract is deployed and is a valid contract
        assertTrue(isContract(address(factory)), "Factory should be a contract");
    }

    /// @notice Tests that the constructor reverts if the implementation address is zero.
    function test_Constructor_RevertIf_ImplementationIsZero() public {
        address zeroAddress = address(0);

        // Expect the contract deployment to revert with the correct error message
        vm.expectRevert(ZeroAddressNotAllowed.selector);

        // Try deploying the K1ValidatorFactory with an implementation address of zero
        new K1ValidatorFactory(zeroAddress, address(this), address(VALIDATOR_MODULE), bootstrapper, REGISTRY);
    }

    /// @notice Tests that the constructor reverts if the K1 Validator address is zero.
    function test_Constructor_RevertIf_K1ValidatorIsZero() public {
        address zeroAddress = address(0);

        // Expect the contract deployment to revert with the correct error message
        vm.expectRevert(ZeroAddressNotAllowed.selector);

        // Try deploying the K1ValidatorFactory with a K1 Validator address of zero
        new K1ValidatorFactory(address(this), address(ACCOUNT_IMPLEMENTATION), zeroAddress, bootstrapper, REGISTRY);
    }

    /// @notice Tests that the constructor reverts if the Bootstrapper address is zero.
    function test_Constructor_RevertIf_BootstrapperIsZero() public {
        Bootstrap zeroBootstrapper = Bootstrap(payable(0));

        // Expect the contract deployment to revert with the correct error message
        vm.expectRevert(ZeroAddressNotAllowed.selector);

        // Try deploying the K1ValidatorFactory with a Bootstrapper address of zero
        new K1ValidatorFactory(address(this), address(ACCOUNT_IMPLEMENTATION), address(VALIDATOR_MODULE), zeroBootstrapper, REGISTRY);
    }

    /// @notice Tests deploying an account using the factory directly.
    function test_DeployAccount_K1ValidatorFactory_CreateAccount() public payable {
        uint256 index = 0;
        address expectedOwner = user.addr;

        address payable expectedAddress = validatorFactory.computeAccountAddress(expectedOwner, index, ATTESTERS, THRESHOLD);

        address payable deployedAccountAddress = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index, ATTESTERS, THRESHOLD);

        // Validate that the account was deployed correctly
        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address mismatch");

        assertEq(
            INexus(deployedAccountAddress).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""),
            true,
            "Validator should be installed"
        );
    }

    /// @notice Tests that computing the account address returns the expected address.
    function test_ComputeAccountAddress() public {
        uint256 index = 0;
        address expectedOwner = user.addr;

        address payable expectedAddress = validatorFactory.computeAccountAddress(expectedOwner, index, ATTESTERS, THRESHOLD);

        // Deploy the account to compare the address
        address payable deployedAccountAddress = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index, ATTESTERS, THRESHOLD);

        assertEq(deployedAccountAddress, expectedAddress, "Computed address mismatch");
    }

    /// @notice Tests that creating an account with the same owner and index results in the same address.
    function test_CreateAccount_SameOwnerAndIndex() public payable {
        uint256 index = 0;
        address expectedOwner = user.addr;

        address payable firstAccountAddress = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index, ATTESTERS, THRESHOLD);
        address payable secondAccountAddress = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index, ATTESTERS, THRESHOLD);

        assertEq(firstAccountAddress, secondAccountAddress, "Addresses should match for the same owner and index");
    }

    /// @notice Tests that creating accounts with different indexes results in different addresses.
    function test_CreateAccount_DifferentIndexes() public payable {
        uint256 index0 = 0;
        uint256 index1 = 1;
        address expectedOwner = user.addr;

        address payable accountAddress0 = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index0, ATTESTERS, THRESHOLD);
        address payable accountAddress1 = validatorFactory.createAccount{ value: 1 ether }(expectedOwner, index1, ATTESTERS, THRESHOLD);

        assertTrue(accountAddress0 != accountAddress1, "Accounts with different indexes should have different addresses");
    }
}
