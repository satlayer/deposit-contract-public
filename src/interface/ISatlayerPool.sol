// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;


/// @title Satlayer Pool Interface
/// @notice An interface containing externally accessible functions of the SatlayerPool contract
interface ISatlayerPool {

    /*//////////////////////////////////////////////////////////////
                            Errors
    //////////////////////////////////////////////////////////////*/


    error TokenCannotBeZeroAddress(); // Thrown when the specified token is the zero address
    error TokenAndCapLengthMismatch(); // Thrown when the length of the token array and the length of the cap array do not match
    error TokenAlreadyAdded(); //Thrown if the token has already been added (and receipt token created)
    error TokenNotAdded(); //Thrown if queried token has not been added to the Satlayer Pool
    error TokenAlreadyConfiguredWithState(); //Thrown if the token as already been enabled or disabled 
    error DepositAmountCannotBeZero(); // Thrown if staker attempts to call deposit() with zero amount
    error WithdrawAmountCannotBeZero(); //Thrown if staker attempts to call withdraw() with zero amount
    error TokenNotAllowedForStaking(); // Thrown if staker attempts to stake unsupported token (or token disabled for staking)
    error UserDoesNotHaveStake(); //Thrown if the staker is attempting to migrate with no stake
    error MigratorCannotBeZeroAddress(); //Thrown if the provided migrator is the zero address
    error MigratorNotSet(); //Thrown if the migrator contract is not set
    error CannotDepositForZeroAddress(); //Thrown if caller tries to deposit on behalf of the zero address
    error CannotRenounceOwnership(); //Thrown if the renounceOwnership() function is called
    error DuplicateToken(); //Thrown when there is a duplicate in the provided token address array
    error TokenArrayCannotBeEmpty(); //Thrown when the provided token address array is empty
    error CapReached(); //Thrown when the cap for a token has been reached
    error InsufficientUserBalance(); //Thrown when the user does not have enough token balance to withdraw desired amount

    /*//////////////////////////////////////////////////////////////
                            Staker Events
    //////////////////////////////////////////////////////////////*/

    ///@notice Emitted when a staker deposits/stakes a supported token into the Satlayer Pool
    ///@param eventId The unique event Id associated with the Deposit event
    ///@param depositor The address of the depositer/staker transfering funds to the Satlayer Pool
    ///@param token The address of the token deposited/staked into the pool
    ///@param amount The amount of token deposited/staked into the pool
    event Deposit(
        uint256 indexed eventId, 
        address indexed depositor, 
        address indexed token, 
        uint256 amount
    );

    ///@notice Emitted when a staker withdraws a previously staked tokens from the Satlayer Pool
    ///@param eventId The unique event Id associated with the Withdraw event
    ///@param withdrawer The address of the staker withdrawing funds from the Satlayer Pool
    ///@param token The address of the token being withdrawn from the pool
    ///@param amount The amount of tokens withdrawn the pool
    event Withdraw(uint256 indexed eventId, address indexed withdrawer, address indexed token, uint256 amount);

    ///@notice Emitted when a staker migrates their tokens from the SatlayerPool to Satlayer.
    ///@param eventId The unique event Id associated with the Migrate event
    ///@param user The address of the staker migrating funds to Satlayer
    ///@param destinationAddress The bech2 encoded address which the tokens will be credited to on Satlayer mainnet
    ///@param migrator The address of the migrator contract which initially receives the migrated tokens
    ///@param tokens The addresses of the tokens being being migrated from the SatlayerPool to Satlayer
    ///@param amounts The amounts of each token migrated to Satlayer
    event Migrate(
        uint256 indexed eventId, 
        address indexed user, 
        string destinationAddress, 
        address migrator, 
        address[] tokens, 
        uint256[] amounts
    );

    /*//////////////////////////////////////////////////////////////
                            Admin Events
    //////////////////////////////////////////////////////////////*/


    ///@notice Emitted when a token has been enabled or disabled for staking
    ///@param token The address of the token which has been enabled/disabled for staking
    ///@param enabled Is true if the token is being enabled and false if the token is being disabled
    event TokenStakabilityChanged(address token, bool enabled);

