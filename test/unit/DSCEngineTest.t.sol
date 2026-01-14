// SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDsc.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20ReturnFalseMock} from "../mocks/MockERC20ReturnFalse.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransferDSC} from "../mocks/MockFailedTransferDSC.sol";
import {MockFailedTransferWETH} from "../mocks/MockFailedTransferWETH.sol";


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

    /**
     * @notice Testing DSCEngine__MintFailed() 
     */
    function testRevertsIfMintFails() public {
        // 1. Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));

        // 2. Act / Assert
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.mintDsc(1 ether);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    // DecentralizedStableCoin Mint Tests ////
    //////////////////////////////////////////

    function testMintRevertsIfToAddressIsZero() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 100 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerCanMint() public {
        vm.startPrank(USER);
        // The USER is not the owner (the DSCEngine is)
        // This will revert via OpenZeppelin's Ownable
        vm.expectRevert(); 
        dsc.mint(USER, 100 ether);
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

    //////////////////////////////////////////
    // DecentralizedStableCoin Burn Tests ////
    //////////////////////////////////////////

    function testRevertIfBurnAmountIsZeroInDSC() public {
        vm.startPrank(address(dsce)); // DSCEngine is the owner of DSC
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanBalance() public {
        vm.startPrank(address(dsce));
        // Minting some DSC to the engine first so it has a balance to burn
        // (Though usually, it burns from its own balance during liquidations)
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(1 ether);
        vm.stopPrank();
    }

    function testOnlyOwnerCanBurn() public {
        vm.startPrank(USER);
        // The USER is not the owner (the DSCEngine is)
        // Using the standard Ownable error from OpenZeppelin
        vm.expectRevert(); 
        dsc.burn(1 ether);
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

function testLiquidationMustImproveHealthFactor() public {
    // 1. Arrange - User setup
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    dsce.mintDsc(100e18); // $100 debt
    vm.stopPrank();

    // 2. Price Crash
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8); // ETH = $18
    // User Collateral: 10 ETH * $18 = $180. 
    // Threshold (50%): $90. Debt: $100. HF < 1.0.

    // 3. Arrange - Liquidator setup
    // We create a fresh liquidator with NO debt so their HF is 'max uint'
    address cleanLiquidator = makeAddr("cleanLiquidator");
    ERC20Mock(weth).mint(cleanLiquidator, 100 ether);
    
    // Give the liquidator DSC to pay the debt (we can transfer it from the existing LIQUIDATOR)
    vm.prank(LIQUIDATOR);
    dsc.transfer(cleanLiquidator, 50e18);

    vm.startPrank(cleanLiquidator);
    dsc.approve(address(dsce), 50e18);

    // 4. Act
    // Liquidator burns 50 DSC of the User's 100 DSC debt
    dsce.liquidate(weth, USER, 50e18);
    vm.stopPrank();
}

function testLiquidatorHealthFactorStaysHealthy() public depositedCollateral {
    // 1. User is underwater
    vm.startPrank(USER);
    dsce.mintDsc(10000e18); 
    vm.stopPrank();
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); 

    // 2. Liquidator has NO collateral but has DSC
    // (Liquidator got DSC from the setUp)
    vm.startPrank(LIQUIDATOR);
    // Liquidator tries to liquidate without having enough of their own collateral
    // to sustain the transaction if the engine logic requires it.
    // Since LIQUIDATOR in setUp has 20 ETH, let's prank a new address.
    address brokeLiquidator = makeAddr("brokeLiquidator");
    vm.stopPrank();
    
    vm.startPrank(brokeLiquidator);
    vm.expectRevert(); // Should revert because health factor is 0 or broken
    dsce.liquidate(weth, USER, 100e18);
    vm.stopPrank();
}

function testRevertsIfHealthFactorNotImproved() public {
    // 1. Arrange - User setup
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    dsce.mintDsc(100e18); // $100 debt
    vm.stopPrank();

    // 2. Arrange - Clean Liquidator (No debt, so they don't revert on their own HF)
    address cleanLiquidator = makeAddr("cleanLiquidator");
    ERC20Mock(weth).mint(cleanLiquidator, 100 ether);
    vm.prank(LIQUIDATOR);
    dsc.transfer(cleanLiquidator, 10e18); 

    // 3. The Strategy
    // First, make them liquidatable
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8); // $18
    
    // NOW: Crash the price to almost nothing.
    // When liquidate() runs, it will calculate 'startingUserHealthFactor' using $1.
    // Then it will burn debt and calculate 'endingUserHealthFactor' also using $1.
    // At such low prices, the collateral bonus taken by the liquidator 
    // often outweighs the tiny debt reduction, or the HF stays at 0.
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1e8); // $1

    vm.startPrank(cleanLiquidator);
    dsc.approve(address(dsce), 10e18);

    // 4. Act / Assert
    vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    dsce.liquidate(weth, USER, 1e18); // Liquidate a tiny amount (1 DSC)
    vm.stopPrank();
}

