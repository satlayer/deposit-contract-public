// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;


/// @title Migrator Interface
/// @notice Interface for the Migrator contract called by the Satlayer Pool's migrate() function
interface IMigrator {
    
    ///@notice Function called by the Satlayer Pool to facilitate migration of staked tokens from the Satlayer Pool to Satlayer Migrator Contract
    ///@param _user The address of the user whose staked funds are being migrated to Satlayer
    ///@param _tokens The tokens being migrated to Satlayer migrator contract from the Satlayer staking pool 
    ///@param _destination The address which will be credited the tokens on Satlayer
    ///@param _amounts The amounts of each token to be migrated to Satlayer for the _user
    function migrate(
        address _user,
        address[] calldata _tokens,
        address _destination, 
        uint256[] calldata _amounts
    ) external;
}