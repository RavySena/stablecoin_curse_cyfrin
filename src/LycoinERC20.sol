// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import { ERC20Burnable, ERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";


contract LycoinERC20 is ERC20Burnable, Ownable {

    constructor (address owner) ERC20("Lycoin", "LYC") Ownable(owner) {
    }


    function mint(address enderecoDonoTokens, uint256 quantidade) external onlyOwner {
        super._mint(enderecoDonoTokens, quantidade);
    }


    function burn(address enderecoDonoTokens, uint256 quantidade) external onlyOwner  {
        super._burn(enderecoDonoTokens, quantidade);
    }


}