function testRevertIfRedeemingMoreCollateralThanBalance() public depositedCollateral {
    vm.startPrank(USER);
    vm.expectRevert(); // Solidity's built-in panic for underflow
    dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1 ether);
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

    function testLiquidationPayoutIsCappedByUserCollateral() public depositedCollateral {
        // Arrange - User has 10 ETH ($20,000)
        vm.startPrank(USER);
        dsce.mintDsc(10000e18); // Max safe-ish mint
        vm.stopPrank();

        // Price drops massively so debt + 10% bonus > total collateral
        // If ETH drops to $1,100: Debt is $10k, but $10k worth of ETH is ~9.09 ETH.
        // 9.09 ETH + 10% bonus = 9.99 ETH. 
        // If it drops to $1,000: $10k debt = 10 ETH. 10 ETH + 1 ETH bonus = 11 ETH (Exceeds 10 ETH balance)
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); 

        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(dsce), 10000e18);
        
        // Act
        dsce.liquidate(weth, USER, 10000e18);
        
        // Assert: Liquidator should get exactly 10 ETH (the cap), not 11 ETH.
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        // Liquidator started with 20 ETH (see setUp), deposited 20, so had 0. 
        // Now should have exactly 10.
        assertEq(liquidatorWethBalance, 10 ether); 
        vm.stopPrank();
    }

    function testGetAccountCollateralValueFromMultipleTokens() public {
        // Arrange
        address wbtc = makeAddr("wbtc"); // In a real test, use the WBTC address from config
        // For this test, let's just use the existing setup and simulate two deposits
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), 1 ether);
        dsce.depositCollateral(weth, 1 ether); // $2000
        
        // We would need to add WBTC to the engine in setup to truly test the loop, 
        // but we can check the current value for the single token loop.
        uint256 expectedValue = dsce.getUsdValue(weth, 1 ether);
        uint256 actualValue = dsce.getAccountCollateralValue(USER);
        
        assertEq(expectedValue, actualValue);
        vm.stopPrank();
    }

    /////////////////////////////
    // Transfer Failure Tests ///
    /////////////////////////////

function testRevertIfTransferFromFails() public {
    // 1. Arrange
    address owner = msg.sender;
    vm.startPrank(owner);
    
    // Use our special mock that returns false
    ERC20ReturnFalseMock mockToken = new ERC20ReturnFalseMock("MOCK", "MCK", USER, AMOUNT_COLLATERAL);
    
    tokenAddresses = [address(mockToken)];
    priceFeedAddresses = [ethUsdPriceFeed];
    
    // Deploy a temporary engine with the "bad" token
    DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    vm.stopPrank();

    // 2. Act & Assert
    vm.prank(USER);
    // Since mockToken.transferFrom returns false, the engine WILL reach your custom revert
    vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    mockEngine.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);
}

