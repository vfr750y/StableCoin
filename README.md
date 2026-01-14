# Decentralized Stablecoin (DSC)

A robust, decentralized, and over-collateralized stablecoin system pegged to the USD. This project implements a "mint-and-burn" mechanism where users can deposit exogenous assets (like wETH or wBTC) as collateral to mint a stable currency ($1.00 peg).

## 🚀 Overview

The system is designed to be **minimally governed**, **fully transparent**, and **mathematically stable**. It utilizes Chainlink Price Feeds to ensure that the value of the collateral always exceeds the value of the minted stablecoins, maintaining a healthy "Health Factor" for the protocol.

### Key Features

* **Exogenous Collateral:** Supports highly liquid assets (wETH, wBTC).
* **Over-collateralization:** Users must maintain a specific collateral-to-debt ratio.
* **Liquidation Engine:** Incentivized liquidators ensure the system remains solvent by paying off under-collateralized positions in exchange for a bonus.
* **Oracle Integration:** Real-time price tracking via Chainlink.

---

## 🏗 Architecture

The project is split into two primary smart contracts:

1. **DecentralizedStableCoin.sol**: An ERC20 token contract that represents the stablecoin itself. It is "Owned" by the Engine, meaning only the Engine can mint or burn tokens.
2. **DSCEngine.sol**: The "brain" of the protocol. It handles collateral deposits, stablecoin minting, redemptions, and the liquidation logic.

---

## 🛠 Getting Started

### Prerequisites

* [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.
* Basic knowledge of Solidity and Ethereum smart contracts.

### Installation

1. Clone the repository:
```bash
git clone https://github.com/vfr750y/StableCoin.git
cd StableCoin

```


2. Install dependencies:
```bash
forge install

```



### Testing

This project uses Foundry for rigorous testing, including unit tests and stateful fuzz (invariant) testing.

```bash
forge test

```

---

## 📖 Usage Guide

### 1. Deposit Collateral & Mint

Users must first approve the `DSCEngine` to spend their collateral (wETH/wBTC) and then call:

```solidity
function depositCollateralAndMintDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToMint
) external;

```

### 2. Monitoring Health Factor

The protocol calculates your health factor based on:



If this value drops below **1**, your position is eligible for liquidation.

### 3. Liquidation

If a user is under-collateralized, any other user can liquidate them to earn a 10% bonus:

```solidity
function liquidate(
    address collateral,
    address user,
    uint256 debtToCover
) external;

```

---

## 🛡 Security

* **Reentrancy Guards:** All state-changing functions are protected against reentrancy.
* **Internal Accounting:** Strict checks ensure that collateral is never "lost" or miscalculated during transfers.
* **Oracle Safety:** Uses Chainlink's decentralized network to prevent price manipulation.

---

## 📄 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

---
