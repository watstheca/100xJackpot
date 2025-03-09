// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token100x is ERC20 {
    constructor() ERC20("100x Jackpot", "100x") {
        _mint(msg.sender, 1_000_000_000 * 10**6); // 1B 100x with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}