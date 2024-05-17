// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../../utils/Imports.sol";
import "../../../utils/SmartAccountTestLab.t.sol";

contract TestERC4337Account_ValidateUserOp is Test, SmartAccountTestLab {
    Vm.Wallet internal signer;
    Nexus internal account;
    function setUp() public {
        init();

        signer = createAndFundWallet("Signer", 0.0001 ether);
        account = deployNexus(signer, 0.0001 ether, address(VALIDATOR_MODULE));
    }

    function testPayPrefund_WithSufficientFunds() public {
        vm.deal(address(account), 1 ether);

        Execution[] memory executions = _prepareSingleExecution(address(account), 0, "");
        PackedUserOperation[] memory userOps = buildPackedUserOperation(signer, account, EXECTYPE_TRY, executions, address(VALIDATOR_MODULE));
        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[0]);
        userOps[0].signature = signMessage(signer, userOpHash);

        prank(address(ENTRYPOINT));
        account.validateUserOp(userOps[0], userOpHash, 0.1 ether);
        stopPrank();
    }
}
