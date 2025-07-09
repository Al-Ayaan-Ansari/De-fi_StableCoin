// SPDX-License-Identifier: MIT

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
 * @title Decentralized Stable Coin Engine
 * @author AL AYAAN ANSARI (mentor: PetrickCollins)
 *
 * This is a system designed to maintain 1 token == 1 dollar.
 * This stable coin has properties:
 * 1. Exogenous Collateral
 * 2. Minted algorithmically
 * 3. Dollar pegged
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only pegged by wETH and wBTC.
 * This system handles all the logic of mining, redeeming, minting, maintaining 1 token == 1 dollar, transferring and withdrawing tokens and collateral.
 *
 * this is system is very loosely based on MarkerDao DSS(DAI) system
 */
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    /////////////
    ///errors////
    /////////////
    error DSCEngine_AmountisLessthanOrZero();
    error DSCEngine_TokenaddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_TranferOfCollateralFailed();
    error DSCEngine_HealthFactorBroken(uint256);
    error DSCEngine_MintingFailed();
    error DSCEngine_TranferFailed();
    error DSCEngine_HealthFactorIsGood();
    error DSCEngine_CollateralAndDscAreZero();

    //////////////////////
    ///state variables////
    //////////////////////
    uint256 constant PRICE_FEED_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;
    uint256 constant HEALTHFACTOR_THRESHOLD = 50; //double the collateral
    uint256 constant HEALTHFACTOR_PRECISION = 100;
    uint256 constant MIN_HEALTHFACTOR = 1e18;

    DecentralizedStableCoin private immutable i_dsc; //stable coin contract

    //mentains the who's,what and how much collateral someone deposited
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    //stores prices of wBTC and wETH
    mapping(address token => address priceFeed) private s_priceFeeds;
    //stores the dscminted and who have them
    mapping(address user => uint256 dscAmountMinted) private s_DSCMinted;
    //all Collateral tokens addresses
    address[] private s_collateralTokens;

    /////////////
    ///events///
    /////////////
    event CollateralDeposited(address indexed user, address indexed collateralAddress, uint256 amount);
    event mintedDsc(address indexed user, uint256 dscMintedAmount);
    event redmeededCollateral(address indexed from, address indexed to, address indexed collateralAddress, uint256 collateralAmount);
    event burnedDsc(address indexed from, address indexed whose, uint256 amount);

    /////////////
    //modifiers//
    /////////////
    modifier MoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine_AmountisLessthanOrZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_TokenNotAllowed();
        }
        _;
    }

    ////////////////
    ///functions////
    ////////////////

    //constructor
    constructor(address[2] memory tokenAddresses, address[2] memory priceFeedAddresses, address dsc) {
        // if (tokenAddresses.length != priceFeedAddresses.length) {
        //     revert DSCEngine_TokenaddressesAndPriceFeedAddressesMustBeSameLength();
        // }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dsc);
    }

    ////////////////////////
    ///external functions///
    ////////////////////////
    function depositeCollateralAndMintDsc(address collateralAdress, uint256 collateralAmount, uint256 amountDscMinted)
        external
    {
        depositeCollateral(collateralAdress, collateralAmount);
        mintDsc(amountDscMinted);
    }

    function redeemCollateralBurnDsc(address collateralAddress, uint256 collateralAmount, uint256 dscAmount) external {
        BurnDsc(dscAmount);
        redeemCollateral(collateralAddress, collateralAmount);
    }

    function liquidate(address userToLiquidate, uint256 debtToCover, address collateral)
        external
        MoreThanZero(debtToCover)
    {
        uint256 startingHealthFactorOf = _HealthFactor(userToLiquidate);
        if (startingHealthFactorOf > MIN_HEALTHFACTOR) {
            revert DSCEngine_HealthFactorIsGood();
        }

        uint256 collateralAmountToPay = convertToEth(debtToCover, collateral);
        uint256 bonusCollateral = (collateralAmountToPay * 10) / HEALTHFACTOR_PRECISION;
        uint256 totalCollateralToPay = collateralAmountToPay + bonusCollateral;

        _redeemCollateral(userToLiquidate, msg.sender, collateral, totalCollateralToPay);

        _burnDsc(debtToCover, userToLiquidate, msg.sender);

        _revertIfHealthFactorIsBroken(userToLiquidate);

        _revertIfHealthFactorIsBroken(msg.sender);
    }
    ////////////////////
    //public functions//
    ////////////////////

    function depositeCollateral(address collateralAddress, uint256 collateralAmount)
        public
        nonReentrant
        MoreThanZero(collateralAmount)
        isAllowedToken(collateralAddress)
    {
        s_collateralDeposited[msg.sender][collateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, collateralAddress, collateralAmount);

        bool success = IERC20(collateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine_TranferOfCollateralFailed();
        }
    }

    function redeemCollateral(address collateralAddress, uint256 collateralAmount)
        public
        MoreThanZero(collateralAmount)
        nonReentrant
        isAllowedToken(collateralAddress)
    {
        _redeemCollateral(msg.sender, msg.sender, collateralAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function BurnDsc(uint256 amount) public MoreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDscMinted) public MoreThanZero(amountDscMinted) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscMinted;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscMinted);
        if (!minted) {
            revert DSCEngine_MintingFailed();
        }
        emit mintedDsc(msg.sender, amountDscMinted);
    }


    /////////////////////////////////
    // internal & private function//
    ////////////////////////////////
    function _burnDsc(uint256 amountDscToBurn, address onBehalfof, address dscFrom) internal {
        s_DSCMinted[onBehalfof] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine_TranferFailed();
        }
        emit burnedDsc(onBehalfof,dscFrom,amountDscToBurn);
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralAmount)
    {
        totalDscMinted = s_DSCMinted[user];
        totalCollateralAmount = getAccountCollateralValue(user);
    }

    function _HealthFactor(address user) internal view returns (uint256) {
        //get total Minted Dsc
        // get total collateral values
        (uint256 totalDscMinted, uint256 totalCollateralAmount) = _getAccountInformation(user);
        uint256 colateralAdjustedForThreshold =
            (totalCollateralAmount * HEALTHFACTOR_THRESHOLD) / HEALTHFACTOR_PRECISION;
        if(totalDscMinted==0 && totalCollateralAmount!=0){
            return type(uint256).max;
        }
        else if(totalDscMinted==0 && totalCollateralAmount==0){
            revert DSCEngine_CollateralAndDscAreZero();
        }
        return (colateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // we need to keep check that always over collateral must be true
        // to do this first we need the info totalMinted Dsc and total collateral value
        // to calculate overcollaterization we need to find healthFactor(like Aave protocal)
        // this is the line we don't want to cross and user can be liquidated before this is crossed
        uint256 healthFactor = _HealthFactor(user);
        if (healthFactor < MIN_HEALTHFACTOR) {
            revert DSCEngine_HealthFactorBroken(healthFactor);
        }
    }

    function _redeemCollateral(address from, address to, address collateralAddress, uint256 collateralAmount)
        internal
    {
        s_collateralDeposited[from][collateralAddress] -= collateralAmount;
        emit redmeededCollateral(from, to, collateralAddress, collateralAmount);
        bool success = IERC20(collateralAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine_TranferOfCollateralFailed();
        }
    }
    //////////////////////////
    ///view & pure functions//
    //////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralInUsd) {
        //finding the total collateral value
        //we have to loop through all collateral a user have deposited
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            totalCollateralInUsd += convertToUsd(collateralAmount, token);
        }
        return totalCollateralInUsd;
    }

    function convertToUsd(uint256 amount, address token) public view returns (uint256) {
        //converting the collateral to usd value
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) * PRICE_FEED_PRECISION * amount) / PRECISION;
    }

    function convertToEth(uint256 usdAmountInWei, address token) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * PRICE_FEED_PRECISION));
    }

    function getAccountInformation(address user) external view returns(uint256 totalDscMinted,uint256 totalCollateralAmount){
        (totalDscMinted,totalCollateralAmount) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns(uint256) {
        return _HealthFactor(user);
    }


}
