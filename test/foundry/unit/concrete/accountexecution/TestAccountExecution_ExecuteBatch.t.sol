// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../shared/TestAccountExecution_Base.t.sol"; // Ensure this import path matches your project structure

contract TestAccountExecution_ExecuteBatch is TestAccountExecution_Base {
        function setUp() public {
            setUpTestAccountExecution_Base();
        }

        function test_ExecuteBatch_Success() public {
        assertEq(counter.getNumber(), 0, "Counter should start at 0");

        // Preparing a batch execution with two operations: increment and decrement
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution(address(counter), 0, abi.encodeWithSelector(Counter.incrementNumber.selector));
        executions[1] = Execution(address(counter), 0, abi.encodeWithSelector(Counter.incrementNumber.selector));

        // Execute batch operation
        PackedUserOperation[] memory userOps = prepareBatchExecutionUserOp(BOB, BOB_ACCOUNT, EXECTYPE_DEFAULT, executions);

        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));

        // Assert the counter value remains unchanged after increment and decrement
        assertEq(counter.getNumber(), 2, "Counter value should increment twice after batch execution");
    }

    function test_ExecuteBatch_Revert() public {
        assertEq(counter.getNumber(), 0, "Counter should start at 0");

        // Preparing a batch execution with two operations: increment and decrement
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution(address(counter), 0, abi.encodeWithSelector(Counter.incrementNumber.selector));
        executions[1] = Execution(address(counter), 0, abi.encodeWithSelector(Counter.revertOperation.selector));

        // Execute batch operation
        PackedUserOperation[] memory userOps = prepareBatchExecutionUserOp(BOB, BOB_ACCOUNT, EXECTYPE_DEFAULT, executions);

        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);

        bytes memory expectedRevertReason = abi.encodeWithSignature("Error(string)", "Counter: Revert operation");


        // Expect the UserOperationRevertReason event
        vm.expectEmit(true, true, true, true);

        emit UserOperationRevertReason(
            userOpHash,
            address(BOB_ACCOUNT),
            userOps[0].nonce,
            expectedRevertReason
        );
        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));

        assertEq(counter.getNumber(), 0, "Counter should remain unchanged after batch execution");
    }

    function test_ExecuteBatch_Empty() public {
        // Initial state assertion
        Execution[] memory executions = new Execution[](3);

        // Preparing a batch execution with two empty operations
        executions[0] = Execution(address(0), 0, "");
        executions[1] = Execution(address(0), 0, "");
        executions[2] = Execution(address(0), 0, "");

        // Execute batch operation
        PackedUserOperation[] memory userOps = prepareBatchExecutionUserOp(BOB, BOB_ACCOUNT, EXECTYPE_DEFAULT, executions);

        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));
    }

    function test_ExecuteBatch_ValueTransfer() public {
        address receiver = address(0x123);
        uint256 sendValue = 1 ether;

        // Fund BOB_ACCOUNT with 10 ETH to cover the value transfer
        payable(address(BOB_ACCOUNT)).call{ value: 10 ether }(""); // Fund BOB_ACCOUNT


        assertEq(receiver.balance, 0, "Receiver should have 0 ETH");

                // Initial state assertion
        Execution[] memory executions = new Execution[](3);

        // Preparing a batch execution with two empty operations
        executions[0] = Execution(receiver, sendValue, "");
        executions[1] = Execution(receiver, sendValue, "");
        executions[2] = Execution(receiver, sendValue, "");

        // Execute batch operation
        PackedUserOperation[] memory userOps = prepareBatchExecutionUserOp(BOB, BOB_ACCOUNT, EXECTYPE_DEFAULT, executions);

        ENTRYPOINT.handleOps(userOps, payable(BOB.addr));

        assertEq(receiver.balance, 3 ether, "Receiver should have received 3 ETH");
    }
}