    ///@notice Emitted when a migrator has been added or removed from the blocklist
    ///@param migrator The address of the migrator which has been added or removed from the blocklist 
    ///@param blocked Is true if the migrator was added to the blocklist, and false if it was removed from the blocklist
    event BlocklistChanged(address migrator, bool blocked);

    ///@notice Emitted when the cap for a token is changed
    ///@param token address of token whose cap is modified
    ///@param cap new staking cap
    event CapChanged(address token, uint256 cap);

    ///@notice Emitted when staking caps are globally enabled or disabled
    ///@param enabled whether or not staking caps are enabled
    event CapsEnabled(bool enabled);

    ///@notice Emitted when the migrator contract address is changed
    ///@param migrator address of the migrator contract
    event MigratorChanged(address migrator);
    
    /*//////////////////////////////////////////////////////////////
                            Staker Functions
    //////////////////////////////////////////////////////////////*/

    ///@notice Stake a specified amount of a particular supported token into the Satlayer Pool
    ///@param _token The token to deposit/stake in the Satlayer Pool
    ///@param _for The user to deposit/stake on behalf of
    ///@param _amount The amount of token to deposit/stake into the Satlayer Pool
    function depositFor(address _token, address _for, uint256 _amount) external;

    ///@notice Withdraw a specified amount of a particular supported token previously staked into the Satlayer Pool
    ///@param _token The token to withdraw from the Satlayer Pool
    ///@param _amount The amount of token to withdraw from the Satlayer Pool
    function withdraw(address _token, uint256 _amount) external;

    ///@notice Migrate the staked tokens for the caller from the Satlayer Pool to Satlayer mainnet
    ///@dev called by the staker
    ///@param _tokens The tokens to migrate to Satlayer from the Satlayer Pool
    ///@param destinationAddress The bech32 encoded address on Satlayer mainnet which the user wishes to migrate their tokens to
    ///@dev can't be called if contract is paused
    function migrate(
        address[] calldata  _tokens, 
        string calldata destinationAddress 
    ) external;


    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    ///@notice Add a token to the Satlayer pool for staking and configure the receipt token parameters
    ///@param _token token to be added as staking collateral
    ///@param _cap max amount of token which can be staked
    ///@dev only callable by the owner
    function addToken(address _token, uint256 _cap, string memory _name, string memory _symbol) external;

    ///@notice Set the address of the migrator contract
    ///@param _migrator migrator contract address
    ///@dev only callable by the owner
    function setMigrator(address _migrator) external;

    ///@notice Enable or disable the specified token for staking
    ///@param _token The token to enable or disable for staking
    ///@param _canStake If true, then staking is to be enabled. If false, then staking will be disabled.
    ///@dev Only callable by the owner
    function setTokenStakingParams(address _token, bool _canStake, uint256 _cap) external;

    ///@notice Pause further staking through the deposit function.
    ///@dev Only callable by the owner. Withdrawals will still be possible when paused
    function pause() external;

    ///@notice Unpause staking allowing the deposit function to be used again
    ///@dev Only callable by the owner
    function unpause() external;

    ///@notice Set the max amount stakeable for a particular token
    ///@param _token token whose cap is being set
    ///@param _cap desired max stakeable amount
    ///@dev Only callable by Owner
    function setCap(address _token, uint256 _cap) external;

    ///@notice Set whether or not max staking caps are enabled in the app
    ///@param _enabled whether or not caps are enabled
    ///@dev Only callable by Owner
    function setCapsEnabled(bool _enabled) external;



    /*//////////////////////////////////////////////////////////////
                         View Functions
    //////////////////////////////////////////////////////////////*/

    ///@notice returns the user's staked balance of a particular token by reading the wallet balance of the corresponding receipt token
    ///@param _token deposit token address
    ///@param _user address of user to query
    ///@return _balance the user's balance of the receipt token corresponding to staked token
    function getUserTokenBalance(address _token, address _user) external view returns (uint256);

    ///@notice returns the total amount staked of a particular token in Satlayer pool
    ///@param _token deposit token address
    ///@return _total the total amount staked of the specified _token
    function getTokenTotalStaked(address _token) external view returns (uint256);
}