//SPDX-License_Identifier:MIT

// This file contains the invariants (properties of our system that should behave the same in all cases)
// 1. Total supply of DSC should be less than the total collateral
// 2. The getter view functions should never revert

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "./../../script/DeployDsc.s.sol";
import {DSCEngine} from "./../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "./../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // comper it a to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        /*
        // Check totalWethDeposited == 0 before calling getUSDValue()
        if (totalWethDeposited == 0) {
            // If 0: Skip USD calculation and assert that totalSupply must also be 0
            console.log("No WETH deposited, skipping USD value calculation");
            assert(totalSupply == 0);
            // If > 0: Continue with normal flow
            return;
        }

        if (totalWbtcDeposited == 0) {
            // If 0: Skip USD calculation and assert that totalSupply must also be 0
            console.log("No WBTC deposited, skipping USD value calculation");
            assert(totalSupply == 0);
            // If > 0: Continue with normal flow
            return;
        }
        */
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value", wethValue);
        console.log("wbtc value", wbtcValue);
        console.log("total supply", totalSupply);
        console.log("times mint called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
