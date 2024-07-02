// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import "./interface/IWETH.sol";

import "./interface/IMigrator.sol";
import "./interface/IZtakingPool.sol";


/// @title Ztaking Pool
/// @notice A staking pool for liquid restaking token holders which rewards stakers with points from multiple platforms
contract ZtakingPool is IZtakingPool, Ownable2Step, Pausable, EIP712, Nonces {

    using SafeERC20 for IERC20;

    bytes32 private constant MIGRATE_TYPEHASH =
        keccak256("Migrate(address user,address migratorContract,address destination,address[] tokens,uint256 signatureExpiry,uint256 nonce)");
    
    // (tokenAddress => isAllowedForStaking)
    mapping(address => bool) public tokenAllowlist;

    // (tokenAddress => stakerAddress => stakedAmount)
    mapping(address => mapping(address => uint256)) public balance;

    // (migratorContract => isBlocklisted)
    mapping(address => bool) public migratorBlocklist;

    // Next eventId to emit
    uint256 private eventId; 

    // Required signer for the migration message
    address public zircuitSigner;

    // ETH's special address
    address immutable WETH_ADDRESS;

    constructor(address _signer, address[] memory _tokensAllowed, address _weth) Ownable(msg.sender) EIP712("ZtakingPool", "1"){
        if (_signer == address(0)) revert SignerCannotBeZeroAddress();
        if (_weth == address(0)) revert WETHCannotBeZeroAddress();

        WETH_ADDRESS = _weth;

        zircuitSigner = _signer;
        uint256 length = _tokensAllowed.length;
        for(uint256 i; i < length; ++i){
            if (_tokensAllowed[i] == address(0)) revert TokenCannotBeZeroAddress();
            tokenAllowlist[_tokensAllowed[i]] = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            Staker Functions
    //////////////////////////////////////////////////////////////*/


    /**
     * @inheritdoc IZtakingPool
     */
    function depositFor(address _token, address _for, uint256 _amount) whenNotPaused external {
        if (_amount == 0) revert DepositAmountCannotBeZero();
        if (_for== address(0)) revert CannotDepositForZeroAddress();
        if (!tokenAllowlist[_token]) revert TokenNotAllowedForStaking();

        balance[_token][_for] += _amount;

        emit Deposit(++eventId, _for, _token, _amount);

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);   
    }

    function depositETHFor(address _for) whenNotPaused payable external {
        if (msg.value == 0) revert DepositAmountCannotBeZero();
        if (_for== address(0)) revert CannotDepositForZeroAddress();
        if (!tokenAllowlist[WETH_ADDRESS]) revert TokenNotAllowedForStaking();

        balance[WETH_ADDRESS][_for] += msg.value;
        emit Deposit(++eventId, _for, WETH_ADDRESS, msg.value);

        IWETH(WETH_ADDRESS).deposit{value:msg.value}();
    }

    /**
     * @inheritdoc IZtakingPool
     */
    function withdraw(address _token, uint256 _amount) external {
        if (_amount == 0) revert WithdrawAmountCannotBeZero();

        balance[_token][msg.sender] -= _amount; //Will underfow if the staker has insufficient balance
        emit Withdraw(++eventId, msg.sender, _token, _amount);

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @inheritdoc IZtakingPool
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
     * @inheritdoc IZtakingPool
     */
    function migrate(
        address[] calldata  _tokens, 
        address _migratorContract, 
        address _destination, 
        uint256 _signatureExpiry, 
        bytes calldata _authorizationSignatureFromZircuit
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

        // verify that the migrator’s address is signed in the authorization signature by the correct signer (zircuitSigner)
        if (!SignatureChecker.isValidSignatureNow(zircuitSigner, constructedHash, _authorizationSignatureFromZircuit)){
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
            IERC20(_tokens[i]).approve(_migratorContract, _amounts[i]);
        }
       
        IMigrator(_migratorContract).migrate(_user, _tokens, _destination, _amounts);

    }
    



    /*//////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IZtakingPool
     */
    function setZircuitSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert SignerCannotBeZeroAddress();
        if (_signer == zircuitSigner) revert SignerAlreadySetToAddress();

        zircuitSigner = _signer;
        emit SignerChanged(_signer);
    }

    /**
     * @inheritdoc IZtakingPool
     */
    function setStakable(address _token, bool _canStake) external onlyOwner {
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        if (tokenAllowlist[_token] == _canStake) revert TokenAlreadyConfiguredWithState();

        tokenAllowlist[_token] = _canStake;
        emit TokenStakabilityChanged(_token, _canStake);
    }

    /**
     * @inheritdoc IZtakingPool
     */
    function blockMigrator(address _migrator, bool _blocklisted) external onlyOwner {
        if (_migrator == address(0)) revert MigratorCannotBeZeroAddress();
        if (migratorBlocklist[_migrator] == _blocklisted) revert MigratorAlreadyAllowedOrBlocked();

        migratorBlocklist[_migrator] = _blocklisted;
        emit BlocklistChanged(_migrator, _blocklisted);
    }

    /**
     * @inheritdoc IZtakingPool
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @inheritdoc IZtakingPool
     */
    function unpause() external onlyOwner whenPaused{
        _unpause();
    }


    function renounceOwnership() public override{
        revert CannotRenounceOwnership();
    }

    
}