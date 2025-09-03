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
 * - dollar Pegger
 * Lagorithmically Stable
 * Iti is similare to DAI if DAI had no gevernance, no fees, and was only backed by WETH and WBTC.
 * @notice This contract is the core of the DSC SYstem. It handles all the logic for mining and redeeming DSC, as well as depoisiting & withdrawing collateral.
 * @notice This contract is VERY losely based on the MAkerDAO DSS (DAI) system.
 */
contract DSCEngine {

}