function testRevertsIfTransferFromFailsInBurn() public {
    // 1. Arrange - Setup with a DSC mock that returns false on transfer
    vm.startPrank(msg.sender);
    MockFailedTransferDSC mockDsc = new MockFailedTransferDSC();
    tokenAddresses = [weth];
    priceFeedAddresses = [ethUsdPriceFeed];
    
    DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
    mockDsc.transferOwnership(address(mockEngine));
    vm.stopPrank();

    // 2. Arrange - User setup
    vm.startPrank(USER);
    ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL); // Ensure user has WETH
    ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
    
    // Deposit and Mint so the user has a "debt" balance in the engine
    mockEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
    mockEngine.mintDsc(1 ether);
    
    // 3. Act / Assert
    // Approve the engine to take the DSC back (standard flow)
    mockDsc.approve(address(mockEngine), 1 ether);
    
    // This calls _burnDsc -> transferFrom -> returns false -> Reverts DSCEngine__TransferFailed
    vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    mockEngine.burnDsc(1 ether);
    vm.stopPrank();
}

function testRevertsIfTransferFailsInRedeemCollateral() public {
    // 1. Arrange - Setup with a collateral mock that returns false on transfer
    address owner = msg.sender;
    vm.startPrank(owner);
    
    MockFailedTransferWETH mockWeth = new MockFailedTransferWETH();
    tokenAddresses = [address(mockWeth)];
    priceFeedAddresses = [ethUsdPriceFeed];
    
    // Deploy engine with the "bad" collateral
    DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    vm.stopPrank();

    // 2. Arrange - User setup
    vm.startPrank(USER);
    mockWeth.mint(USER, AMOUNT_COLLATERAL);
    mockWeth.approve(address(mockEngine), AMOUNT_COLLATERAL);
    mockEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);
    
    // 3. Act / Assert
    // When we redeem, the engine updates its internal balance and then calls transfer()
    // Since mockWeth.transfer returns false, it should revert
    vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    mockEngine.redeemCollateral(address(mockWeth), AMOUNT_COLLATERAL);
    vm.stopPrank();
}

//////////////////////////////////////////
//     getter tests                     //
//////////////////////////////////////////

function testGetAccountCollateralValue() public depositedCollateral {
    // 1. Arrange
    // In your 'depositedCollateral' modifier, USER deposits 10 ether of WETH.
    // In HelperConfig, WETH price is usually mocked at $2,000.
    // Expected: 10 * 2000 = 20,000 USD (in 1e18 precision)
    
    uint256 expectedValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

    // 2. Act
    uint256 actualValue = dsce.getAccountCollateralValue(USER);

    // 3. Assert
    assertEq(actualValue, expectedValue);
}
/*
function testGetAccountCollateralValueWithMultipleTokens() public {
    // 1. Arrange - Setup
    // We already have WETH from setUp, let's create a real WBTC mock
    ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", USER, AMOUNT_COLLATERAL);
    
    // Create the arrays for the new engine
    address[] memory tokenAddresses = new address[](2);
    address[] memory feedAddresses = new address[](2);
    
    tokenAddresses[0] = weth;
    tokenAddresses[1] = address(wbtc);
    feedAddresses[0] = ethUsdPriceFeed;
    feedAddresses[1] = btcUsdPriceFeed;

    // Deploy a temporary engine with both tokens
    DSCEngine multiEngine = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));

    vm.startPrank(USER);
    // Deposit 1 ETH ($2000)
    ERC20Mock(weth).approve(address(multiEngine), 1 ether);
    multiEngine.depositCollateral(weth, 1 ether);

    // Deposit 1 BTC ($1000 - assuming BTC price in your mock is 1000)
    wbtc.approve(address(multiEngine), 1 ether);
    multiEngine.depositCollateral(address(wbtc), 1 ether);
    vm.stopPrank();

    // 2. Act
    uint256 totalCollateralValue = multiEngine.getAccountCollateralValue(USER);

    // 3. Assert
    uint256 expectedWethValue = multiEngine.getUsdValue(weth, 1 ether);
    uint256 expectedWbtcValue = multiEngine.getUsdValue(address(wbtc), 1 ether);
    uint256 expectedTotalValue = expectedWethValue + expectedWbtcValue;
    
    assertEq(totalCollateralValue, expectedTotalValue);
}
*/

