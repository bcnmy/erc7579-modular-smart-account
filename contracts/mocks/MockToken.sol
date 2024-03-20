// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Note: could be imported from foundry mocks
contract MockToken is ERC20 {
    constructor() ERC20("TST", "MockToken") {}

    function mint(address sender, uint256 amount) external {
        _mint(sender, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}