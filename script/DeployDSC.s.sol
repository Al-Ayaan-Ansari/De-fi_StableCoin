// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script,console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script{

    function run() public returns (DecentralizedStableCoin, DSCEngine, HelperConfig){
        return deployDSC();
    }

    function deployDSC() public returns (DecentralizedStableCoin, DSCEngine,HelperConfig){
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed,address wbtcUsdPriceFeed,address weth,address wbtc,uint256 deployerKey) = config.activeNetworkConfig();
        address[2] memory tokenAddresses = [weth,wbtc];
        address[2] memory priceFeedAddresses = [wethUsdPriceFeed,wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DecentralizedStableCoin dsc = new DecentralizedStableCoin(vm.addr(deployerKey));
        DSCEngine dscEngine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(dsc));
        // console.log(msg.sender);            //some debugging console.log `
        // console.log(dsc.owner());
        dsc.transferOwnership(address(dscEngine));
        // console.log(dsc.owner());
        vm.stopBroadcast();
        return (dsc,dscEngine,config);
    }
}