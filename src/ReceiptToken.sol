// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interface/IReceiptToken.sol";

contract ReceiptToken is IReceiptToken, Ownable, ERC20 {

    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 __decimals) Ownable(msg.sender) ERC20(name, symbol) {
        _decimals = __decimals;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        // reverts with ERC20InsufficientBalance in _update if user's balance is less than amount
        _burn(from, amount);
    }
}

