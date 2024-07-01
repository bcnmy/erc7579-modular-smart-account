// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/src/utils/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { EntryPoint } from "account-abstraction/contracts/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

import "./CheatCodes.sol";
import "./EventsAndErrors.sol";
import "../../../contracts/lib/ModeLib.sol";
import "../../../contracts/lib/ExecLib.sol";
import { Nexus } from "../../../contracts/Nexus.sol";
import { MockHook } from "../../../contracts/mocks/MockHook.sol";
import { MockHandler } from "../../../contracts/mocks/MockHandler.sol";
import { MockExecutor } from "../../../contracts/mocks/MockExecutor.sol";
import { MockValidator } from "../../../contracts/mocks/MockValidator.sol";
import { MockPaymaster } from "./../../../contracts/mocks/MockPaymaster.sol";
import { Bootstrap, BootstrapConfig } from "../../../contracts/utils/RegistryBootstrap.sol";
import { BiconomyMetaFactory } from "../../../contracts/factory/BiconomyMetaFactory.sol";
import { NexusAccountFactory } from "../../../contracts/factory/NexusAccountFactory.sol";
import { BootstrapLib } from "../../../contracts/lib/BootstrapLib.sol";
import { MockRegistry } from "../../../contracts/mocks/MockRegistry.sol";

