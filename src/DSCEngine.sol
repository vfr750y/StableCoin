// SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/oracleLib.sol";
/**
 * * @title DSCEngine
 * * @author Ajay Curry
 * *
 * * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 USD peg
 * * This stablecoin has the properties
 * - Exogenous Collateral
 * - US Dollar Pegged
 * - Algorithmically Stable
 * It is similar to DAI if DAI had no gevernance, no fees, and was only backed by WETH and WBTC.
 * The DSC system should always be "overcollateralized"
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY losely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////////////
    //  Errors             //
    /////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BurnAmountExceedsMinted();
    /////////////////////////
    //  Type Declarations  //
    /////////////////////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////////
    //  State variables     //
    /////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // i.e. a 10% bonus;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////////
    //  Events             //
    /////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    ////////////////////////////
    //  Modifiers             //
    ////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////////////
    //  Constructor          //
    //////////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD PriceFeeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////
    //  External functions    //
    ////////////////////////////
    /**
     *
     * @param tokenCollateralAddress The address of the ERC20 token where the collateral comes from
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of Dsc to mint
     * @notice this function will depostir your callaeral and mint in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /**
     * @notice follows Checks Effects Interactions
     * @param tokenCollateralAddress The address of the token contract to deposit as collateral e.g. WETH or WBTC on Sepolia or Mainnet or Anvil (mocks)
     *
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     *
     * @param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function burns DSC and redeems collateral in one transaction
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health
    }

    // health factor must be over 1 after collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // 1. Check if the collateral value > DSC amount
    /**
     *
     * @param amountDscToMint Amount of DSC to mint.
     * @notice follows CEI
     * @notice they must have more collateral value than the minum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender); // line might not be needed??
    }
    // Liquidator (anyone) takes the backing and pays off the DSC

    /**
     *
     * @param collateral The ERC20 collateral address to liquidate
     * @param user The user who has broken the health factor. Their _healthFactor should be below the MIN_)HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized.
     * @notice A known bug would be if the protocol were 1000% or less collateralized, then we wouldn't be able to incentivise the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // check the health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // Burn their DSC "debt"
        // Take their collateral
        // E.g. a bad user : $140 ETH, 100 DSC. - debt ToCover = $100. $100 of DSC = &&& ETH?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        // Then give a 10% bonus in WETH
        // Implement a feature to liquidate in the event the protocol is insolvent
        // and sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        //////
        // Add code to prevent totalCollateralToRedeem from being greater than the user Collateral
        ////////////

        uint256 userCollateral = s_collateralDeposited[user][collateral];
        if (totalCollateralToRedeem > userCollateral) {
            totalCollateralToRedeem = userCollateral;

            // Adjust debtToCover based on the actual collateral redeemed
            // debtToCover = getUsdValue(collateral, userCollateral) * LIQUIDATION_PRECISION
            //     / (LIQUIDATION_PRECISION + LIQUIDATION_BONUS);

            // Burn all user DSC if all collateral is redeemed
            debtToCover = s_DSCMinted[user]; // Burn all DSC debt
        }
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /////////////////////////////////////
    //  Private and internal functions //
    /////////////////////////////////////

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        // check that the burn amount doesn’t exceed the minted amount
        if (amountDscToBurn > s_DSCMinted[onBehalfOf]) {
            revert DSCEngine__BurnAmountExceedsMinted();
        }
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1 then they can get liquidated
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collaterlAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // Examples of health factor
        // A user has $1000 of ETH and has minted $100 of DSC (100 DSC)
        // 1000 * 50 = 50000
        // 50000 / 100 = 500
        // 500 / 100 = 5

        // @dev Health factor is infinite when debt = 0
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        return (collaterlAdjustedForThreshold * PRECISION) / totalDscMinted;

        //return (collateralValueInUsd / totalDscMinted);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Check health factor - checks to see if the user has enough collateral
        // revert if health factor is bad
        // in above example health factor is 5 which is good.abi
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////
    //  Pulic and Exernal View functions //
    ///////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // ETH/USD and BTC/USD from Chainlink both return values in 8 decimal places (1e8)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //price of ETH(token)
        //Amount of USD in Wei divided by price
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
