// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Lycoin} from "../../src/Lycoin.sol";
import {LycoinERC20} from "../../src/LycoinERC20.sol";
import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";


contract Handler is Test {
    Lycoin public lycoin;
    LycoinERC20 public lycoinERC20;
    address[] collateralTokens;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(Lycoin _lycoin, LycoinERC20 _lycoinERC20, address[] memory _collateralTokens) {
        lycoin = _lycoin;
        lycoinERC20 = _lycoinERC20;

        collateralTokens.push(_collateralTokens[0]);
        collateralTokens.push(_collateralTokens[1]);
    }


    function depositAndMint(uint256 _collateralToken, uint256 amountCollateral) external {
        address collateralToken = getAddressCollateral(_collateralToken);

        amountCollateral = bound(amountCollateral, 10, MAX_DEPOSIT_SIZE);
        uint256 amountMint = amountCollateral / 2;


        vm.startBroadcast(msg.sender);

        ERC20Mock(collateralToken).mint(msg.sender, amountCollateral);
        ERC20Mock(collateralToken).approve(address(lycoin), amountCollateral);

        lycoin.depositAndMint(collateralToken, amountCollateral, amountMint);

        vm.stopBroadcast();
    }


    function getAddressCollateral(uint256 _collateralToken) internal view returns (address) {
        if (_collateralToken % 2 == 0) {
            return collateralTokens[0];
        }

        return collateralTokens[1];
    }



}