contract TestHelper is CheatCodes, EventsAndErrors {
    // -----------------------------------------
    // State Variables
    // -----------------------------------------

    Vm.Wallet internal DEPLOYER;
    Vm.Wallet internal BOB;
    Vm.Wallet internal ALICE;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal BUNDLER;
    Vm.Wallet internal FACTORY_OWNER;

    address internal BOB_ADDRESS;
    address internal ALICE_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address payable internal BUNDLER_ADDRESS;

    address[] internal ATTESTERS;
    uint8 internal THRESHOLD;

    Nexus internal BOB_ACCOUNT;
    Nexus internal ALICE_ACCOUNT;
    Nexus internal CHARLIE_ACCOUNT;

    IEntryPoint internal ENTRYPOINT;
    NexusAccountFactory internal FACTORY;
    BiconomyMetaFactory internal META_FACTORY;
    MockRegistry internal REGISTRY;
    MockHook internal HOOK_MODULE;
    MockHandler internal HANDLER_MODULE;
    MockExecutor internal EXECUTOR_MODULE;
    MockValidator internal VALIDATOR_MODULE;
    Nexus internal ACCOUNT_IMPLEMENTATION;

    Bootstrap internal BOOTSTRAPPER;

    // -----------------------------------------
    // Setup Functions
    // -----------------------------------------
    /// @notice Initializes the testing environment with wallets, contracts, and accounts
    function setupTestEnvironment() internal virtual {
        /// Initializes the testing environment
        setupPredefinedWallets();
        deployTestContracts();
        deployNexusForPredefinedWallets();
    }

    function createAndFundWallet(string memory name, uint256 amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = newWallet(name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }

    function setupPredefinedWallets() internal {
        DEPLOYER = createAndFundWallet("DEPLOYER", 1000 ether);

        BOB = createAndFundWallet("BOB", 1000 ether);
        BOB_ADDRESS = BOB.addr;

        ALICE = createAndFundWallet("ALICE", 1000 ether);
        CHARLIE = createAndFundWallet("CHARLIE", 1000 ether);

        ALICE_ADDRESS = ALICE.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;

        BUNDLER = createAndFundWallet("BUNDLER", 1000 ether);
        BUNDLER_ADDRESS = payable(BUNDLER.addr);

        FACTORY_OWNER = createAndFundWallet("FACTORY_OWNER", 1000 ether);

        ATTESTERS = new address[](1);
        ATTESTERS[0] = ALICE.addr;
        THRESHOLD = 1;
    }

    function deployTestContracts() internal {
        ENTRYPOINT = new EntryPoint();
        vm.etch(address(0x0000000071727De22E5E9d8BAf0edAc6f37da032), address(ENTRYPOINT).code);
        ENTRYPOINT = IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
        ACCOUNT_IMPLEMENTATION = new Nexus(address(ENTRYPOINT));
        FACTORY = new NexusAccountFactory(address(ACCOUNT_IMPLEMENTATION), address(FACTORY_OWNER.addr));
        META_FACTORY = new BiconomyMetaFactory(address(FACTORY_OWNER.addr));
        vm.prank(FACTORY_OWNER.addr);
        META_FACTORY.addFactoryToWhitelist(address(FACTORY));
        HOOK_MODULE = new MockHook();
        HANDLER_MODULE = new MockHandler();
        EXECUTOR_MODULE = new MockExecutor();
        VALIDATOR_MODULE = new MockValidator();
        BOOTSTRAPPER = new Bootstrap();
        REGISTRY = new MockRegistry();
    }

    // -----------------------------------------
    // Account Deployment Functions
    // -----------------------------------------
    /// @notice Deploys an account with a specified wallet, deposit amount, and optional custom validator
    /// @param wallet The wallet to deploy the account for
    /// @param deposit The deposit amount
    /// @param validator The custom validator address, if not provided uses default
    /// @return The deployed Nexus account
    function deployNexus(Vm.Wallet memory wallet, uint256 deposit, address validator) internal returns (Nexus) {
        address payable accountAddress = calculateAccountAddress(wallet.addr, validator);
        bytes memory initCode = buildInitCode(wallet.addr, validator);

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildUserOpWithInitAndCalldata(wallet, initCode, "", validator);

        ENTRYPOINT.depositTo{ value: deposit }(address(accountAddress));
        ENTRYPOINT.handleOps(userOps, payable(wallet.addr));
        assertTrue(MockValidator(validator).isOwner(accountAddress, wallet.addr));
        return Nexus(accountAddress);
    }

    /// @notice Deploys Nexus accounts for predefined wallets
    function deployNexusForPredefinedWallets() internal {
        BOB_ACCOUNT = deployNexus(BOB, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(BOB_ACCOUNT), "BOB_ACCOUNT");
        ALICE_ACCOUNT = deployNexus(ALICE, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(ALICE_ACCOUNT), "ALICE_ACCOUNT");
        CHARLIE_ACCOUNT = deployNexus(CHARLIE, 100 ether, address(VALIDATOR_MODULE));
        vm.label(address(CHARLIE_ACCOUNT), "CHARLIE_ACCOUNT");
    }
    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    /// @notice Calculates the address of a new account
    /// @param owner The address of the owner
    /// @param validator The address of the validator
    /// @return account The calculated account address
    function calculateAccountAddress(address owner, address validator) internal view returns (address payable account) {
        bytes memory moduleInstallData = abi.encodePacked(owner);

        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(validator, moduleInstallData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        bytes memory saDeploymentIndex = "0";

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);
        bytes32 salt = keccak256(saDeploymentIndex);

        account = FACTORY.computeAccountAddress(_initData, salt);
        return account;
    }

    /// @notice Prepares the init code for account creation with a validator
    /// @param ownerAddress The address of the owner
    /// @param validator The address of the validator
    /// @return initCode The prepared init code
    function buildInitCode(address ownerAddress, address validator) internal view returns (bytes memory initCode) {
        bytes memory moduleInitData = abi.encodePacked(ownerAddress);

        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(validator, moduleInitData);
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");

        bytes memory saDeploymentIndex = "0";

        // Create initcode and salt to be sent to Factory
        bytes memory _initData = BOOTSTRAPPER.getInitNexusScopedCalldata(validators, hook, REGISTRY, ATTESTERS, THRESHOLD);

        bytes32 salt = keccak256(saDeploymentIndex);

        bytes memory factoryData = abi.encodeWithSelector(FACTORY.createAccount.selector, _initData, salt);

        // Prepend the factory address to the encoded function call to form the initCode
        initCode =
            abi.encodePacked(address(META_FACTORY), abi.encodeWithSelector(META_FACTORY.deployWithFactory.selector, address(FACTORY), factoryData));
    }

    /// @notice Prepares a user operation with init code and call data
    /// @param wallet The wallet for which the user operation is prepared
    /// @param initCode The init code
    /// @param callData The call data
    /// @param validator The validator address
    /// @return userOp The prepared user operation
    function buildUserOpWithInitAndCalldata(
        Vm.Wallet memory wallet,
        bytes memory initCode,
        bytes memory callData,
        address validator
    )
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        userOp = buildUserOpWithCalldata(wallet, callData, validator);
        userOp.initCode = initCode;

        bytes memory signature = signUserOp(wallet, userOp);
        userOp.signature = signature;
    }

    /// @notice Prepares a user operation with call data and a validator
    /// @param wallet The wallet for which the user operation is prepared
    /// @param callData The call data
    /// @param validator The validator address
    /// @return userOp The prepared user operation
    function buildUserOpWithCalldata(
        Vm.Wallet memory wallet,
        bytes memory callData,
        address validator
    )
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        address payable account = calculateAccountAddress(wallet.addr, validator);
        uint256 nonce = getNonce(account, validator);
        userOp = buildPackedUserOp(account, nonce);
        userOp.callData = callData;

        bytes memory signature = signUserOp(wallet, userOp);
        userOp.signature = signature;
    }
    /// @notice Retrieves the nonce for a given account and validator
    /// @param account The account address
    /// @param validator The validator address
    /// @return nonce The retrieved nonce

    function getNonce(address account, address validator) internal view returns (uint256 nonce) {
        uint192 key = uint192(bytes24(bytes20(address(validator))));
        nonce = ENTRYPOINT.getNonce(address(account), key);
    }

    /// @notice Signs a user operation
    /// @param wallet The wallet to sign the operation
    /// @param userOp The user operation to sign
    /// @return The signed user operation
    function signUserOp(Vm.Wallet memory wallet, PackedUserOperation memory userOp) internal view returns (bytes memory) {
        bytes32 opHash = ENTRYPOINT.getUserOpHash(userOp);
        return signMessage(wallet, opHash);
    }

    // -----------------------------------------
    // Utility Functions
    // -----------------------------------------

    /// @notice Modifies the address of a deployed contract in a test environment
    /// @param originalAddress The original address of the contract
    /// @param newAddress The new address to replace the original
    function changeContractAddress(address originalAddress, address newAddress) internal {
        vm.etch(newAddress, originalAddress.code);
    }

    /// @notice Builds a user operation struct for account abstraction tests
    /// @param sender The sender address
    /// @param nonce The nonce
    /// @return userOp The built user operation
    function buildPackedUserOp(address sender, uint256 nonce) internal pure returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // verification and call gas limit
            preVerificationGas: 3e5, // Adjusted preVerificationGas
            gasFees: bytes32(abi.encodePacked(uint128(3e6), uint128(3e6))), // maxFeePerGas and maxPriorityFeePerGas
            paymasterAndData: "",
            signature: ""
        });
    }

    /// @notice Signs a message and packs r, s, v into bytes
    /// @param wallet The wallet to sign the message
    /// @param messageHash The hash of the message to sign
    /// @return signature The packed signature
    function signMessage(Vm.Wallet memory wallet, bytes32 messageHash) internal pure returns (bytes memory signature) {
        bytes32 userOpHash = ECDSA.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet.privateKey, userOpHash);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Prepares a packed user operation with specified parameters
    /// @param signer The wallet to sign the operation
    /// @param account The Nexus account
    /// @param execType The execution type
    /// @param executions The executions to include
    /// @param validator The validator address
    /// @return userOps The prepared packed user operations
    function buildPackedUserOperation(
        Vm.Wallet memory signer,
        Nexus account,
        ExecType execType,
        Execution[] memory executions,
        address validator
    )
        internal
        view
        returns (PackedUserOperation[] memory userOps)
    {
        // Validate execType
        require(execType == EXECTYPE_DEFAULT || execType == EXECTYPE_TRY, "Invalid ExecType");

        // Determine mode and calldata based on callType and executions length
        ExecutionMode mode;
        bytes memory executionCalldata;
        uint256 length = executions.length;

        if (length == 1) {
            mode = (execType == EXECTYPE_DEFAULT) ? ModeLib.encodeSimpleSingle() : ModeLib.encodeTrySingle();
            executionCalldata =
                abi.encodeCall(Nexus.execute, (mode, ExecLib.encodeSingle(executions[0].target, executions[0].value, executions[0].callData)));
        } else if (length > 1) {
            mode = (execType == EXECTYPE_DEFAULT) ? ModeLib.encodeSimpleBatch() : ModeLib.encodeTryBatch();
            executionCalldata = abi.encodeCall(Nexus.execute, (mode, ExecLib.encodeBatch(executions)));
        } else {
            revert("Executions array cannot be empty");
        }

        // Initialize the userOps array with one operation
        userOps = new PackedUserOperation[](1);

        // Build the UserOperation
        userOps[0] = buildPackedUserOp(address(account), getNonce(address(account), validator));
        userOps[0].callData = executionCalldata;

        // Sign the operation
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(signer, userOpHash);

        return userOps;
    }

    /// @dev Returns a random non-zero address.
    /// @notice Returns a random non-zero address
    /// @return result A random non-zero address
    function randomNonZeroAddress() internal returns (address result) {
        do {
            result = address(uint160(random()));
        } while (result == address(0));
    }

    /// @notice Checks if an address is a contract
    /// @param account The address to check
    /// @return True if the address is a contract, false otherwise
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @dev credits: vectorized || solady
    /// @dev Returns a pseudorandom random number from [0 .. 2**256 - 1] (inclusive).
    /// For usage in fuzz tests, please ensure that the function has an unnamed uint256 argument.
    /// e.g. `testSomething(uint256) public`.
    function random() internal returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
            // This is the keccak256 of a very long string I randomly mashed on my keyboard.
            let sSlot := 0xd715531fe383f818c5f158c342925dcf01b954d24678ada4d07c36af0f20e1ee
            let sValue := sload(sSlot)

            mstore(0x20, sValue)
            r := keccak256(0x20, 0x40)

            // If the storage is uninitialized, initialize it to the keccak256 of the calldata.
            if iszero(sValue) {
                sValue := sSlot
                let m := mload(0x40)
                calldatacopy(m, 0, calldatasize())
                r := keccak256(m, calldatasize())
            }
            sstore(sSlot, add(r, 1))

            // Do some biased sampling for more robust tests.
            // prettier-ignore
            for { } 1 { } {
                let d := byte(0, r)
                // With a 1/256 chance, randomly set `r` to any of 0,1,2.
                if iszero(d) {
                    r := and(r, 3)
                    break
                }
                // With a 1/2 chance, set `r` to near a random power of 2.
                if iszero(and(2, d)) {
                    // Set `t` either `not(0)` or `xor(sValue, r)`.
                    let t := xor(not(0), mul(iszero(and(4, d)), not(xor(sValue, r))))
                    // Set `r` to `t` shifted left or right by a random multiple of 8.
                    switch and(8, d)
                    case 0 {
                        if iszero(and(16, d)) { t := 1 }
                        r := add(shl(shl(3, and(byte(3, r), 0x1f)), t), sub(and(r, 7), 3))
                    }
                    default {
                        if iszero(and(16, d)) { t := shl(255, 1) }
                        r := add(shr(shl(3, and(byte(3, r), 0x1f)), t), sub(and(r, 7), 3))
                    }
                    // With a 1/2 chance, negate `r`.
                    if iszero(and(0x20, d)) { r := not(r) }
                    break
                }
                // Otherwise, just set `r` to `xor(sValue, r)`.
                r := xor(sValue, r)
                break
            }
        }
    }

    /// @notice Pre-funds a smart account and asserts success
    /// @param sa The smart account address
    /// @param prefundAmount The amount to pre-fund
    function prefundSmartAccountAndAssertSuccess(address sa, uint256 prefundAmount) internal {
        (bool res,) = sa.call{ value: prefundAmount }(""); // Pre-funding the account contract
        assertTrue(res, "Pre-funding account should succeed");
    }

    /// @notice Prepares a single execution
    /// @param to The target address
    /// @param value The value to send
    /// @param data The call data
    /// @return execution The prepared execution array
    function prepareSingleExecution(address to, uint256 value, bytes memory data) internal pure returns (Execution[] memory execution) {
        execution = new Execution[](1);
        execution[0] = Execution(to, value, data);
    }

    /// @notice Prepares several identical executions
    /// @param execution The execution to duplicate
    /// @param executionsNumber The number of executions to prepare
    /// @return executions The prepared executions array
    function prepareSeveralIdenticalExecutions(Execution memory execution, uint256 executionsNumber) internal pure returns (Execution[] memory) {
        Execution[] memory executions = new Execution[](executionsNumber);
        for (uint256 i = 0; i < executionsNumber; i++) {
            executions[i] = execution;
        }
        return executions;
    }

    /// @notice Helper function to execute a single operation.
    function executeSingle(
        Vm.Wallet memory user,
        Nexus userAccount,
        address target,
        uint256 value,
        bytes memory callData,
        ExecType execType
    )
        internal
    {
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({ target: target, value: value, callData: callData });

        PackedUserOperation[] memory userOps = buildPackedUserOperation(user, userAccount, execType, executions, address(VALIDATOR_MODULE));
        ENTRYPOINT.handleOps(userOps, payable(user.addr));
    }

    /// @notice Helper function to execute a batch of operations.
    function executeBatch(Vm.Wallet memory user, Nexus userAccount, Execution[] memory executions, ExecType execType) internal {
        PackedUserOperation[] memory userOps = buildPackedUserOperation(user, userAccount, execType, executions, address(VALIDATOR_MODULE));
        ENTRYPOINT.handleOps(userOps, payable(user.addr));
    }

    /// @notice Calculates the gas cost of the calldata
    /// @param data The calldata
    /// @return calldataGas The gas cost of the calldata
    function calculateCalldataCost(bytes memory data) internal pure returns (uint256 calldataGas) {
        for (uint256 i = 0; i < data.length; i++) {
            if (uint8(data[i]) == 0) {
                calldataGas += 4;
            } else {
                calldataGas += 16;
            }
        }
    }

    /// @notice Helper function to measure and log gas for simple EOA calls
    /// @param description The description for the log
    /// @param target The target contract address
    /// @param value The value to be sent with the call
    /// @param callData The calldata for the call
    function measureAndLogGasEOA(string memory description, address target, uint256 value, bytes memory callData) internal {
        uint256 calldataCost = 0;
        for (uint256 i = 0; i < callData.length; i++) {
            if (uint8(callData[i]) == 0) {
                calldataCost += 4;
            } else {
                calldataCost += 16;
            }
        }

        uint256 baseGas = 21_000;

        uint256 initialGas = gasleft();
        (bool res,) = target.call{ value: value }(callData);
        uint256 gasUsed = initialGas - gasleft() + baseGas + calldataCost;
        assertTrue(res);
        emit log_named_uint(description, gasUsed);
    }

    /// @notice Helper function to calculate calldata cost and log gas usage
    /// @param description The description for the log
    /// @param userOps The user operations to be executed
    function measureAndLogGas(string memory description, PackedUserOperation[] memory userOps) internal {
        bytes memory callData = abi.encodeWithSelector(ENTRYPOINT.handleOps.selector, userOps, payable(BUNDLER.addr));

        uint256 calldataCost = 0;
        for (uint256 i = 0; i < callData.length; i++) {
            if (uint8(callData[i]) == 0) {
                calldataCost += 4;
            } else {
                calldataCost += 16;
            }
        }

        uint256 baseGas = 21_000;

        uint256 initialGas = gasleft();
        ENTRYPOINT.handleOps(userOps, payable(BUNDLER.addr));
        uint256 gasUsed = initialGas - gasleft() + baseGas + calldataCost;
        emit log_named_uint(description, gasUsed);
    }

    /// @notice Handles a user operation and measures gas usage
    /// @param userOps The user operations to handle
    /// @param refundReceiver The address to receive the gas refund
    /// @return gasUsed The amount of gas used
    function handleUserOpAndMeasureGas(PackedUserOperation[] memory userOps, address refundReceiver) internal returns (uint256 gasUsed) {
        uint256 gasStart = gasleft();
        ENTRYPOINT.handleOps(userOps, payable(refundReceiver));
        gasUsed = gasStart - gasleft();
    }

    /// @notice Generates and signs the paymaster data for a user operation.
    /// @dev This function prepares the `paymasterAndData` field for a `PackedUserOperation` with the correct signature.
    /// @param userOp The user operation to be signed.
    /// @param signer The wallet that will sign the paymaster hash.
    /// @param paymaster The paymaster contract.
    /// @return Updated `PackedUserOperation` with `paymasterAndData` field correctly set.
    function generateAndSignPaymasterData(
        PackedUserOperation memory userOp,
        Vm.Wallet memory signer,
        MockPaymaster paymaster
    )
        internal
        view
        returns (bytes memory)
    {
        // Validity timestamps
        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint48 validAfter = uint48(block.timestamp);

        // Initial paymaster data with zero signature
        bytes memory initialPmData = abi.encodePacked(
            address(paymaster),
            uint128(3e6), // Verification gas limit
            uint128(0), // Post-operation gas limit
            abi.encode(validUntil, validAfter),
            new bytes(65) // Zero signature
        );

        // Update user operation with initial paymaster data
        userOp.paymasterAndData = initialPmData;

        // Generate hash to be signed
        bytes32 paymasterHash = paymaster.getHash(userOp, validUntil, validAfter);

        // Sign the hash
        bytes memory paymasterSignature = signMessage(signer, paymasterHash);
        require(paymasterSignature.length == 65, "Invalid Paymaster Signature length");

        // Final paymaster data with the actual signature
        bytes memory finalPmData = abi.encodePacked(
            address(paymaster),
            uint128(3e6), // Verification gas limit
            uint128(0), // Post-operation gas limit
            abi.encode(validUntil, validAfter),
            paymasterSignature
        );

        return finalPmData;
    }
}
