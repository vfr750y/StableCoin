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

pragma solidity ^0.8.19;

/**
 * * @title DSCEngine
 * * @author Ajay Curry
 * *
 * * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
 * * This stablecoin has the properties
 * * - Exogenous Collateral
 *
 * - dollar Pegged
 * Algorithmically Stable
 * It is similar to DAI if DAI had no gevernance, no fees, and was only backed by WETH and WBTC.
 * DSC system should always be "overcollateralized"
 * @notice This contract is the core of the DSC SYstem. It handles all the logic for mining and redeeming DSC, as well as depoisiting & withdrawing collateral.
 * @notice This contract is VERY losely based on the MAkerDAO DSS (DAI) system.
 */
contract DSCEngine {

    /////////////////////////
    //  Errors             //
    /////////////////////////
error DSCEngine__NeedsMoreThanZero();

    ////////////////////////////
    //  Modifiers             //
    ////////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0 ){
            revert DSCEngine__NeedsMoreThanZero();}
        }
    }
    function depositCollateralAndMintDsc() external {}


/**
 * 
 * @param tokenCollateralAddress The address fo the token to deposit as collateral
 * 
 * @param amountCollateral THe amount of collateral to deposit
 */


    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral){}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function healthFactor() external view {}
}
