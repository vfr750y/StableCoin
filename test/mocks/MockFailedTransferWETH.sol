// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailedTransferWETH is ERC20 {
    constructor() ERC20("MockWETH", "MWETH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Force transfer to return false to trigger DSCEngine__TransferFailed
    function transfer(address, uint256) public override returns (bool) {
        return false;
    }
}