// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ReceiptToken} from "./ReceiptToken.sol";

import "./interface/IMigrator.sol";
import "./interface/ISatlayerPool.sol";


/// @title Satlayer Pool
/// @notice A staking pool for liquid restaking token holders which rewards stakers with points from multiple platforms
contract SatlayerPool is ISatlayerPool, Ownable, Pausable {
    using SafeERC20 for IERC20Metadata;
    
    // (tokenAddress => stakingAllowed)
    mapping(address => bool) public tokenAllowlist;

    mapping(address => address) public tokenMap;

    bool public capsEnabled = true;
    mapping(address => uint256) public caps;

    address public migrator;

    // Next eventId to emit
    uint256 private eventId;
      
    constructor(address[] memory _tokensAllowed, uint256[] memory _caps, string[] memory _names, string[] memory _symbols) Ownable(msg.sender) {
        if (_tokensAllowed.length != _caps.length || _tokensAllowed.length != _names.length || _tokensAllowed.length != _symbols.length) revert TokenAndCapLengthMismatch();

        uint256 length = _tokensAllowed.length;
        for(uint256 i; i < length;) {
            if (_tokensAllowed[i] == address(0)) revert TokenCannotBeZeroAddress();
            // will revert if there are duplicates in the _tokensAllowed array
            addToken(_tokensAllowed[i], _caps[i], _names[i], _symbols[i]);
            unchecked { ++i; }
        }
    }


    /*//////////////////////////////////////////////////////////////
                            Staker Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISatlayerPool
     */
    function depositFor(address _token, address _for, uint256 _amount) whenNotPaused external {
        if (_amount == 0) revert DepositAmountCannotBeZero();
        if (_for == address(0)) revert CannotDepositForZeroAddress();
        if (!tokenAllowlist[_token]) revert TokenNotAllowedForStaking();
        if (capsEnabled && caps[_token] < getTokenTotalStaked(_token) + _amount) revert CapReached();
        
        uint256 balanceBefore = IERC20Metadata(_token).balanceOf(address(this));
        IERC20Metadata(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 actualAmount = IERC20Metadata(_token).balanceOf(address(this)) - balanceBefore;

        emit Deposit(++eventId, _for, _token, actualAmount);

        ReceiptToken(tokenMap[_token]).mint(_for, actualAmount);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function withdraw(address _token, uint256 _amount) external {
        if (_amount == 0) revert WithdrawAmountCannotBeZero();
        if (getUserTokenBalance(_token, msg.sender) < _amount) revert InsufficientUserBalance();

        emit Withdraw(++eventId, msg.sender, _token, _amount);

        // reverts with InsufficientUserBalance if the user does not have enough receipt tokens to
        // burn _amount
        ReceiptToken(tokenMap[_token]).burn(msg.sender, _amount);
        IERC20Metadata(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function migrate(
        address[] calldata  _tokens, 
        string calldata destinationAddress 
    ) external whenNotPaused { 
        // checks
        if (migrator == address(0)) revert MigratorNotSet();

        uint256 length = _tokens.length;
        if (length == 0) revert TokenArrayCannotBeEmpty();

        uint256[] memory _amounts = new uint256[](length);
        for(uint256 i; i < length;) {
            _amounts[i] = getUserTokenBalance(_tokens[i], msg.sender);
            if (_amounts[i] == 0) revert UserDoesNotHaveStake(); // or duplicate token

            IERC20Metadata(_tokens[i]).approve(migrator, _amounts[i]);
            ReceiptToken(tokenMap[_tokens[i]]).burn(msg.sender, _amounts[i]);
            unchecked { ++i; }
        }
        
        emit Migrate(++eventId, msg.sender, destinationAddress, migrator, _tokens, _amounts);
        // migrator will transfer tokens out of staking contract and then migrate them over to SatLayer mainnet
        IMigrator(migrator).migrate(msg.sender, destinationAddress, _tokens, _amounts);
    }


    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISatlayerPool
     */
    function setCapsEnabled(bool _enabled) external onlyOwner {
        if (capsEnabled == _enabled) revert ParamsUnchanged();
        emit CapsEnabled(_enabled);
        capsEnabled = _enabled;
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function setMigrator(address _migrator) external onlyOwner {
        if (_migrator == address(0)) revert MigratorCannotBeZeroAddress();

        emit MigratorChanged(_migrator);
        migrator = _migrator;
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function addToken(address _token, uint256 _cap, string memory _name, string memory _symbol) public onlyOwner {
        if (tokenMap[_token] != address(0)) revert TokenAlreadyAdded();

        ReceiptToken receiptToken = new ReceiptToken(_name, _symbol, IERC20Metadata(_token).decimals());

        tokenMap[_token] = address(receiptToken);

        setTokenStakingParams(_token, true, _cap);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function setTokenStakingParams(address _token, bool _canStake, uint256 _cap) public onlyOwner {
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        
        if (tokenMap[_token] == address(0)) revert TokenNotAdded();

        bool stakingChanged = tokenAllowlist[_token] != _canStake;
        bool capChanged = caps[_token] != _cap;

        if (!stakingChanged && !capChanged) revert ParamsUnchanged();

        if (stakingChanged) {
            tokenAllowlist[_token] = _canStake;
            emit TokenStakabilityChanged(_token, _canStake);
        }

        if (capChanged) {
            caps[_token] = _cap;
            emit CapChanged(_token, _cap);
        }
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function unpause() external onlyOwner whenPaused{
        _unpause();
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function recoverERC20(address tokenAddress, address tokenReceiver, uint256 tokenAmount) external onlyOwner {
        if (tokenMap[tokenAddress] != address(0)) revert TokenAlreadyAdded();

        IERC20Metadata(tokenAddress).safeTransfer(tokenReceiver, tokenAmount);
    
    }

    function renounceOwnership() public override{
        revert CannotRenounceOwnership();
    }


    /*//////////////////////////////////////////////////////////////
                         View Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISatlayerPool
     */
    function getUserTokenBalance(address _token, address _user) public view returns (uint256) {
        if (tokenMap[_token] == address(0)) revert TokenNotAdded();

        return ReceiptToken(tokenMap[_token]).balanceOf(_user);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function getTokenTotalStaked(address _token) public view returns (uint256) {
        if (tokenMap[_token] == address(0)) revert TokenNotAdded();

        return ReceiptToken(tokenMap[_token]).totalSupply();
    }
}
