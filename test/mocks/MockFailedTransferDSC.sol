// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransferDSC is ERC20, Ownable {
    constructor() ERC20("MockDSC", "MDSC") {}

    // MUST return true for DSCEngine to proceed
    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    // This is what we are testing
    function transferFrom(address, address, uint256) public override returns (bool) {
        return false; 
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}