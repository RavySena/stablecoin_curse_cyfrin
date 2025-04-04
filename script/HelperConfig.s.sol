// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "../lib/forge-std/src/Script.sol";
import { MockV3Aggregator } from "../lib/chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import { ERC20Mock } from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";


contract HelperConfig is Script {
    int256 constant INITIAL_ANSWER_ETH = 2000e8;
    int256 constant INITIAL_ANSWER_BTC = 4000e8;
    uint8 constant DECIMALS = 8;

    address constant TOKEN_BTC_USD_SEPOLIA = 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC;
    address constant TOKEN_ETH_USD_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant PRICE_FEED_BTC_USD_SEPOLIA = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    address constant PRICE_FEED_ETH_USD_SEPOLIA = 0x694AA1769357215DE4FAC081bf1f309aDC325306;


    struct NetworkConfig {
        address btcUsdToken;
        address ethUsdToken;
        address btcUsdPriceFeed;
        address ethUsdPriceFeed;
        address secret_key;
    }

    NetworkConfig public activeNetworkConfig;
	
    
	// Verifica em qual rede esta sendo executado e definine os valores da struct activeNetworkConfig com base nisso
	constructor() {
        if (block.chainid == 31337) {
            activeNetworkConfig = getLocalConfig();
        } else if (block.chainid == 11155111) { // Sepolia
            activeNetworkConfig = getSepoliaConfig();
        }
    }
    

    function getLocalConfig() internal returns (NetworkConfig memory) {
        vm.startBroadcast();
    
        MockV3Aggregator priceFeedBTC = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER_BTC);
        MockV3Aggregator priceFeedETH = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER_ETH);

        ERC20Mock wbtcToken = new ERC20Mock();
        ERC20Mock wethToken = new ERC20Mock();

        vm.stopBroadcast();
        
        return NetworkConfig(
            address(wbtcToken),
            address(wethToken),
            address(priceFeedBTC),
            address(priceFeedETH),
            msg.sender
        );
    }


    function getSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig(
            TOKEN_BTC_USD_SEPOLIA,
            TOKEN_ETH_USD_SEPOLIA,
            PRICE_FEED_BTC_USD_SEPOLIA,
            PRICE_FEED_ETH_USD_SEPOLIA,
            address(0) // "YOUR KEY"
        );
    }
		
}