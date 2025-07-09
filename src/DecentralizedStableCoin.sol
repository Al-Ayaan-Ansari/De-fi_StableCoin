// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

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
/**
 * @author : AL AYAAN ANSARI
 * @title : DecentralizedStableCoin
 *
 * collateral : Eth and BTC  (wBTC, wETH)
 * minting: algorithmic
 * relative stability : pegged to us dollar (maybe be to Indian Rupees in the future)
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
 */
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    ///////////////
    ////errors/////
    //////////////
    error DecentralizedStableCoin_balanceIsLessThanBurningAmount();
    error DecentralizedStableCoin_CannotBurnZeroCoins();
    error DecentralizedStableCoin_CannotMintToAddressZero();
    error DecentralizedStableCoin_CannotMintLessThanOrEqualToZeroAmount();

    
    ///constructor//
    constructor(address DSCEngine) ERC20("DecentralizedStableCoin", "DSC") Ownable(DSCEngine) {}

    //burn function 
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin_CannotBurnZeroCoins();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin_balanceIsLessThanBurningAmount();
        }
        super.burn(_amount);
    }

    //mint function
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin_CannotMintToAddressZero();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin_CannotMintLessThanOrEqualToZeroAmount();
        }
        _mint(_to, _amount);
        return true;
    }
}
