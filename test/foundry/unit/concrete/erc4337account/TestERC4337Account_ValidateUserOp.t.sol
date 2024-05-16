// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../../utils/Imports.sol";
import "../../../utils/SmartAccountTestLab.t.sol";

contract TestERC4337Account_ValidateUserOp is Test, SmartAccountTestLab {
    address public userAddress;

    function setUp() public {
        init();
        userAddress = address(BOB.addr);
    }

    function test_ValidateUserOp_ValidOperation() public {
        // Initialize a user operation with a valid setup
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildPackedUserOp(userAddress, getNonce(address(BOB_ACCOUNT), address(VALIDATOR_MODULE)));
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(BOB, userOpHash);

        startPrank(address(ENTRYPOINT));
        // Attempt to validate the user operation, expecting success
        uint256 res = BOB_ACCOUNT.validateUserOp(userOps[0], userOpHash, 0);
        assertTrue(res == 0, "Valid operation should pass validation");
        stopPrank();
    }

    function test_ValidateUserOp_InvalidSignature() public {
        // Initialize a user operation with a valid nonce but signed by an incorrect signer
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildPackedUserOp(userAddress, getNonce(address(BOB_ACCOUNT), address(VALIDATOR_MODULE)));
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(ALICE, userOpHash); // Incorrect signer simulated

        startPrank(address(ENTRYPOINT));
        // Attempt to validate the user operation, expecting failure due to invalid signature
        uint256 res = BOB_ACCOUNT.validateUserOp(userOps[0], userOpHash, 0);
        assertTrue(res == 1, "Operation with invalid signature should fail validation");
        stopPrank();
    }

    function test_ValidateUserOp_InvalidSignatureFormat() public {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildPackedUserOp(userAddress, getNonce(address(BOB_ACCOUNT), address(VALIDATOR_MODULE)));
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = "0x1234"; // Incorrect format, too short

        startPrank(address(ENTRYPOINT));
        vm.expectRevert(InvalidSignature.selector);
        BOB_ACCOUNT.validateUserOp(userOps[0], userOpHash, 0);
        stopPrank();
    }

    function test_ValidateUserOp_InsufficientFunds() public {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = buildPackedUserOp(userAddress, getNonce(address(BOB_ACCOUNT), address(VALIDATOR_MODULE)));
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(BOB, userOpHash);

        startPrank(address(ENTRYPOINT));
        BOB_ACCOUNT.validateUserOp(userOps[0], userOpHash, 5);
        stopPrank();
    }

    function test_ValidateUserOp_InvalidNonce() public {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        uint256 incorrectNonce = 123; // deliberately incorrect
        userOps[0] = buildPackedUserOp(userAddress, incorrectNonce);
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(BOB, userOpHash);

        startPrank(address(ENTRYPOINT));
        uint res = BOB_ACCOUNT.validateUserOp(userOps[0], userOpHash, 0);
        stopPrank();
        
        assertTrue(res == 1, "Operation with invalid nonce should fail validation");
    }
}
