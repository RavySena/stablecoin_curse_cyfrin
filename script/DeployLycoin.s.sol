// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;


import { Script } from "../lib/forge-std/src/Script.sol";
import { Lycoin } from "../src/Lycoin.sol";
import { LycoinERC20 } from "../src/LycoinERC20.sol";
import { HelperConfig } from "./HelperConfig.s.sol";


contract DeployLycoin is Script {
    Lycoin lycoin;
    LycoinERC20 lycoinERC20;
    HelperConfig helperConfig;


    address private btcUsdToken;
    address private ethUsdToken;
    address private btcUsdPriceFeed;
    address private ethUsdPriceFeed;
    address private deployerKey;


    function run() external returns (Lycoin, LycoinERC20, HelperConfig) {
        helperConfig = new HelperConfig();
        (btcUsdToken, ethUsdToken, btcUsdPriceFeed, ethUsdPriceFeed, deployerKey) = helperConfig.activeNetworkConfig();

        address[] memory tokens = new address[](2);
        address[] memory priceFeeds = new address[](2);

        tokens[0] = btcUsdToken;
        tokens[1] = ethUsdToken;

        priceFeeds[0] = btcUsdPriceFeed;
        priceFeeds[1] = ethUsdPriceFeed;



        vm.startBroadcast(deployerKey);

        lycoinERC20 = new LycoinERC20(address(this));
        lycoin = new Lycoin(address(lycoinERC20), tokens, priceFeeds);

        lycoinERC20.transferOwnership(address(lycoin));
        
        vm.stopBroadcast();
        
        return (lycoin, lycoinERC20, helperConfig);
    }
}