// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../utils/NexusTest_Base.t.sol";

/// @title TestFuzz_AccountFactory_Deployment
/// @notice Fuzz tests for deploying accounts using the NexusAccountFactory.
contract TestFuzz_AccountFactory_Deployment is NexusTest_Base {
    function setUp() public {
        init();
    }

    /// @notice Tests account creation with random initialization data.
    /// @param randomSeed The random seed to generate initialization data.
    function testFuzz_CreateAccountWithRandomData(uint256 randomSeed) public {
        Vm.Wallet memory randomUser = createAndFundWallet("RandomUser", 1 ether);
        bytes memory initData = abi.encodePacked(randomUser.addr, randomSeed);

        // Use the BootstrapLib to create the configuration
        address[] memory modules = new address[](1);
        modules[0] = address(VALIDATOR_MODULE);

        bytes[] memory datas = new bytes[](1);
        datas[0] = initData;

        BootstrapConfig[] memory validators = BootstrapLib.createMultipleConfigs(modules, datas);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes32 salt = keccak256(abi.encodePacked(randomSeed));
        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);
        address payable deployedAccountAddress = FACTORY.createAccount(_initData, salt);

        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address should match expected address");
    }

    /// @notice Tests account creation with a large index.
    /// @param largeIndex The large index to be used in initialization data.
    function testFuzz_CreateAccountWithLargeIndex(uint256 largeIndex) public {
        Vm.Wallet memory randomUser = createAndFundWallet("RandomUser", 1 ether);
        bytes memory initData = abi.encodePacked(randomUser.addr, largeIndex);

        // Use the BootstrapLib to create the configuration
        address[] memory modules = new address[](1);
        modules[0] = address(VALIDATOR_MODULE);

        bytes[] memory datas = new bytes[](1);
        datas[0] = initData;

        BootstrapConfig[] memory validators = BootstrapLib.createMultipleConfigs(modules, datas);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes32 salt = keccak256(abi.encodePacked(largeIndex));
        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);
        address payable deployedAccountAddress = FACTORY.createAccount(_initData, salt);

        assertEq(deployedAccountAddress, expectedAddress, "Deployed account address should match expected address for large index");
    }

    /// @notice Tests repeated account creation with the same initialization data.
    /// @param randomSeed The random seed to generate initialization data.
    function testFuzz_RepeatedAccountCreation(uint256 randomSeed) public {
        Vm.Wallet memory randomUser = createAndFundWallet("RandomUser", 1 ether);
        bytes memory initData = abi.encodePacked(randomUser.addr, randomSeed);

        // Use the BootstrapLib to create the configuration
        address[] memory modules = new address[](1);
        modules[0] = address(VALIDATOR_MODULE);

        bytes[] memory datas = new bytes[](1);
        datas[0] = initData;

        BootstrapConfig[] memory validators = BootstrapLib.createMultipleConfigs(modules, datas);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes32 salt = keccak256(abi.encodePacked(randomSeed));
        address payable expectedAddress = FACTORY.computeAccountAddress(_initData, salt);

        // First deployment
        address payable deployedAccountAddress1 = FACTORY.createAccount(_initData, salt);
        assertEq(deployedAccountAddress1, expectedAddress, "First deployment address should match expected address");

        // Attempt to deploy the same account again
        address payable deployedAccountAddress2 = FACTORY.createAccount(_initData, salt);
        assertEq(deployedAccountAddress2, expectedAddress, "Repeated deployment address should match expected address");
    }
}
