// SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE * 2); // Increase to 20 ETH
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), STARTING_ERC20_BALANCE * 2);
        dsce.depositCollateral(weth, STARTING_ERC20_BALANCE * 2); // Deposit 20 ETH
        dsce.mintDsc(10000e18);
        vm.stopPrank();
    }
    ///////////////////////////////
    // Constructor Test ///////////
    ///////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }
    /////////////////////////
    // Price Test ///////////
    /////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // Example 15 ETH * 2000 USD = 30000 USD this is from ETH_USD_PRICE in HelperConfig
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
    ///////////////////////////////////////
    // Deposit Collateral Tests ///////////
    ///////////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////////////////////////
    //   Redeem collateral tests  ///
    //////////////////////////////////

    function testRevertIfRedeemAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToRedeem = 5 ether;
        uint256 initialCollateralValue = dsce.getAccountCollateralValue(USER);
        dsce.redeemCollateral(weth, amountToRedeem);
        uint256 finalCollateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = initialCollateralValue - dsce.getUsdValue(weth, amountToRedeem);
        assertEq(finalCollateralValue, expectedCollateralValue);
        assertEq(ERC20Mock(weth).balanceOf(USER), 5 ether);
        vm.stopPrank();
    }

    function testRevertIfRedeemBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        // Mint DSC to make health factor critical
        uint256 usdCollateralValue = dsce.getAccountCollateralValue(USER); // 10 ETH * 2000 = 20,000 USD
        uint256 maxDscToMint = (usdCollateralValue * 50) / 100; // 50% of collateral value = 10,000 USD
        dsce.mintDsc(maxDscToMint);
        // Attempt to redeem some collateral, which should break health factor
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0.9e18));
        dsce.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    //////////////////////////////
    //  Mint DSC Test   //////////
    //////////////////////////////

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountDscToMint = 1000e18;
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDscToMint);
        assertEq(dsc.balanceOf(USER), amountDscToMint);
        vm.stopPrank();
    }

    function testRevertIfMintBreaksHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 excessiveDsc = 10001e18;
        dsc.approve(address(dsce), excessiveDsc);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 999900009999000099));
        dsce.mintDsc(excessiveDsc);
        vm.stopPrank();
    }

    ////////////////////////////////
    // Burn DSC Tests    ///////////
    ////////////////////////////////

    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateral {
        vm.startPrank(USER);
        // mint some DSC
        uint256 amountDscToMint = 1000e18;
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        // burn half
        uint256 amountToBurn = 500e18;
        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDscToMint - amountToBurn);
        assertEq(dsc.balanceOf(USER), amountDscToMint - amountToBurn);
        vm.stopPrank();
    }
    //

    function testRevertIfBurnExceedsMinted() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountDscToMint = 1000e18;
        //  dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        uint256 excessiveBurn = 1001e18;
        // dsc.approve(address(dsce), excessiveBurn);
        vm.expectRevert(DSCEngine.DSCEngine__BurnAmountExceedsMinted.selector);
        dsce.burnDsc(excessiveBurn);
        vm.stopPrank();
    }
    ///////////////////////////////////////
    // Deposit and Mint Combined Tests ////
    ///////////////////////////////////////

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        uint256 amountCollateral = 5 ether;
        uint256 amountDscToMint = 5000e18; // 5000 DSC
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountDscToMint);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateral = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountDscToMint);
        assertEq(expectedCollateral, amountCollateral);
        vm.stopPrank();
    }

    /////////////////////////////
    // Redeem and Burn Tests ////
    /////////////////////////////

    function testRedeemCollateralForDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountDscToMint = 1000e18;
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        uint256 amountCollateralToRedeem = 2 ether;
        uint256 amountDscToBurn = 400e18;
        dsc.approve(address(dsce), amountDscToBurn);
        dsce.redeemCollateralForDsc(weth, amountCollateralToRedeem, amountDscToBurn);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateral = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, amountDscToMint - amountDscToBurn);
        assertEq(expectedCollateral, AMOUNT_COLLATERAL - amountCollateralToRedeem);
        vm.stopPrank();
    }

    //////////////////////////
    // Liquidation Tests /////
    //////////////////////////

    function testDoNotLiquidateIfHealthFactorNotBroken() public depositedCollateral {
        vm.startPrank(LIQUIDATOR);
        uint256 debtToCover = 100e18;
        dsc.approve(address(dsce), debtToCover);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCanLiquidateUser() public depositedCollateral {
        vm.startPrank(USER);
        // Mint DSC to break health factor
        uint256 amountDscToMint = 10000e18;
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        // Simulate price drop to break health factor (e.g., WETH price to $1000)
        vm.startPrank(address(this));
        MockV3Aggregator wethPriceFeed = MockV3Aggregator(ethUsdPriceFeed);
        wethPriceFeed.updateAnswer(1000e8); // WETH = $1000
        vm.stopPrank();

        // switch to liquidator user
        vm.startPrank(LIQUIDATOR);
        uint256 debtToCover = 10000e18;
        dsc.approve(address(dsce), debtToCover);
        uint256 initialLiquidatorWeth = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        dsce.liquidate(weth, USER, debtToCover);
        uint256 finalLiquidatorWeth = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        // Expect the liquidator to receive up to 10 ETH (user's entire collateral)
        uint256 expectedWethReceived = 10e18; // User's full collateral
        assertEq(finalLiquidatorWeth - initialLiquidatorWeth, expectedWethReceived);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        // Expect all DSC to be burned
        uint256 expectedDscBurned = 10000e18; // All user DSC burned
        assertEq(totalDscMinted, 0); // totalDscMinted = amountDscToMint - expectedDscBurned
        vm.stopPrank();
    }

    function testPartialLiquidation() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountDscToMint = 6000e18;
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        vm.startPrank(address(this));
        MockV3Aggregator wethPriceFeed = MockV3Aggregator(ethUsdPriceFeed);
        wethPriceFeed.updateAnswer(1000e8); // WETH = $1,000
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        uint256 debtToCover = 3000e18;
        dsc.approve(address(dsce), debtToCover);
        uint256 initialLiquidatorWeth = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        dsce.liquidate(weth, USER, debtToCover);
        uint256 finalLiquidatorWeth = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        uint256 expectedWethReceived = (3000e18 * 1e18 / (1000e8 * 1e10)) * 110 / 100; // 5.5 ETH
        assertEq(finalLiquidatorWeth - initialLiquidatorWeth, expectedWethReceived);
        (uint256 totalDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, amountDscToMint - debtToCover);
        vm.stopPrank();
    }

    function testGetHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountDscToMint = 5000e18; // 5000 DSC
        dsc.approve(address(dsce), amountDscToMint);
        dsce.mintDsc(amountDscToMint);
        // Collateral = 10 ETH * 2000 USD = 20,000 USD
        // Adjusted = 20,000 * 50% = 10,000 USD
        // Health factor = (10,000 * 1e18) / 5000 = 2e18
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, 2e18);
        vm.stopPrank();
    }

    function testHealthFactorWhenNoDscMinted() public depositedCollateral {
        // No DSC minted, health factor should be "infinite" (max uint256 in practice)
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }
}
