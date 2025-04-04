// SPDX-License-Identifier: None
pragma solidity ^0.8.13;

import { Lycoin } from "../../src/Lycoin.sol";
import { LycoinERC20 } from "../../src/LycoinERC20.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../../lib/forge-std/src/StdInvariant.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { Test } from "../../lib/forge-std/src/Test.sol";
import { DeployLycoin } from "../../script/DeployLycoin.s.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Handler } from "./Handler.t.sol";


contract MyContractTest is StdInvariant, Test {
    Lycoin public lycoin;
    LycoinERC20 public lycoinERC20;
    HelperConfig public helperConfig;

    uint256 constant QUANTIDADE_INICIAL_WETH = 100 ether;
    uint256 constant QUANTIDADE_INICIAL_WBTC = 1 ether;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    address public wethToken;
    address public wbtcToken;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");

    address[] listCollateral;


    function setUp() public {
        DeployLycoin deployer = new DeployLycoin();
        (lycoin, lycoinERC20, helperConfig) = deployer.run();

        (wbtcToken, wethToken,,,) = helperConfig.activeNetworkConfig();

        listCollateral.push(wethToken);
        listCollateral.push(wbtcToken);

        Handler handler = new Handler(lycoin, lycoinERC20, listCollateral); 
        targetContract(address(handler));
    }


    // The balance in tokens cannot be greater than the balance in collateral
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = lycoinERC20.totalSupply();

        uint256 totalWethDeposited = IERC20(wethToken).balanceOf(address(lycoin));
        uint256 totalWbtcDeposited = IERC20(wbtcToken).balanceOf(address(lycoin));

        if (totalSupply > 0) {
            assert(totalWethDeposited + totalWbtcDeposited >= totalSupply);
        }
    }
}