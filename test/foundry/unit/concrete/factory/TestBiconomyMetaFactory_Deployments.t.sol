// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../../utils/NexusTest_Base.t.sol";
import "../../../../../contracts/utils/RegistryBootstrap.sol";
import "../../../../../contracts/factory/BiconomyMetaFactory.sol";
import "../../../../../contracts/factory/K1ValidatorFactory.sol";

/// @title TestBiconomyMetaFactory_Deployments
/// @notice Tests for managing the factory whitelist and deploying accounts using the BiconomyMetaFactory.
contract TestBiconomyMetaFactory_Deployments is NexusTest_Base {
    Vm.Wallet public user;
    BiconomyMetaFactory public metaFactory;
    address public mockFactory;

    /// @notice Sets up the testing environment.
    function setUp() public {
        init();
        user = newWallet("user");
        vm.deal(user.addr, 1 ether);
        metaFactory = new BiconomyMetaFactory(address(FACTORY_OWNER.addr));
        mockFactory = address(
            new K1ValidatorFactory(address(FACTORY_OWNER.addr), address(ACCOUNT_IMPLEMENTATION), address(VALIDATOR_MODULE), new Bootstrap(), REGISTRY)
        );
    }

    /// @notice Tests the constructor sets the owner correctly.
    function test_Constructor_SetsOwner() public {
        assertEq(metaFactory.owner(), address(FACTORY_OWNER.addr), "Owner address mismatch");
    }

    /// @notice Tests the constructor reverts if zero address is provided.
    function test_Constructor_RevertIf_ZeroOwner() public {
        vm.expectRevert(ZeroAddressNotAllowed.selector);
        new BiconomyMetaFactory(address(0));
    }

    /// @notice Tests adding and removing factories from the whitelist.
    function test_FactoryWhitelist_AddRemoveFactory() public {
        vm.startPrank(FACTORY_OWNER.addr);
        metaFactory.addFactoryToWhitelist(mockFactory);
        assertTrue(metaFactory.isFactoryWhitelisted(mockFactory), "Factory should be whitelisted");

        metaFactory.removeFactoryFromWhitelist(mockFactory);
        assertFalse(metaFactory.isFactoryWhitelisted(mockFactory), "Factory should be removed from whitelist");
        vm.stopPrank();
    }

    /// @notice Tests that deploying an account fails if the factory is not whitelisted.
    function test_DeployAccount_FailsIfFactoryNotWhitelisted() public payable {
        bytes memory factoryData = abi.encodeWithSelector(K1ValidatorFactory.createAccount.selector, user.addr, 1, ATTESTERS, THRESHOLD);

        // Expect the deployment to revert
        vm.expectRevert(FactoryNotWhitelisted.selector);
        metaFactory.deployWithFactory{ value: 1 ether }(mockFactory, factoryData);
    }

    /// @notice Tests deploying an account using a whitelisted factory.
    function test_DeployAccount_WhitelistedFactory() public payable {
        vm.startPrank(FACTORY_OWNER.addr);
        metaFactory.addFactoryToWhitelist(mockFactory);
        vm.stopPrank();

        bytes memory factoryData = abi.encodeWithSelector(K1ValidatorFactory.createAccount.selector, user.addr, 1, ATTESTERS, THRESHOLD);

        address payable createdAccount = metaFactory.deployWithFactory{ value: 1 ether }(mockFactory, factoryData);

        // Validate that the account was deployed correctly
        assertTrue(createdAccount != address(0), "Created account address should not be zero");
    }

    /// @notice Tests that the factory address is correctly stored in the whitelist.
    function test_FactoryAddressStoredInWhitelist() public {
        vm.startPrank(FACTORY_OWNER.addr);
        metaFactory.addFactoryToWhitelist(mockFactory);
        vm.stopPrank();

        assertTrue(metaFactory.isFactoryWhitelisted(mockFactory), "Factory should be in the whitelist");
    }

    /// @notice Tests that the factory address is correctly removed from the whitelist.
    function test_FactoryAddressRemovedFromWhitelist() public {
        vm.startPrank(FACTORY_OWNER.addr);
        metaFactory.addFactoryToWhitelist(mockFactory);
        assertTrue(metaFactory.isFactoryWhitelisted(mockFactory), "Factory should be in the whitelist");

        metaFactory.removeFactoryFromWhitelist(mockFactory);
        assertFalse(metaFactory.isFactoryWhitelisted(mockFactory), "Factory should be removed from the whitelist");
        vm.stopPrank();
    }

    /// @notice Tests that the deployWithFactory method reverts if the factory call fails.
    function test_DeployAccount_RevertIfFactoryCallFails() public payable {
        vm.startPrank(FACTORY_OWNER.addr);
        metaFactory.addFactoryToWhitelist(mockFactory);
        vm.stopPrank();

        // Creating invalid factory data that will cause the call to fail
        bytes memory factoryData = abi.encodeWithSelector(bytes4(keccak256("nonExistentFunction()")));

        vm.expectRevert(CallToDeployWithFactoryFailed.selector);
        metaFactory.deployWithFactory{ value: 1 ether }(mockFactory, factoryData);
    }

    /// @notice Tests that adding a zero address to the factory whitelist reverts.
    function test_AddFactoryToWhitelist_RevertsIfAddressZero() public {
        vm.startPrank(FACTORY_OWNER.addr);
        vm.expectRevert(InvalidFactoryAddress.selector);
        metaFactory.addFactoryToWhitelist(address(0));
        vm.stopPrank();
    }
}
