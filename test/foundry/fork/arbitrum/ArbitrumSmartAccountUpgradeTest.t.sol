// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../utils/Imports.sol";
import { ArbitrumSettings } from "./ArbitrumSettings.t.sol";
import { NexusTest_Base } from "../../utils/NexusTest_Base.t.sol";
import { UserOperation } from "../../shared/interfaces/UserOperation.t.sol";
import { IEntryPointV_0_6 } from "../../shared/interfaces/IEntryPointV_0_6.t.sol";
import { IBiconomySmartAccountV2 } from "../../shared/interfaces/IBiconomySmartAccountV2.t.sol";

/// @title ArbitrumSmartAccountUpgradeTest
/// @notice Tests the upgrade process from Biconomy Smart Account V2 to Nexus and validates the upgrade process.
contract ArbitrumSmartAccountUpgradeTest is NexusTest_Base, ArbitrumSettings {
    Vm.Wallet internal signer;
    Nexus public newImplementation;
    uint256 internal signerPrivateKey;
    IEntryPoint public ENTRYPOINT_V_0_7;
    IEntryPointV_0_6 public ENTRYPOINT_V_0_6;
    IBiconomySmartAccountV2 public smartAccountV2;

    /// @notice Sets up the initial test environment and forks the Arbitrum mainnet.
    function setUp() public {
        address _ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
        uint256 mainnetFork = vm.createFork(getArbitrumRpcUrl());
        vm.selectFork(mainnetFork);
        vm.rollFork(209_480_000);
        init();
        smartAccountV2 = IBiconomySmartAccountV2(SMART_ACCOUNT_V2_ADDRESS);
        ENTRYPOINT_V_0_6 = IEntryPointV_0_6(ENTRYPOINT_ADDRESS);
        ENTRYPOINT_V_0_7 = ENTRYPOINT;
        newImplementation = new Nexus(_ENTRYPOINT);
        // /!\ The private key is for testing purposes only and should not be used in production.
        signerPrivateKey = 0x2924d554c046e633f658427df4d0e7726487b1322bd16caaf24a53099f1cda85;
        signer = vm.createWallet(signerPrivateKey);
    }

    /// @notice Tests the upgrade from Smart Account V2 to Nexus and ensures initialization.
    function test_UpgradeV2ToV3AndInitialize() public {
        checkInitialState();
        _fundAccounts();
        upgradeAndInitialize();
        verifyUpgradeAndInitialization();
    }

    /// @notice Validates the account ID after the upgrade process.
    function test_AccountIdValidationAfterUpgrade() public {
        test_UpgradeV2ToV3AndInitialize();
        string memory expectedAccountId = "biconomy.nexus.1.0.0-beta";
        string memory actualAccountId = IAccountConfig(payable(address(smartAccountV2))).accountId();
        assertEq(actualAccountId, expectedAccountId, "Account ID does not match after upgrade.");
    }

    /// @notice Validates the Account implementation address after the upgrade process.
    function test_AccountImplementationAddress() public {
        address beforeUpgradeImplementation = IBiconomySmartAccountV2(SMART_ACCOUNT_V2_ADDRESS).getImplementation();
        assertNotEq(beforeUpgradeImplementation, address(newImplementation), "Implementation address does not match before upgrade.");
        test_UpgradeV2ToV3AndInitialize();
        address afterUpgradeImplementation = Nexus(payable(SMART_ACCOUNT_V2_ADDRESS)).getImplementation();
        address expectedImplementation = address(newImplementation);
        assertEq(afterUpgradeImplementation, expectedImplementation, "Implementation address does not match after upgrade.");
    }

    /// @notice Tests USDC transfer functionality after the upgrade.
    function test_USDCTransferPostUpgrade() public {
        test_UpgradeV2ToV3AndInitialize();
        MockToken usdc = MockToken(USDC_ADDRESS);
        address recipient = address(0x123);
        uint256 amount = usdc.balanceOf(address(smartAccountV2));
        bytes memory callData = abi.encodeWithSelector(usdc.transfer.selector, recipient, amount);
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(address(usdc), 0, callData);
        PackedUserOperation[] memory userOps =
            buildPackedUserOperation(BOB, Nexus(payable(address(SMART_ACCOUNT_V2_ADDRESS))), EXECTYPE_DEFAULT, execution, address(VALIDATOR_MODULE));
        ENTRYPOINT_V_0_7.handleOps(userOps, payable(OWNER_ADDRESS));
        assertEq(usdc.balanceOf(recipient), amount, "USDC transfer failed");
    }

    /// @notice Tests native ETH transfer functionality after the upgrade.
    function test_NativeEthTransferPostUpgrade() public {
        test_UpgradeV2ToV3AndInitialize();
        address recipient = address(0x123);
        uint256 amount = 1 ether;
        vm.deal(address(smartAccountV2), amount + 1 ether);
        Execution[] memory execution = new Execution[](1);
        execution[0] = Execution(recipient, amount, "");
        PackedUserOperation[] memory userOps =
            buildPackedUserOperation(BOB, Nexus(payable(address(smartAccountV2))), EXECTYPE_DEFAULT, execution, address(VALIDATOR_MODULE));
        ENTRYPOINT_V_0_7.handleOps(userOps, payable(OWNER_ADDRESS));
        assertEq(address(recipient).balance, amount, "ETH transfer failed");
    }

    /// @notice Prepares the initial state check before upgrade.
    function checkInitialState() internal {
        address initialEntryPoint = Nexus(payable(address(smartAccountV2))).entryPoint();
        assertEq(address(initialEntryPoint), ENTRYPOINT_ADDRESS, "Initial entry point mismatch.");
    }

    /// @notice Funds the required accounts for the upgrade process.
    function _fundAccounts() internal {
        vm.deal(SMART_ACCOUNT_V2_ADDRESS, 1 ether);
        vm.deal(OWNER_ADDRESS, 1 ether);
        ENTRYPOINT_V_0_6.depositTo{ value: 1 ether }(SMART_ACCOUNT_V2_ADDRESS);
    }

    /// @notice Performs the upgrade and initialization steps.
    function upgradeAndInitialize() internal {
        address[] memory dest = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);

        dest[0] = address(smartAccountV2);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(IBiconomySmartAccountV2.updateImplementation.selector, newImplementation);

        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), abi.encodePacked(BOB.addr));
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        dest[1] = address(smartAccountV2);
        values[1] = 0;
        calldatas[1] = abi.encodeWithSelector(Nexus.initializeAccount.selector, _initData);

        bytes memory batchCallData = abi.encodeWithSelector(IBiconomySmartAccountV2.executeBatch.selector, dest, values, calldatas);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = buildUserOperation(address(smartAccountV2), batchCallData);

        bytes32 userOpHash = ENTRYPOINT_V_0_6.getUserOpHash(userOps[0]);
        userOps[0].signature = abi.encode(signMessage(signer, userOpHash), MODULE_ADDRESS);

        ENTRYPOINT_V_0_6.handleOps(userOps, address(this));
    }

    /// @notice Verifies the state after upgrade and initialization.
    function verifyUpgradeAndInitialization() internal {
        address newEntryPoint = Nexus(payable(address(smartAccountV2))).entryPoint();
        assertEq(newEntryPoint, address(ENTRYPOINT_V_0_7), "Entry point should change after upgrade.");
        assertTrue(
            Nexus(payable(address(smartAccountV2))).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""),
            "Validator module should be installed after upgrade."
        );
    }

    /// @notice Builds a user operation for testing.
    /// @param from The sender address.
    /// @param callData The call data for the operation.
    /// @return op The constructed UserOperation.
    function buildUserOperation(address from, bytes memory callData) internal view returns (UserOperation memory op) {
        op.sender = from;
        op.nonce = ENTRYPOINT_V_0_6.getNonce(op.sender, 0);
        op.callData = callData;
        op.callGasLimit = 3e6;
        op.verificationGasLimit = 3e6;
        op.preVerificationGas = 3e6;
        op.maxFeePerGas = 3e6;
        op.maxPriorityFeePerGas = 3e6;
        op.paymasterAndData = "";
    }
}
