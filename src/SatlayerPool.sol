// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {ReceiptToken} from "./ReceiptToken.sol";

import "./interface/IMigrator.sol";
import "./interface/ISatlayerPool.sol";


/// @title Satlayer Pool
/// @notice A staking pool for liquid restaking token holders which rewards stakers with points from multiple platforms
contract SatlayerPool is ISatlayerPool, Ownable, Pausable, EIP712, Nonces {
    using SafeERC20 for IERC20Metadata;

    bytes32 private constant MIGRATE_TYPEHASH =
        keccak256("Migrate(address user,address migratorContract,address destination,address[] tokens,uint256 signatureExpiry,uint256 nonce)");
    
    // (tokenAddress => isAllowedForStaking)
    mapping(address => bool) public tokenAllowlist;

    // (tokenAddress => stakerAddress => stakedAmount)
    mapping(address => mapping(address => uint256)) public balance;

    // (migratorContract => isBlocklisted)
    mapping(address => bool) public migratorBlocklist;

    mapping(address => uint256) public totalAmounts;

    mapping(address => address) public tokenMap;
    mapping(address => address) public reverseTokenMap;

    bool public capsEnabled = true;
    mapping(address => uint256) public caps;

    bool public individualCapsEnabled = false;
    mapping(address => uint256) public individualCaps;

    address satlayerSigner;

    // Next eventId to emit
    uint256 private eventId;
      
    constructor(address[] memory _tokensAllowed, uint256[] memory _caps, uint256[] memory _individualCaps, string[] memory _names, string[] memory _symbols) Ownable(msg.sender) EIP712("SatlayerPool", "1"){
        if (_tokensAllowed.length != _caps.length || _tokensAllowed.length != _individualCaps.length || _tokensAllowed.length != _names.length || _tokensAllowed.length != _symbols.length) revert TokenAndCapLengthMismatch();

        uint256 length = _tokensAllowed.length;
        for(uint256 i; i < length; ++i){
            if (_tokensAllowed[i] == address(0)) revert TokenCannotBeZeroAddress();
            // will revert if there are duplicates in the _tokensAllowed array
            addToken(_tokensAllowed[i], _caps[i], _individualCaps[i], _names[i], _symbols[i]);
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
        if (individualCapsEnabled && individualCaps[_token] != 0 && individualCaps[_token] < getUserTokenBalance(_token, _for) + _amount) revert IndividualCapReached();
        
        emit Deposit(++eventId, _for, _token, _amount);

        ReceiptToken(tokenMap[_token]).mint(_for, _amount);
        IERC20Metadata(_token).safeTransferFrom(msg.sender, address(this), _amount);   
    }


     
    /**
     * @inheritdoc ISatlayerPool
     */
    function withdraw(address _token, uint256 _amount) external {
        if (_amount == 0) revert WithdrawAmountCannotBeZero();
        if (getUserTokenBalance(_token, msg.sender) < _amount) revert InsufficientUserBalance();

        emit Withdraw(++eventId, msg.sender, _token, _amount);

        ReceiptToken(tokenMap[_token]).burn(msg.sender, _amount);
        IERC20Metadata(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function migrateWithSig(
        address _user,
        address[] calldata _tokens, 
        address _migratorContract, 
        address _destination, 
        uint256 _signatureExpiry, 
        bytes memory _stakerSignature
    ) onlyOwner external{
        {
            bytes32 structHash = keccak256(abi.encode(
                MIGRATE_TYPEHASH, 
                _user, 
                _migratorContract,
                _destination, 
                //The array values are encoded as the keccak256 hash of the concatenated encodeData of their contents 
                //Ref: https://eips.ethereum.org/EIPS/eip-712#definition-of-encodedata
                keccak256(abi.encodePacked(_tokens)),
                _signatureExpiry, 
                _useNonce(_user)
            ));
            bytes32 constructedHash = _hashTypedDataV4(structHash);

            if (!SignatureChecker.isValidSignatureNow(_user, constructedHash, _stakerSignature)){
                revert SignatureInvalid();
            }
        }

        uint256[] memory _amounts = _migrateChecks(_user, _tokens, _signatureExpiry, _migratorContract);
        _migrate(_user, _destination, _migratorContract, _tokens, _amounts);

    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function migrate(
        address[] calldata  _tokens, 
        address _migratorContract, 
        address _destination, 
        uint256 _signatureExpiry, 
        bytes calldata _authorizationSignatureFromSatlayer
    ) external { 
        uint256[] memory _amounts = _migrateChecks(msg.sender, _tokens, _signatureExpiry, _migratorContract);

        bytes32 constructedHash = keccak256(
                abi.encodePacked(
                    '\x19Ethereum Signed Message:\n32',
                    keccak256(
                        abi.encodePacked(
                            _migratorContract,
                            _signatureExpiry,
                            address(this),
                            block.chainid
                        )
                    )
                )
            );

        // verify that the migrator’s address is signed in the authorization signature by the correct signer (SatlayerSigner)
        if (!SignatureChecker.isValidSignatureNow(satlayerSigner, constructedHash, _authorizationSignatureFromSatlayer)){
            revert SignatureInvalid();
        }
        
        _migrate(msg.sender, _destination, _migratorContract, _tokens, _amounts);
    }

    function _migrateChecks(address _user, address[] calldata  _tokens, uint256 _signatureExpiry, address _migratorContract) 
        internal view returns (uint256[] memory _amounts){
        
        uint256 length = _tokens.length;
        if (length == 0) revert TokenArrayCannotBeEmpty();

        _amounts = new uint256[](length);

        for(uint256 i; i < length; ++i){
            _amounts[i] = balance[_tokens[i]][_user];
            if (_amounts[i] == 0) revert UserDoesNotHaveStake();
        }

        if (block.timestamp >= _signatureExpiry) revert SignatureExpired();// allows us to invalidate signature by having it expired

        if (migratorBlocklist[_migratorContract]) revert MigratorBlocked();
    }

    function _migrate(
        address _user, 
        address _destination, 
        address _migratorContract,
        address[] calldata  _tokens, 
        uint256[] memory _amounts) 
        internal {
        
        uint256 length = _tokens.length;
       //effects for-loop (state changes)
        for(uint256 i; i < length; ++i){
            //if the balance has been already set to zero, then _tokens[i] is a duplicate of a previous token in the array
            if (balance[_tokens[i]][_user] == 0) revert DuplicateToken();

            balance[_tokens[i]][_user] = 0;
        }

        emit Migrate (++eventId, _user, _tokens, _destination, _migratorContract, _amounts);

        //interactions for-loop (external calls)
        for(uint256 i; i < length; ++i){
            IERC20Metadata(_tokens[i]).approve(_migratorContract, _amounts[i]);
        }
       
        IMigrator(_migratorContract).migrate(_user, _tokens, _destination, _amounts);

    }
    



    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/


    /**
     * @inheritdoc ISatlayerPool
     */
    function setCap(address _token, uint256 _cap) external onlyOwner {
        // TODO: do we want to restrict it so the cap can never be decreased
        caps[_token] = _cap;
    }


    /**
     * @inheritdoc ISatlayerPool
     */
    function setCapsEnabled(bool _enabled) external onlyOwner {
        capsEnabled = _enabled;
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function setIndividualCap(address _token, uint256 _individualCap) external onlyOwner {
        // TODO: do we want to restrict it so the cap can never be decreased
        individualCaps[_token] = _individualCap;
    }


    /**
     * @inheritdoc ISatlayerPool
     */
    function setIndividualCapsEnabled(bool _enabled) external onlyOwner {
        individualCapsEnabled = _enabled;
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function setSatlayerSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert SignerCannotBeZeroAddress();
        if (_signer == satlayerSigner) revert SignerAlreadySetToAddress();

        satlayerSigner = _signer;
        emit SignerChanged(_signer);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function addToken(address _token, uint256 _cap, uint256 _individualCap, string memory _name, string memory _symbol) public onlyOwner {
        if (tokenMap[_token] != address(0)) revert TokenAlreadyAdded();

        ReceiptToken receiptToken = new ReceiptToken(_name, _symbol, IERC20Metadata(_token).decimals());

        tokenMap[_token] = address(receiptToken);
        reverseTokenMap[address(receiptToken)] = _token;

        setTokenStakingParams(_token, true, _cap, _individualCap);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function setTokenStakingParams(address _token, bool _canStake, uint256 _cap, uint256 _individualCap) public onlyOwner {
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        if (tokenAllowlist[_token] == _canStake) revert TokenAlreadyConfiguredWithState();

        tokenAllowlist[_token] = _canStake;

        caps[_token] = _cap;
        individualCaps[_token] = _individualCap;
        
        emit TokenStakabilityChanged(_token, _canStake);
    }

    /**
     * @inheritdoc ISatlayerPool
     */
    function blockMigrator(address _migrator, bool _blocklisted) external onlyOwner {
        if (_migrator == address(0)) revert MigratorCannotBeZeroAddress();
        if (migratorBlocklist[_migrator] == _blocklisted) revert MigratorAlreadyAllowedOrBlocked();

        migratorBlocklist[_migrator] = _blocklisted;
        emit BlocklistChanged(_migrator, _blocklisted);
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


    function renounceOwnership() public override{
        revert CannotRenounceOwnership();
    }


    /*//////////////////////////////////////////////////////////////
                         View Functions
    //////////////////////////////////////////////////////////////*/

    function getUserTokenBalance(address _token, address _user) public view returns (uint256) {
        return ReceiptToken(tokenMap[_token]).balanceOf(_user);
    }

    function getTokenTotalStaked(address _token) public view returns (uint256) {
        return ReceiptToken(tokenMap[_token]).totalSupply();
    }

}