// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/SatlayerPool.sol";
import "../src/ReceiptToken.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function test() public {} // exclude from coverage

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

}

contract MockMigrator {
    function migrate(address user, string memory destinationAddress, address[] memory tokens, uint256[] memory amounts) external {}
    function test() public {} // exclude from coverage
}

contract SatlayerPoolTest is Test {
    SatlayerPool public pool;
    MockERC20 public token1;
    MockERC20 public token2;
    MockMigrator public migrator;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        uint256[] memory caps = new uint256[](2);
        caps[0] = 1000 ether;
        caps[1] = 2000 ether;

        string[] memory names = new string[](2);
        names[0] = "Token1";
        names[1] = "Token2";

        string[] memory symbols = new string[](2);
        symbols[0] = "TKN1";
        symbols[1] = "TKN2";

        pool = new SatlayerPool(tokens, caps, names, symbols);

        migrator = new MockMigrator();

        token1.mint(user1, 1000 ether);
        token2.mint(user1, 2000 ether);
        token1.mint(user2, 1000 ether);
        token2.mint(user2, 2000 ether);
    }

    function testConstructor() public {
        assertTrue(pool.tokenAllowlist(address(token1)));
        assertTrue(pool.tokenAllowlist(address(token2)));
        assertEq(pool.caps(address(token1)), 1000 ether);
        assertEq(pool.caps(address(token2)), 2000 ether);
        assertNotEq(pool.tokenMap(address(token1)), address(0));
        assertNotEq(pool.tokenMap(address(token2)), address(0));
    }

    function testDepositFor() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        vm.stopPrank();

        assertEq(pool.getUserTokenBalance(address(token1), user1), 100 ether);
        assertEq(pool.getTokenTotalStaked(address(token1)), 100 ether);
    }

    function testDepositForOtherUser() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user2, 100 ether);
        vm.stopPrank();

        assertEq(pool.getUserTokenBalance(address(token1), user2), 100 ether);
        assertEq(pool.getTokenTotalStaked(address(token1)), 100 ether);
    }

    function testDepositForZeroAmount() public {
        vm.expectRevert(ISatlayerPool.DepositAmountCannotBeZero.selector);
        pool.depositFor(address(token1), user1, 0);
    }

    function testDepositForZeroAddress() public {
        vm.expectRevert(ISatlayerPool.CannotDepositForZeroAddress.selector);
        pool.depositFor(address(token1), address(0), 100 ether);
    }

    function testDepositForUnallowedToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        vm.expectRevert(ISatlayerPool.TokenNotAllowedForStaking.selector);
        pool.depositFor(address(invalidToken), user1, 100 ether);
    }

    function testDepositExceedingCap() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 1001 ether);
        vm.expectRevert(ISatlayerPool.CapReached.selector);
        pool.depositFor(address(token1), user1, 1001 ether);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        pool.withdraw(address(token1), 50 ether);
        vm.stopPrank();

        assertEq(pool.getUserTokenBalance(address(token1), user1), 50 ether);
        assertEq(pool.getTokenTotalStaked(address(token1)), 50 ether);
    }

    function testWithdrawZeroAmount() public {
        vm.expectRevert(ISatlayerPool.WithdrawAmountCannotBeZero.selector);
        pool.withdraw(address(token1), 0);
    }

    function testWithdrawInsufficientBalance() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        vm.expectRevert(ISatlayerPool.InsufficientUserBalance.selector);
        pool.withdraw(address(token1), 101 ether);
        vm.stopPrank();
    }

    function testMigrate() public {
        pool.setMigrator(address(migrator));

        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        token2.approve(address(pool), 200 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        pool.depositFor(address(token2), user1, 200 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        pool.migrate(tokens, "destination_address");
        vm.stopPrank();

        assertEq(pool.getUserTokenBalance(address(token1), user1), 0);
        assertEq(pool.getUserTokenBalance(address(token2), user1), 0);
    }

    function testMigrateNoMigrator() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        vm.expectRevert(ISatlayerPool.MigratorNotSet.selector);
        pool.migrate(tokens, "destination_address");
        vm.stopPrank();
    }

    function testMigrateEmptyTokenArray() public {
        pool.setMigrator(address(migrator));

        address[] memory tokens = new address[](0);

        vm.expectRevert(ISatlayerPool.TokenArrayCannotBeEmpty.selector);
        pool.migrate(tokens, "destination_address");
    }

    function testSetCapsEnabled() public {
        pool.setCapsEnabled(false);
        assertFalse(pool.capsEnabled());

        pool.setCapsEnabled(true);
        assertTrue(pool.capsEnabled());
    }

    function testSetCapsEnabledUnchanged() public {
        vm.expectRevert(ISatlayerPool.ParamsUnchanged.selector);
        pool.setCapsEnabled(true);
    }

    function testSetMigrator() public {
        address newMigrator = address(0x123);
        pool.setMigrator(newMigrator);
        assertEq(pool.migrator(), newMigrator);
    }

    function testSetMigratorZeroAddress() public {
        vm.expectRevert(ISatlayerPool.MigratorCannotBeZeroAddress.selector);
        pool.setMigrator(address(0));
    }

    function testAddToken() public {
        MockERC20 newToken = new MockERC20("NewToken", "NEW");
        pool.addToken(address(newToken), 500 ether, "NewToken", "NEW");

        assertTrue(pool.tokenAllowlist(address(newToken)));
        assertEq(pool.caps(address(newToken)), 500 ether);
    }

    function testAddTokenAlreadyAdded() public {
        vm.expectRevert(ISatlayerPool.TokenAlreadyAdded.selector);
        pool.addToken(address(token1), 500 ether, "Token 1", "TKN1");
    }

    function testSetTokenStakingParams() public {
        pool.setTokenStakingParams(address(token1), false, 2000 ether);

        assertFalse(pool.tokenAllowlist(address(token1)));
        assertEq(pool.caps(address(token1)), 2000 ether);
    }

    function testSetTokenStakingParamsZeroAddress() public {
        vm.expectRevert(ISatlayerPool.TokenCannotBeZeroAddress.selector);
        pool.setTokenStakingParams(address(0), true, 1000 ether);
    }

    function testSetTokenStakingParamsNotAdded() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        vm.expectRevert(ISatlayerPool.TokenNotAdded.selector);
        pool.setTokenStakingParams(address(invalidToken), true, 1000 ether);
    }

    function testSetTokenStakingParamsUnchanged() public {
        vm.expectRevert(ISatlayerPool.ParamsUnchanged.selector);
        pool.setTokenStakingParams(address(token1), true, 1000 ether);
    }

    function testPauseUnpause() public {
        pool.pause();
        assertTrue(pool.paused());

        pool.unpause();
        assertFalse(pool.paused());
    }

    function testPauseWhenPaused() public {
        pool.pause();
        vm.expectRevert();
        pool.pause();
    }

    function testUnpauseWhenNotPaused() public {
        vm.expectRevert();
        pool.unpause();
    }

    function testRecoverERC20() public {
        MockERC20 recoveryToken = new MockERC20("Recovery", "REC");
        recoveryToken.mint(address(pool), 100 ether);

        pool.recoverERC20(address(recoveryToken), owner, 100 ether);
        assertEq(recoveryToken.balanceOf(owner), 100 ether);
    }

    function testRecoverERC20StakingToken() public {
        vm.expectRevert(ISatlayerPool.TokenAlreadyAdded.selector);
        pool.recoverERC20(address(token1), owner, 100 ether);
    }

    function testRenounceOwnership() public {
        vm.expectRevert(ISatlayerPool.CannotRenounceOwnership.selector);
        pool.renounceOwnership();
    }

    function testGetUserTokenBalance() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        vm.stopPrank();

        assertEq(pool.getUserTokenBalance(address(token1), user1), 100 ether);
    }

    function testGetUserTokenBalanceInvalidToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        vm.expectRevert(ISatlayerPool.TokenNotAdded.selector);
        pool.getUserTokenBalance(address(invalidToken), user1);
    }

    function testGetTokenTotalStaked() public {
        vm.startPrank(user1);
        token1.approve(address(pool), 100 ether);
        pool.depositFor(address(token1), user1, 100 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        token1.approve(address(pool), 50 ether);
        pool.depositFor(address(token1), user2, 50 ether);
        vm.stopPrank();

        assertEq(pool.getTokenTotalStaked(address(token1)), 150 ether);
    }

    function testGetTokenTotalStakedInvalidToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        vm.expectRevert(ISatlayerPool.TokenNotAdded.selector);
        pool.getTokenTotalStaked(address(invalidToken));
    }
}
