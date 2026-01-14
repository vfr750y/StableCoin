// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract ERC20ReturnFalseMock is ERC20Mock {
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance) 
        ERC20Mock(name, symbol, initialAccount, initialBalance) {}

    function transferFrom(address, address, uint256) public override returns (bool) {
        return false; // This triggers your if(!success) check
    }
}
