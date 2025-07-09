// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test,console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";


contract DSCEngineTest is Test{

    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address PLAYER = makeAddr("PLAYER");
    uint256 AMOUNT = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc,dscEngine,config)= deployer.run();
        (wethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(PLAYER,AMOUNT);
    }

    /////////////////
    ///modifiers/////
    /////////////////
    modifier depositedCollateral() {
        vm.startPrank(PLAYER);
        ERC20Mock(weth).approveInternal(PLAYER,address(dscEngine),AMOUNT);
        dscEngine.depositeCollateral(weth,AMOUNT);
        _;

    }

    /////////////////////
    //constructor tests//
    ////////////////////


    ////////////////
    //price tests///
    ////////////////
    function testConvertToUsd() public view {
        uint256 expectedAmount = 3000e18;
        uint256 actualAmount = dscEngine.convertToUsd(3e18,weth);

        assertEq(expectedAmount, actualAmount);

    }

    function testConvertTokenfromUsd() public view {
        uint256 usdAmount = 2000 ether;
        // 1000$/ETH 1000$ = 0.5
        uint256 expectedAmount = 2 ether;
        uint256 actualAmount = dscEngine.convertToEth(usdAmount,weth);
        assert(expectedAmount == actualAmount);

    }


    ////////////////////////////////////////////
    //Depositing collateral  and minting tests//
    ////////////////////////////////////////////
    function testCollateralAddedSuccesfully() public {
        vm.startPrank(PLAYER);
        ERC20Mock(weth).approveInternal(PLAYER,address(dscEngine),5);
        dscEngine.depositeCollateral(weth,1);
        vm.stopPrank();
        
    }

    function testIfCollateralisZeroRevert() public {
        vm.startPrank(PLAYER);
        ERC20Mock(weth).approveInternal(PLAYER,address(dscEngine),5);
        vm.expectRevert(DSCEngine.DSCEngine_AmountisLessthanOrZero.selector);
        dscEngine.depositeCollateral(weth,0);
        
        vm.stopPrank();
    }
    function testIfCollateralIsNotApprovedToken() public {
        ERC20Mock wSOLMock = new ERC20Mock("SOL", "Solana", PLAYER, 1000e8);
        vm.startPrank(PLAYER);
        ERC20Mock(weth).approveInternal(PLAYER,address(dscEngine),5);
        vm.expectRevert(DSCEngine.DSCEngine_TokenNotAllowed.selector);
        dscEngine.depositeCollateral(address(wSOLMock),2);
        
        vm.stopPrank();
    }

    function testCollateralDepositedAndMintedDsc() public depositedCollateral{
        uint256 mintedDscAmount = 5 ether;
        uint256 expectedCollateralinUsd = 10000 ether;
        vm.startPrank(PLAYER);
        dscEngine.mintDsc(mintedDscAmount);
        vm.stopPrank();
        (uint256 actualDscMinted,uint256 totalCollateral) = dscEngine.getAccountInformation(PLAYER);
        console.log(actualDscMinted,mintedDscAmount,totalCollateral);
        assertEq(actualDscMinted,mintedDscAmount);
        assertEq(totalCollateral,expectedCollateralinUsd);
    }
    
    ///////////////////////////
    ///////redeem Collateral///
    ///////////////////////////

    function testRedeemCollateralFailsIfHealthFactorGotBroken() public depositedCollateral{
        uint256 redeemAmount = 10 ether;
        vm.startPrank(PLAYER);
        vm.expectRevert(DSCEngine.DSCEngine_CollateralAndDscAreZero.selector);
        dscEngine.redeemCollateral(weth,redeemAmount);

    }

    function testHealthFactorBrokenIfUnderCollateraization() public depositedCollateral {
        uint256 mintDsc = 5001 ether;
        // uint256 expectedHealthFactor = 999800039992001599; // 0.9998 less than 1 
        vm.startPrank(PLAYER);
        vm.expectRevert();  //abi.encodeWithSelector(DSCEngine.DSCEngine_HealthFactorBroken.selector,expectedHealthFactor)
        dscEngine.mintDsc(mintDsc);

    }

    function testBurnDscFailsifMintedAmountgetLessThanZero() public  depositedCollateral{
        uint256 dscToBurn = 1 ether;
        vm.startPrank(PLAYER);
        vm.expectRevert();
        dscEngine.BurnDsc(dscToBurn);
    }

    function testBurnDscProperly() public depositedCollateral {
        uint256 dscMinted = 100 ether;
        uint256 dscBurn = 10 ether;
        vm.startPrank(PLAYER);
        dscEngine.mintDsc(dscMinted);
        dsc.approve(address(dscEngine), dscBurn);
        dscEngine.BurnDsc(dscBurn);
        uint256 expectedDscAfterBurning = 90 ether;
        (uint256 actualDsc,) = dscEngine.getAccountInformation(PLAYER);
        assertEq(expectedDscAfterBurning,actualDsc);

    }

    ///////////////////////
    ///liquidatation test//
    ///////////////////////


}