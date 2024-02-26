// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IValidator, IModule, VALIDATION_SUCCESS, VALIDATION_FAILED } from "../../interfaces/IERC7579Modules.sol";
import { EncodedModuleTypes } from "../../lib/ModuleTypeLib.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockValidator is IValidator {
    mapping(address => address) public owners;

    /// @inheritdoc IValidator
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        returns (uint256 validation)
    {
        return ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(userOpHash), userOp.signature)
            == owners[msg.sender] ? VALIDATION_SUCCESS : VALIDATION_FAILED;
    }

    /// @inheritdoc IValidator
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata data
    )
        external
        view
        returns (bytes4)
    {
        sender;
        hash;
        data;
        return 0xffffffff;
    }

    /// @inheritdoc IModule
    function onInstall(bytes calldata data) external {
        owners[msg.sender] = address(bytes20(data));
    }

    /// @inheritdoc IModule
    function onUninstall(bytes calldata data) external {
        delete owners[msg.sender];
    }

    /// @inheritdoc IModule
    function isModuleType(uint256 typeID) external view returns (bool) {
        typeID;
        return true;
    }

    function isOwner(address account, address owner) external view returns (bool) {
        return owners[account] == owner;
    }

    /// @inheritdoc IModule
    function getModuleTypes() external view returns (EncodedModuleTypes) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function test(uint256 a) public {
        a;
    }
}