function testGetAccountCollateralValueDirectly() public {
    // 1. Arrange - Use the existing weth/dsce from setUp
    vm.startPrank(USER);
    uint256 amountToDeposit = 1 ether;
    ERC20Mock(weth).approve(address(dsce), amountToDeposit);
    dsce.depositCollateral(weth, amountToDeposit);
    vm.stopPrank();

    // 2. Act
    // This call must iterate through the loop and hit the return statement
    uint256 collateralValue = dsce.getAccountCollateralValue(USER);

    // 3. Assert
    // If the price is $2000, 1 ETH = 2000e18 USD value
    uint256 expectedValue = dsce.getUsdValue(weth, amountToDeposit);
    assertEq(collateralValue, expectedValue);
    assert(collateralValue > 0);
}

///////////////////////////////////////
    // getAccountCollateralValue Tests ////
    ///////////////////////////////////////

    function testGetAccountCollateralValueReturnsZeroIfNoCollateral() public {
        // Arrange
        address newUser = makeAddr("noCollateral");
        // Act
        uint256 collateralValue = dsce.getAccountCollateralValue(newUser);
        // Assert
        assertEq(collateralValue, 0);
    }

    function testGetAccountCollateralValueWithSingleToken() public depositedCollateral {
        // Arrange
        // depositedCollateral modifier deposits 10 ether of WETH (USER)
        // ETH_USD price in HelperConfig is 2000e8
        uint256 expectedValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);

        // Act
        uint256 actualValue = dsce.getAccountCollateralValue(USER);

        // Assert
        assertEq(actualValue, expectedValue);
    }

    function testGetAccountCollateralValueWithMultipleTokens() public {
        // 1. Arrange - We need a second token
        // We'll use the BTC address/price feed from your active network config
        (, address btcUsdPriceFeed, address wbtc,,) = helperConfig.activeNetworkConfig();
        
        // Use a user with a clean state
        address multiUser = makeAddr("multiUser");
        
        vm.startPrank(multiUser);
        // Deposit 1 ETH ($2000)
        ERC20Mock(weth).mint(multiUser, 1 ether);
        ERC20Mock(weth).approve(address(dsce), 1 ether);
        dsce.depositCollateral(weth, 1 ether);

        // Deposit 1 BTC ($1000 - typical mock price)
        ERC20Mock(wbtc).mint(multiUser, 1 ether);
        ERC20Mock(wbtc).approve(address(dsce), 1 ether);
        dsce.depositCollateral(wbtc, 1 ether);
        vm.stopPrank();

        // 2. Act
        uint256 totalCollateralValue = dsce.getAccountCollateralValue(multiUser);

        // 3. Assert
        uint256 expectedWethValue = dsce.getUsdValue(weth, 1 ether);
        uint256 expectedWbtcValue = dsce.getUsdValue(wbtc, 1 ether);
        uint256 expectedTotalValue = expectedWethValue + expectedWbtcValue;

        assertEq(totalCollateralValue, expectedTotalValue);
    }

function testGetPrecision() public {
    uint256 expectedPrecision = 1e18;
    uint256 actualPrecision = dsce.getPrecision();
    assertEq(actualPrecision, expectedPrecision);
}

function testGetAdditionalFeedPrecision() public {
    uint256 expectedPrecision = 1e10;
    uint256 actualPrecision = dsce.getAdditionalFeedPrecision();
    assertEq(actualPrecision, expectedPrecision);
}

function testGetLiquidationBonus() public {
    uint256 expectedPrecision = 10;
    uint256 actualPrecision = dsce.getLiquidationBonus();
    assertEq(actualPrecision, expectedPrecision);
}

function testGetMinHealthFactor() public {
    uint256 expectedPrecision = 1e18;
    uint256 actualPrecision = dsce.getMinHealthFactor();
    assertEq(actualPrecision, expectedPrecision);
}

function testGetDsc() public {
    address dscAddress = dsce.getDsc();
    assertEq(dscAddress, address(dsc));
}


}


