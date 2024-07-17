// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IReceiptToken is IERC20Metadata {

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;


}


