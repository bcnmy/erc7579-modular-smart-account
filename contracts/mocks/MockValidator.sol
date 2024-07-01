// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IModule } from "../interfaces/modules/IModule.sol";
import { IValidator } from "../interfaces/modules/IValidator.sol";
import { IModuleManager } from "../interfaces/base/IModuleManager.sol";
import { VALIDATION_SUCCESS, VALIDATION_FAILED, MODULE_TYPE_VALIDATOR, ERC1271_MAGICVALUE, ERC1271_INVALID } from "../types/Constants.sol";
import { PackedUserOperation } from "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import { ECDSA } from "solady/src/utils/ECDSA.sol";
import { SignatureCheckerLib } from "solady/src/utils/SignatureCheckerLib.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockValidator is IValidator {
    mapping(address => address) public smartAccountOwners;

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external view returns (uint256 validation) {
        return
            ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(userOpHash), userOp.signature) == smartAccountOwners[msg.sender]
                ? VALIDATION_SUCCESS
                : VALIDATION_FAILED;
    }

    function isValidSignatureWithSender(address, bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        address owner = smartAccountOwners[msg.sender];
        // MAYBE SHOULD PREPARE REPLAY RESISTANT HASH BY APPENDING MSG.SENDER
        // SEE: https://github.com/bcnmy/scw-contracts/blob/3362262dab34fa0f57e2fbe0e57a4bdbd5318165/contracts/smart-account/modules/EcdsaOwnershipRegistryModule.sol#L122-L132
        // OR USE EIP-712
        if (SignatureCheckerLib.isValidSignatureNowCalldata(owner, hash, signature)) {
            return ERC1271_MAGICVALUE;
        }
        if (SignatureCheckerLib.isValidSignatureNowCalldata(owner, MessageHashUtils.toEthSignedMessageHash(hash), signature)) {
            return ERC1271_MAGICVALUE;
        }
        return ERC1271_INVALID;
    }

    function onInstall(bytes calldata data) external {
        require(IModuleManager(msg.sender).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(this), ""), "Validator is still installed");
        smartAccountOwners[msg.sender] = address(bytes20(data));
    }

    function onUninstall(bytes calldata data) external {
        data;
        require(!IModuleManager(msg.sender).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(this), ""), "Validator is still installed");
        delete smartAccountOwners[msg.sender];
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    function isOwner(address account, address owner) external view returns (bool) {
        return smartAccountOwners[account] == owner;
    }

    function isInitialized(address) external pure returns (bool) {
        return false;
    }

    function getOwner(address account) external view returns (address) {
        return smartAccountOwners[account];
    }
}
