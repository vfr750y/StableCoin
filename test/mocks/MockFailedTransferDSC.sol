// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailedTransferDSC is ERC20 {
    constructor() ERC20("MockDSC", "MDSC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // This is the key: force transferFrom to return false
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}