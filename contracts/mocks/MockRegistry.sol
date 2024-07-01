// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IERC7484 } from "../interfaces/IERC7484.sol";

contract MockRegistry is IERC7484 {
    event Log(address sender);

    function check(address module) external view {}

    function checkForAccount(address smartAccount, address module) external view {}

    function check(address module, uint256 moduleType) external view {}

    function checkForAccount(address smartAccount, address module, uint256 moduleType) external view override {}

    function check(address module, address[] calldata attesters, uint256 threshold) external view {}

    function check(address module, uint256 moduleType, address[] calldata attesters, uint256 threshold) external view {}

    function trustAttesters(uint8 threshold, address[] calldata attesters) external {
        emit Log(msg.sender);
        emit NewTrustedAttesters();
    }
}
