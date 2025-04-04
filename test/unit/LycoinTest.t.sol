// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import { DeployLycoin } from "../../script/DeployLycoin.s.sol";
import { Lycoin } from "../../src/Lycoin.sol";
import { LycoinERC20 } from "../../src/LycoinERC20.sol";

import { Test } from "../../lib/forge-std/src/Test.sol";
import { Script, console } from "../../lib/forge-std/src/Script.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20Errors } from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";


contract LycoinTest is Test {
    Lycoin public lycoin;
    LycoinERC20 public lycoinERC20;
    HelperConfig public helperConfig;

    uint256 constant QUANTIDADE_INICIAL_WETH = 100 ether;
    uint256 constant QUANTIDADE_INICIAL_WBTC = 1 ether;

    address public wethToken;
    address public wbtcToken;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");


    modifier createWethAndApprove() {
        ERC20Mock(wethToken).mint(USER, QUANTIDADE_INICIAL_WETH);
        ERC20Mock(wethToken).mint(USER2, QUANTIDADE_INICIAL_WETH);

        vm.prank(USER);
        ERC20Mock(wethToken).approve(address(lycoin), QUANTIDADE_INICIAL_WETH);

        vm.prank(USER2);
        ERC20Mock(wethToken).approve(address(lycoin), QUANTIDADE_INICIAL_WETH);

        _;
    }


    modifier deposit() {
        vm.prank(USER);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);

        vm.prank(USER2);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);
        _;
    }


    modifier depositAndMintLycoin() {
        ERC20Mock(wethToken).mint(USER, QUANTIDADE_INICIAL_WETH);
        ERC20Mock(wethToken).mint(USER2, QUANTIDADE_INICIAL_WETH);


        vm.startBroadcast(USER);

        ERC20Mock(wethToken).approve(address(lycoin), QUANTIDADE_INICIAL_WETH);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);

        vm.stopBroadcast();


        vm.startBroadcast(USER2);

        ERC20Mock(wethToken).approve(address(lycoin), QUANTIDADE_INICIAL_WETH);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);

        vm.stopBroadcast();


        uint256 collateralUser = lycoin.getPriceCollateralInUSD(USER);
        vm.prank(USER);
        lycoin.mintLycoin(collateralUser / 2);


        collateralUser = lycoin.getPriceCollateralInUSD(USER2);
        vm.prank(USER2);
        lycoin.mintLycoin(collateralUser / 2);

        _;
    }


    modifier breakHealthFactor() {
        bytes32 acessarMapping = keccak256(abi.encode(USER, uint256(3)));
        bytes32 acessarMappingDoMapping = keccak256(abi.encode(wethToken, acessarMapping));

        bytes32 valorColateral = vm.load(address(lycoin), acessarMappingDoMapping);

        vm.store(address(lycoin), acessarMappingDoMapping, bytes32(uint256(valorColateral) - 10 ether));
        
        bytes32 valorColateralAlterado = vm.load(address(lycoin), acessarMappingDoMapping);

        _;
    }

		
	function setUp() external { 
        DeployLycoin deployer = new DeployLycoin();
        (lycoin, lycoinERC20, helperConfig) = deployer.run();

        (wbtcToken, wethToken,,,) = helperConfig.activeNetworkConfig();   
    }
		 

    /*------------------------------------------------                   ------------------------------------------------*/
    /*------------------------------------------------ depositCollateral ------------------------------------------------*/
    /*------------------------------------------------                   ------------------------------------------------*/
	function testSemTokensPermitidos() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, lycoin, 0, QUANTIDADE_INICIAL_WETH));

        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);
    }


    function testTokenInvalido() external {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Lycoin.TokenInvalid.selector));
        lycoin.depositCollateral(0x0000000000000000000000000000000000000001, QUANTIDADE_INICIAL_WETH);
    }


	function testParametrosValidos() external createWethAndApprove() {
        vm.prank(USER);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);

        uint256 collateralUser = lycoin.getCollateralUserUnique(USER, wethToken);

        assertEq(collateralUser, QUANTIDADE_INICIAL_WETH);
    }


    /*------------------------------------------------         ------------------------------------------------*/
    /*------------------------------------------------ Getters ------------------------------------------------*/
    /*------------------------------------------------         ------------------------------------------------*/
	function testCollateralInUSDFunctionality() external createWethAndApprove() {
        ERC20Mock(wbtcToken).mint(USER, QUANTIDADE_INICIAL_WBTC);
        vm.prank(USER);
        ERC20Mock(wbtcToken).approve(address(lycoin), QUANTIDADE_INICIAL_WBTC);


        vm.startBroadcast(USER);

        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);
        lycoin.depositCollateral(wbtcToken, QUANTIDADE_INICIAL_WBTC);

        vm.stopBroadcast();

        uint256 collateralUser = lycoin.getPriceCollateralInUSD(USER) * 1e8;
        uint256 collateralPriceWETH = uint256(lycoin.getLatestPriceToken(wethToken));
        uint256 collateralPriceWBTC = uint256(lycoin.getLatestPriceToken(wbtcToken));

        assertEq(collateralUser, (QUANTIDADE_INICIAL_WETH * collateralPriceWETH) + (QUANTIDADE_INICIAL_WBTC * collateralPriceWBTC));
    }


    /*------------------------------------------------               ------------------------------------------------*/
    /*------------------------------------------------ _healthFactor ------------------------------------------------*/
    /*------------------------------------------------               ------------------------------------------------*/
    function testHealthFactorFunctionality() external createWethAndApprove() deposit() {
        uint256 factor = lycoin.healthFactorCalculation(USER);
        uint256 collateralUser = lycoin.getPriceCollateralInUSD(USER);

        vm.prank(USER);
        lycoin.mintLycoin(collateralUser / 2);

        factor = lycoin.healthFactorCalculation(USER);

        assertEq(factor, uint256(1e18));
    }


    function testHealthFactorLowMinting() external createWethAndApprove() deposit() {
        uint256 collateralUser = lycoin.getPriceCollateralInUSD(USER);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Lycoin.HealthFactorLow.selector, 1e18 / 2));
        lycoin.mintLycoin(collateralUser);
    }


    /*------------------------------------------------            ------------------------------------------------*/
    /*------------------------------------------------ burnLycoin ------------------------------------------------*/
    /*------------------------------------------------            ------------------------------------------------*/
    function testBurnFunctionality() external depositAndMintLycoin() {
        uint256 tokensUserBefore = lycoin.getTokensUser(USER);

        vm.prank(USER);
        lycoin.burnLycoin(tokensUserBefore / 2);

        uint256 tokensUserAfter = lycoin.getTokensUser(USER);

        assertEq(tokensUserBefore / 2, tokensUserAfter);
    }


    function testBurnMoreTokensUserHold() external depositAndMintLycoin() {
        uint256 tokensUser = lycoin.getTokensUser(USER);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Lycoin.amountInvalidToBurn.selector, tokensUser * 2));
        lycoin.burnLycoin(tokensUser * 2);
    }


    /*------------------------------------------------                  ------------------------------------------------*/
    /*------------------------------------------------ reedemCollateral ------------------------------------------------*/
    /*------------------------------------------------                  ------------------------------------------------*/
    function testReedemFunctionality() external depositAndMintLycoin() {
        ERC20Mock(wethToken).mint(USER, QUANTIDADE_INICIAL_WETH);

        vm.prank(USER);
        ERC20Mock(wethToken).approve(address(lycoin), QUANTIDADE_INICIAL_WETH);

        vm.prank(USER);
        lycoin.depositCollateral(wethToken, QUANTIDADE_INICIAL_WETH);

        uint256 amountUser = lycoin.getCollateralUserUnique(USER, wethToken);

        vm.prank(USER);
        lycoin.reedemCollateral(wethToken, amountUser / 2);

        amountUser = lycoin.getCollateralUserUnique(USER, wethToken);
        uint256 amoutUserWrapped = ERC20Mock(wethToken).balanceOf(USER);

        assertEq(amountUser, QUANTIDADE_INICIAL_WETH);
        assertEq(amoutUserWrapped, QUANTIDADE_INICIAL_WETH);
    }


    function testReedemHealthFactorBroken() external depositAndMintLycoin() {
        uint256 amountUser = lycoin.getCollateralUserUnique(USER, wethToken);

        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Lycoin.HealthFactorLow.selector, 0));
        lycoin.reedemCollateral(wethToken, amountUser);
    }


    function testReedemNoCollateral() external {
        // Tenta resgatar colateral
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Lycoin.amountInvalidToBurn.selector, QUANTIDADE_INICIAL_WETH));
        lycoin.reedemCollateral(wethToken, QUANTIDADE_INICIAL_WETH);
    }


    /*------------------------------------------------                               ------------------------------------------------*/
    /*------------------------------------------------ reedemCollateralAndBurnLycoin ------------------------------------------------*/
    /*------------------------------------------------                               ------------------------------------------------*/
    function testReedemCollateralAndBurnLycoinFunctionality() external depositAndMintLycoin() {
        uint256 amountCollateral = lycoin.getCollateralUserUnique(USER, wethToken);
        uint256 amountTokensLycoin = lycoin.getTokensUser(USER);

        vm.prank(USER);

        lycoin.reedemCollateralAndBurnLycoin(wethToken, amountCollateral / 2, amountTokensLycoin);

        amountCollateral = lycoin.getCollateralUserUnique(USER, wethToken);
        amountTokensLycoin = lycoin.getTokensUser(USER);

        assertEq(amountCollateral, QUANTIDADE_INICIAL_WETH / 2);
        assertEq(amountTokensLycoin, 0);
    }


    /*------------------------------------------------           ------------------------------------------------*/
    /*------------------------------------------------ Liquidate ------------------------------------------------*/
    /*------------------------------------------------           ------------------------------------------------*/
    function testLiquidateFunctionality() external createWethAndApprove() depositAndMintLycoin() breakHealthFactor() {
        // Before Liquidation
        uint256 tokensDebtorBeforeLiquidation = lycoin.getTokensUser(USER);
        uint256 tokensLiquidatorBeforeLiquidation = lycoin.getTokensUser(USER2);

        uint256 collateralDebtorBeforeLiquidation = lycoin.getCollateralUserUnique(USER, wethToken);
        uint256 collateralLiquidatorBeforeLiquidation = lycoin.getCollateralUserUnique(USER2, wethToken);

        uint256 healthFactorDebtorBeforeLiquidation = lycoin.healthFactorCalculation(USER);
        console.log("Health factor before liquidation:", healthFactorDebtorBeforeLiquidation);
        
        vm.prank(USER2);
        lycoin.liquidate(wethToken, USER, tokensLiquidatorBeforeLiquidation / 2);


        // After Liquidation
        uint256 tokensDebtorAfterLiquidation = lycoin.getTokensUser(USER);
        uint256 tokensLiquidatorAfterLiquidation = lycoin.getTokensUser(USER2);

        uint256 collateralDebtorAfterLiquidation = lycoin.getCollateralUserUnique(USER, wethToken);
        uint256 collateralLiquidatorAfterLiquidation = lycoin.getCollateralUserUnique(USER2, wethToken);

        uint256 healthFactorDebtorAfterLiquidation = lycoin.healthFactorCalculation(USER);
        console.log("Health factor after liquidation:", healthFactorDebtorAfterLiquidation);

        uint256 totalCollateralRedeemed = lycoin.getLiquidatorBonusCalculation(wethToken, tokensLiquidatorBeforeLiquidation / 2);

        
        // Validations
        assertEq(tokensDebtorAfterLiquidation, tokensDebtorBeforeLiquidation / 2);
        assertEq(tokensLiquidatorAfterLiquidation, tokensLiquidatorBeforeLiquidation / 2);
        assertEq(collateralDebtorAfterLiquidation, collateralDebtorBeforeLiquidation - totalCollateralRedeemed);
        assertEq(collateralLiquidatorAfterLiquidation, collateralLiquidatorBeforeLiquidation + totalCollateralRedeemed);
    }


    function testLiquidateGoodDebtorHealthFactor() external createWethAndApprove() depositAndMintLycoin() {   
        vm.expectRevert(abi.encodeWithSelector(Lycoin.HealthFactorDebtorGood.selector, 1 ether));  
	    lycoin.liquidate(wethToken, USER, 1 ether);
    }
}