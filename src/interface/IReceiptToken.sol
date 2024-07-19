// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Receipt Token Interface
/// @notice Interface for the externally accessible functions of the ReceiptToken contract
interface IReceiptToken is IERC20Metadata {

    ///@notice mint receipt token to specified address
    ///@param to address to mint receipt token to
    ///@param amount amount of receipt token to mint
    ///@dev only callable by the owner, which is the Satlayer pool
    function mint(address to, uint256 amount) external;

    ///@notice burn receipt token from specified address
    ///@param from address to burn receipt token from
    ///@param amount amount of receipt token to burn
    ///@dev only callable by the owner, which is the Satlayer pool. Does not require a token approval
    function burn(address from, uint256 amount) external;


}


