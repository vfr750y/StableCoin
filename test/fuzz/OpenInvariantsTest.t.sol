//SPDX-License_Identifier:MIT

// This file contains the invariants (properties of our system that should behave the same in all cases)
// 1. Total supply of DSC should be less than the total collateral
// 2. The getter view functions should never revert

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "./../../script/DeployDsc.s.sol";
import {DSCEngine} from "./../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "./../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(dsce));
    }

    function invariant_protolMustHaceMoreValueTHanTotalSUpply() public view {
        // get the value of all the collateral in the protocol
        // comper it a to all the debt (dsc)
    }
}
