// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import { LycoinERC20, ERC20 } from "./LycoinERC20.sol";
import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { AggregatorV3Interface } from "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


/**
 * @title This contract is an exogenous stablecoin, pegged to the dollar.
 * @author Ravy Sena - Lykos
 * @notice This contract was created only to practice what was learned in the Cyfrin course.
 */
contract Lycoin is ReentrancyGuard {
    /*------------------------------------------------ INSTANCES ------------------------------------------------*/
    AggregatorV3Interface internal priceFeed;
    LycoinERC20 lycoinERC20;


    /*------------------------------------------------ CONSTANTS ------------------------------------------------*/
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_BONUS = 10;


    /*------------------------------------------------ TYPE DECLARATIONS ------------------------------------------------*/
    mapping(address user => mapping(address token => uint256 amount)) private amountUsers;
    mapping(address token => address priceFeed) private priceFeedTokens;
    address[] private tokens;


    /*------------------------------------------------ ERRORS ------------------------------------------------*/
    error DifferentSizeListsInTheConstructor(uint256, uint256);
    error NeedsAmountGreaterThanZero(uint256);
    error HealthFactorLow(uint256);
    error TokenInvalid();
    error AddressInvalid(address);
    error amountInvalidToBurn(uint256);
    error HealthFactorDebtorGood(uint256);
    error HealthFactorNotImproved(uint256);


    /*------------------------------------------------ EVENTS ------------------------------------------------*/
    event TokenListADD(address);
    event TokenMinting(address indexed user, uint256 amount, uint256 amountUser);
    event TokenBurning(address indexed user, uint256 amount, uint256 amountUser);
    event CollateralADD(address indexed user, address collateral, uint256 amount, uint256 amountUser);
    event RedeemCollateral(address indexed from, address indexed to, address collateral, uint256 amount, uint256 amountUser);
    

    /*------------------------------------------------ MODIFIERS ------------------------------------------------*/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert NeedsAmountGreaterThanZero(amount);
        }
        _;
    }


    modifier tokenValid(address collateralToken) {
        if (priceFeedTokens[collateralToken] == address(0)) {
            revert TokenInvalid();
        }
        _;
    }


    modifier addressValid (address user) {
        if (user == address(0)) {
            revert AddressInvalid(user);
        }
        _;
    }

    
    /*------------------------------------------------           ------------------------------------------------*/
    /*------------------------------------------------ FUNCTIONS ------------------------------------------------*/
    /*------------------------------------------------           ------------------------------------------------*/

    constructor (address _lycoinERC20Address, address[] memory _tokens, address[] memory _priceFeedTokens) {
        lycoinERC20 = LycoinERC20(_lycoinERC20Address);
        
        if (_tokens.length != _priceFeedTokens.length) {
            revert DifferentSizeListsInTheConstructor(_tokens.length, _priceFeedTokens.length);
        }

        for (uint256 i=0; i < _tokens.length; i++) {
            tokens.push(_tokens[i]);
            priceFeedTokens[_tokens[i]] = _priceFeedTokens[i];

            emit TokenListADD(_tokens[i]);
        }
    }


    /*------------------------------------------------                   ------------------------------------------------*/
    /*------------------------------------------------ FUNCTIONS PUBLICS ------------------------------------------------*/
    /*------------------------------------------------                   ------------------------------------------------*/
    /**
     * @notice Deposits and mints tokens. Calls `depositCollateral` function and then `mintLycoin`
     * @param collateralToken The token that will be used as collateral
     * @param amountCollateral The amount of collateral tokens
     * @param amountMint The amount of Lycoin tokens that will be created. Must be at most half the dollar value of the collateral.
     */
    function depositAndMint(address collateralToken, uint256 amountCollateral, uint256 amountMint) external tokenValid(collateralToken) moreThanZero(amountCollateral) moreThanZero(amountMint) {
        depositCollateral(collateralToken, amountCollateral);
        mintLycoin(amountMint);
    }


    function depositCollateral(address collateralToken, uint256 amount) public moreThanZero(amount) tokenValid(collateralToken) {
        amountUsers[msg.sender][collateralToken] += amount;

        ERC20(collateralToken).transferFrom(msg.sender, address(this), amount);

        emit CollateralADD(msg.sender, collateralToken, amount, amountUsers[msg.sender][collateralToken]);
    }


    function mintLycoin(uint256 amount) public moreThanZero(amount) {
        lycoinERC20.mint(msg.sender, amount);

        uint256 amountUser = lycoinERC20.balanceOf(msg.sender);

        uint256 healthFactor = healthFactorCalculation(msg.sender);
        _revertHealthFactorLow(healthFactor);

        emit TokenMinting(msg.sender, amount, amountUser);
    }

    /**
     * @notice Burn the tokens and then redeem the collateral. Call the `burnLycoin` function and then `reedemCollateral`
     * @param collateralToken The token that was used as collateral
     * @param amountCollateral The amount of collateral tokens to be redeemed
     * @param amountLycoin The amount of Lycoin tokens that will be burned.
     */
    function reedemCollateralAndBurnLycoin(address collateralToken, uint256 amountCollateral, uint256 amountLycoin) public tokenValid(collateralToken) moreThanZero(amountCollateral) moreThanZero(amountLycoin) {
        burnLycoin(amountLycoin);
        reedemCollateral(collateralToken, amountCollateral);
    }


    function burnLycoin(uint256 amount) public moreThanZero(amount) nonReentrant() {
        uint256 tokensUser = lycoinERC20.balanceOf(msg.sender);

        if (tokensUser < amount) {
            revert amountInvalidToBurn(amount);
        }
        
        _burnDsc(msg.sender, amount);
    }


    function reedemCollateral(address collateralToken, uint256 amount) public tokenValid(collateralToken) moreThanZero(amount) nonReentrant() {
        uint256 collateralUser = getCollateralUserUnique(msg.sender, collateralToken);

        if (collateralUser < amount) {
            revert amountInvalidToBurn(amount);
        }

        _redeemCollateral(collateralToken, amount, msg.sender, msg.sender);
        
        uint256 healthFactor = healthFactorCalculation(msg.sender);
        _revertHealthFactorLow(healthFactor);
    }


    /**
     * @notice Liquidation function, it checks if the debtor has a low health factor, then it burns the debt and gives the collateral with a bonus to the liquidator
     * @param collateralToken The token that the liquidator will receive
     * @param user The user who has a low factor
     * @param debtToCover The amount of Lycoin tokens that will be burned to pay off the debt.
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover) external addressValid(user) tokenValid(collateralToken) moreThanZero(debtToCover) nonReentrant {
        uint256 healthFactorDebtor = healthFactorCalculation(user);

        if (healthFactorDebtor >= MIN_HEALTH_FACTOR) {
            revert HealthFactorDebtorGood(healthFactorDebtor);
        }

        uint256 _totalCollateralRedeemed = getLiquidatorBonusCalculation(collateralToken, debtToCover);

        _redeemCollateral(collateralToken, _totalCollateralRedeemed, user, msg.sender);
        amountUsers[msg.sender][collateralToken] += _totalCollateralRedeemed;

        _burnDsc(msg.sender, debtToCover);
        _burnDsc(user, debtToCover);

        uint256 endingHealthFactorDebtor = healthFactorCalculation(user);

        if(endingHealthFactorDebtor <= healthFactorDebtor){
            revert HealthFactorNotImproved(endingHealthFactorDebtor);
        }
    }


    /*------------------------------------------------                                 ------------------------------------------------*/
    /*------------------------------------------------ FUNCTIONS INTERNAL AND PRIVATES ------------------------------------------------*/
    /*------------------------------------------------                                 ------------------------------------------------*/
    function _getAccountInformation(address _user) internal view returns (uint256 tokensUser, uint256 collateralUserInUSD) {
        tokensUser = getTokensUser(_user);
        collateralUserInUSD = getPriceCollateralInUSD(_user);
    }



    function _revertHealthFactorLow(uint256 _health) internal pure {
        if (_health < MIN_HEALTH_FACTOR) {
            revert HealthFactorLow(_health);
        }
    }


    function _redeemCollateral(address collateralToken, uint256 amountCollateral, address from, address to) private {
        uint256 collateralUser = getCollateralUserUnique(msg.sender, collateralToken);
        amountUsers[from][collateralToken] -= amountCollateral;

        emit RedeemCollateral(from, to, collateralToken, amountCollateral, collateralUser);

        ERC20(collateralToken).transfer(to, amountCollateral);
    }


    function _burnDsc(address from, uint256 amount) private {
        lycoinERC20.burn(from, amount);

        uint256 tokensUser = lycoinERC20.balanceOf(from);

        emit TokenBurning(from, amount, tokensUser);
    }



    /*------------------------------------------------                   ------------------------------------------------*/
    /*------------------------------------------------ FUNCTIONS GETTERS ------------------------------------------------*/
    /*------------------------------------------------                   ------------------------------------------------*/
    function getLatestPriceToken(address token) public tokenValid(token) view returns (int256 price) {
        (,price,,,) = AggregatorV3Interface(priceFeedTokens[token]).latestRoundData();
    }


    function getPriceCollateralInUSD(address user) public addressValid(user) view returns (uint256 valorEtherEnviado) {
        for (uint256 i = 0; i < tokens.length; i++) {
            (,int256 price,,,) = AggregatorV3Interface(priceFeedTokens[tokens[i]]).latestRoundData();

            uint256 collateralUser = getCollateralUserUnique(user, tokens[i]);

            uint256 elevaCasasDecimaisUSD = uint256(uint256(price) * ADDITIONAL_FEED_PRECISION);
            
            valorEtherEnviado += (collateralUser * elevaCasasDecimaisUSD) / PRECISION;
        }
    }


    function getCollateralUserUnique(address user, address token) public addressValid(user) tokenValid(token) view returns (uint256 collateralUser) {
        collateralUser = amountUsers[user][token];
    }


    function getTokensUser(address user) public addressValid(user) view returns (uint256) {
        return lycoinERC20.balanceOf(user);
    }


    function getLiquidatorBonusCalculation(address collateralToken, uint256 debtToCover) public view returns (uint256 totalCollateralRedeemed) {
        uint256 tokenAmountFromDebtCovered = (debtToCover * PRECISION) / (uint256(getLatestPriceToken(collateralToken)) * ADDITIONAL_FEED_PRECISION);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;
    }


    function healthFactorCalculation(address user) public addressValid(user) view returns(uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        
        if (totalDscMinted > 0) {
            uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
            return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        }

        return 5e18;
    }
}
