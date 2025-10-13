methods {
    // SatlayerPool
    function caps(address) external returns (uint) envfree;
    function capsEnabled() external returns (bool) envfree;
    function getTokenTotalStaked(address) external returns (uint256) envfree;
    function migrator() external returns (address) envfree;
    function tokenAllowlist(address) external returns (bool) envfree;
    function tokenMap(address) external returns (address) envfree;
    // Ownable
    function owner() external returns (address) envfree;
    // ERC20
    function _.approve(address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.burn(address, uint256) external => DISPATCHER(true);
    function _.decimals() external => DISPATCHER(true);
    function _.mint(address, uint256) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
}

// Notice: we always skip `renounceOwnership` because it always reverts making the rules vacuous
definition isRenounceOwnershipMethod (method f) returns bool = f.selector == sig:renounceOwnership().selector;

function applySafeAssumptions(env e) {
    require e.msg.sender != currentContract;
    require e.msg.sender != 0;
}

//=============
// High level
//=============

// `tokenAllowlist` updates are restricted
// Roles:
// - owner
// Methods:
// - `setTokenStakingParams()`
// - `addToken()`
rule high_tokenAllowlistRestrictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;
    address stakingToken;

    bool isTokenAllowedBefore = tokenAllowlist(stakingToken);

    f(e, args);

    bool isTokenAllowedAfter = tokenAllowlist(stakingToken);

    assert 
        isTokenAllowedBefore != isTokenAllowedAfter => 
            (
                f.selector == sig:setTokenStakingParams(address, bool, uint256).selector ||
                f.selector == sig:addToken(address, uint256, string, string).selector
            ) &&
                e.msg.sender == owner();
}

// `tokenMap` updates are restricted
// Roles:
// - owner
// Methods:
// - `addToken()`
rule high_tokenMapRestictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;
    address stakingToken;

    address receiptTokenBefore = tokenMap(stakingToken);

    f(e, args);

    address receiptTokenAfter = tokenMap(stakingToken);

    assert
        receiptTokenBefore != receiptTokenAfter =>
            f.selector == sig:addToken(address, uint256, string, string).selector &&
            e.msg.sender == owner();
}

// `capsEnabled` updates are restricted
// Roles:
// - owner
// Methods:
// - `setCapsEnabled()`
rule high_capsEnabledRestrictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;

    bool isCapsEnabledBefore = capsEnabled();

    f(e, args);

    bool isCapsEnabledAfter = capsEnabled();

    assert 
        isCapsEnabledBefore != isCapsEnabledAfter =>
            f.selector == sig:setCapsEnabled(bool).selector &&
            e.msg.sender == owner();
}

// `caps` updates are restricted
// Roles:
// - owner
// Methods:
// - `setTokenStakingParams()`
// - `addToken()`
rule high_capsRestrictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;
    address stakingToken;

    uint256 capsBefore = caps(stakingToken);

    f(e, args);

    uint256 capsAfter = caps(stakingToken);

    assert 
        capsBefore != capsAfter => 
            (
                f.selector == sig:setTokenStakingParams(address, bool, uint256).selector ||
                f.selector == sig:addToken(address, uint256, string, string).selector
            ) &&
                e.msg.sender == owner();
}

// `migrator` updates are restricted
// Roles:
// - owner
// Methods:
// - `setMigrator()`
rule high_migratorRestrictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;

    address migratorBefore = migrator();

    f(e, args);

    address migratorAfter = migrator();

    assert 
        migratorBefore != migratorAfter =>
            f.selector == sig:setMigrator(address).selector &&
            e.msg.sender == owner();
}

// `eventId` only increases & updates are restricted.
// Methods:
// - `depositFor()`
// - `withdraw()`
// - `migrate()`
rule high_eventIdMonotonicity(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;

    uint256 eventIdBefore = currentContract.eventId;

    f(e, args);

    uint256 eventIdAfter = currentContract.eventId;

    // eventId only increases
    assert eventIdAfter >= eventIdBefore;
    // only certain methods can increase `eventId`
    assert 
        eventIdAfter > eventIdBefore =>
            f.selector == sig:depositFor(address, address, uint).selector ||
            f.selector == sig:withdraw(address, uint).selector ||
            f.selector == sig:migrate(address[], string).selector;
}

// `onlyOwner` protected methods can be called only by contract owner
rule high_accessControl(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;

    f(e, args);

    assert (
        f.selector == sig:setCapsEnabled(bool).selector ||
        f.selector == sig:setMigrator(address).selector ||
        f.selector == sig:addToken(address, uint256, string, string).selector ||
        f.selector == sig:setTokenStakingParams(address, bool, uint256).selector ||
        f.selector == sig:pause().selector ||
        f.selector == sig:unpause().selector ||
        f.selector == sig:recoverERC20(address, address, uint256).selector
    ) => e.msg.sender == owner();
}

// `whenNotPaused` protected methods always revert if contract is paused
rule high_whenNotPausedRestrictions(method f) filtered { f -> !isRenounceOwnershipMethod(f) } {
    env e;
    calldataarg args;

    pause(e);

    f@withrevert(e, args);

    bool isReverted = lastReverted;

    assert (
        f.selector == sig:depositFor(address, address, uint256).selector ||
        f.selector == sig:migrate(address[], string).selector ||
        f.selector == sig:pause().selector
    ) => isReverted;
}

//=============
// Unit
//=============

// `depositFor()` updates storage as expected
rule unit_depositForIntegrity() {
    env e;

    address stakeToken;
    address receiver;
    uint256 amount;
    address receiptToken = tokenMap(stakeToken);

    applySafeAssumptions(e);
    require receiver != currentContract;
    require receiver != e.msg.sender;

    uint256 stakingTokenContractBalanceBefore = stakeToken.balanceOf(e, currentContract);
    uint256 receiptTokenReceiverBalanceBefore = receiptToken.balanceOf(e, receiver);

    depositFor(e, stakeToken, receiver, amount);

    uint256 stakingTokenContractBalanceAfter = stakeToken.balanceOf(e, currentContract);
    uint256 receiptTokenReceiverBalanceAfter = receiptToken.balanceOf(e, receiver);

    assert require_uint256(stakingTokenContractBalanceBefore + amount) == stakingTokenContractBalanceAfter;
    assert require_uint256(receiptTokenReceiverBalanceBefore + amount) == receiptTokenReceiverBalanceAfter;
}

// `depositFor()` reverts when expected
rule unit_depositForRevertConditions() {
    env e;

    address token;
    address receiver;
    uint256 amount;

    applySafeAssumptions(e);

    require token.owner(e) == currentContract;

    bool isPaused = paused(e);
    bool isAmountZero = amount == 0;
    bool isReceiverZero = receiver == 0;
    bool isTokenAllowed = tokenAllowlist(e, token);
    bool isCapsReached = capsEnabled(e) && (getTokenTotalStaked(e, token) + amount > caps(e, token));
    bool isEventIdOverflow = currentContract.eventId + 1 > max_uint256;
    bool hasEnoughBalance = token.balanceOf(e, e.msg.sender) >= amount;
    bool isSatlayerPoolBalanceOverflow = token.balanceOf(e, currentContract) + amount > max_uint256;
    bool hasEnoughAllowance = token.allowance(e, e.msg.sender, currentContract) >= amount;
    bool isReceiptTokenOverflow = token.totalSupply(e) + amount > max_uint256;
    bool isExpectedToRevert = 
        isPaused || 
        isAmountZero || 
        isReceiverZero || 
        !isTokenAllowed || 
        isCapsReached || 
        isEventIdOverflow || 
        !hasEnoughBalance || 
        isSatlayerPoolBalanceOverflow ||
        !hasEnoughAllowance ||
        isReceiptTokenOverflow;

    depositFor@withrevert(e, token, receiver, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `depositFor()` does not affect other entities
rule unit_depositForDoesNotAffectOtherEntities() {
    env e;

    address stakeToken;
    address receiver;
    uint256 amount;
    address receiptToken = tokenMap(stakeToken);
    address otherUser;

    applySafeAssumptions(e);
    require receiver != currentContract;
    require receiver != e.msg.sender;
    require otherUser != receiver && otherUser != e.msg.sender && otherUser != currentContract;

    uint256 stakingTokenBalanceBefore = stakeToken.balanceOf(e, otherUser);
    uint256 receiptTokenBalanceBefore = receiptToken.balanceOf(e, otherUser);

    depositFor(e, stakeToken, receiver, amount);

    uint256 stakingTokenBalanceAfter = stakeToken.balanceOf(e, otherUser);
    uint256 receiptTokenBalanceAfter = receiptToken.balanceOf(e, otherUser);

    assert stakingTokenBalanceBefore == stakingTokenBalanceAfter;
    assert receiptTokenBalanceBefore == receiptTokenBalanceAfter;
}

// `withdraw()` updates storage as expected
rule unit_withdrawIntegrity() {
    env e;

    address stakeToken;
    uint256 amount;
    address receiptToken = tokenMap(stakeToken);

    applySafeAssumptions(e);

    uint256 stakeTokenBalanceBefore = stakeToken.balanceOf(e, e.msg.sender);
    uint256 receiptTokenBalanceBefore = receiptToken.balanceOf(e, e.msg.sender);

    withdraw(e, stakeToken, amount);

    uint256 stakeTokenBalanceAfter = stakeToken.balanceOf(e, e.msg.sender);
    uint256 receiptTokenBalanceAfter = receiptToken.balanceOf(e, e.msg.sender);

    assert stakeTokenBalanceBefore <= stakeTokenBalanceAfter;
    assert receiptTokenBalanceBefore >= receiptTokenBalanceAfter;
}

// `withdraw()` reverts when expected
rule unit_withdrawRevertConditions() {
    env e;

    address token;
    uint256 amount;

    applySafeAssumptions(e);
    require token.owner(e) == currentContract;
    require token != currentContract;

    bool isAmountZero = amount == 0;
    bool hasEnoughBalance = getUserTokenBalance(e, token, e.msg.sender) >= amount;
    bool isEventIdOverflow = currentContract.eventId + 1 > max_uint256;
    bool isPoolSolvent = token.balanceOf(e, currentContract) >= amount;

    bool isExpectedToRevert = 
        isAmountZero ||
        !hasEnoughBalance ||
        isEventIdOverflow ||
        !isPoolSolvent;

    withdraw@withrevert(e, token, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `withdraw()` does not affect other entities
rule unit_withdrawDoesNotAffectOtherEntities() {
    env e;

    address stakeToken;
    uint256 amount;
    address receiptToken = tokenMap(stakeToken);
    address otherUser;

    applySafeAssumptions(e);
    require otherUser != e.msg.sender && otherUser != currentContract;

    uint256 stakeTokenBalanceBefore = stakeToken.balanceOf(e, otherUser);
    uint256 receiptTokenBalanceBefore = receiptToken.balanceOf(e, otherUser);

    withdraw(e, stakeToken, amount);

    uint256 stakeTokenBalanceAfter = stakeToken.balanceOf(e, otherUser);
    uint256 receiptTokenBalanceAfter = receiptToken.balanceOf(e, otherUser);

    assert stakeTokenBalanceBefore == stakeTokenBalanceAfter;
    assert receiptTokenBalanceBefore == receiptTokenBalanceAfter;
}

// `migrate()` updates storage as expected
rule unit_migrateIntegrity() {
    env e;

    address stakeToken;
    address receiptToken = tokenMap(stakeToken);
    address[] tokens;
    string destinationAddress = "ANY";

    applySafeAssumptions(e);

    uint256 receiptTokenBalanceBefore = receiptToken.balanceOf(e, e.msg.sender);

    migrate(e, tokens, destinationAddress);

    uint256 receiptTokenBalanceAfter = receiptToken.balanceOf(e, e.msg.sender);

    assert receiptTokenBalanceBefore > 0 => receiptTokenBalanceAfter == 0;
}

// `migrate()` reverts when expected
rule unit_migrateRevertConditions() {
    env e;

    address token;
    address[] tokens;
    string destinationAddress = "ANY";
    uint256 tokenIndex;

    applySafeAssumptions(e);
    require token.owner(e) == currentContract;
    require token != currentContract;
    require tokenIndex < tokens.length;
    require tokens.length == 1;

    bool isMigratorZero = migrator() == 0;
    bool isTokensArrayEmpty = tokens.length == 0;
    bool isBalanceEmpty = getUserTokenBalance(e, tokens[tokenIndex], e.msg.sender) == 0;
    bool isEventIdOverflow = currentContract.eventId + 1 > max_uint256;
    bool isTokenAdded = tokenMap(tokens[tokenIndex]) != 0;
    bool isPaused = paused(e);

    bool isExpectedToRevert = 
        isMigratorZero ||
        isTokensArrayEmpty ||
        isBalanceEmpty ||
        isEventIdOverflow ||
        !isTokenAdded ||
        isPaused;

    migrate@withrevert(e, tokens, destinationAddress);

    assert lastReverted <=> isExpectedToRevert;
}

// `migrate()` does not affect other entities
rule unit_migrateDoesNotAffectOtherEntities() {
    env e;

    address stakeToken;
    address receiptToken = tokenMap(stakeToken);
    address[] tokens;
    string destinationAddress = "ANY";
    address otherUser;

    applySafeAssumptions(e);
    require otherUser != e.msg.sender && otherUser != currentContract;

    uint256 receiptTokenBalanceBefore = receiptToken.balanceOf(e, otherUser);

    migrate(e, tokens, destinationAddress);

    uint256 receiptTokenBalanceAfter = receiptToken.balanceOf(e, otherUser);

    assert receiptTokenBalanceBefore == receiptTokenBalanceAfter;
}

// `setCapsEnabled()` updates storage as expected
rule unit_setCapsEnabledIntegrity() {
    env e;

    bool isEnabled;

    setCapsEnabled(e, isEnabled);

    assert capsEnabled(e) == isEnabled;
}

// `setCapsEnabled()` reverts when expected
rule unit_setCapsEnabledRevertConditions() {
    env e;

    bool isEnabled;

    bool isOwner = owner() == e.msg.sender;
    bool isParamChanged = capsEnabled() != isEnabled;
    bool isEtherSent = e.msg.value > 0;

    bool isExpectedToRevert = 
        !isOwner ||
        !isParamChanged ||
        isEtherSent;

    setCapsEnabled@withrevert(e, isEnabled);

    assert lastReverted <=> isExpectedToRevert;
}

// `setMigrator()` updates storage as expected
rule unit_setMigratorIntegrity() {
    env e;

    address newMigrator;

    setMigrator(e, newMigrator);

    assert migrator() == newMigrator;
}

// `setMigrator()` reverts when expected
rule unit_setMigratorRevertConditions() {
    env e;

    address newMigrator;

    bool isOwner = owner() == e.msg.sender;
    bool isMigratorZero = newMigrator == 0;
    bool isEtherSent = e.msg.value > 0;

    bool isExpectedToRevert = 
        !isOwner ||
        isMigratorZero ||
        isEtherSent;

    setMigrator@withrevert(e, newMigrator);

    assert lastReverted <=> isExpectedToRevert;
}

// `addToken()` updates storage as expected
rule unit_addTokenIntegrity() {
    env e;

    address token;
    uint256 cap;
    string name = "ANY";
    string symbol = "ANY";

    addToken(e, token, cap, name, symbol);

    assert tokenMap(token) != 0;
}

// `addToken()` reverts when expected
rule unit_addTokenRevertConditions() {
    env e;

    address token;
    uint256 cap;
    string name = "ANY";
    string symbol = "ANY";

    bool isOwner = owner() == e.msg.sender;
    bool isTokenZero = token == 0;
    bool isTokenAdded = tokenMap(token) != 0;
    bool isEtherSent = e.msg.value > 0;
    bool areParamsUnchanged = tokenAllowlist(token) && caps(token) == cap;

    bool isExpectedToRevert = 
        !isOwner ||
        isTokenZero ||
        isTokenAdded ||
        isEtherSent ||
        areParamsUnchanged;

    addToken@withrevert(e, token, cap, name, symbol);

    assert lastReverted <=> isExpectedToRevert;
}

// `setTokenStakingParams()` updates storage as expected
rule unit_setTokenStakingParamsIntegrity() {
    env e;

    address token;
    bool canStake;
    uint256 cap;

    setTokenStakingParams(e, token, canStake, cap);

    assert tokenAllowlist(token) == canStake;
    assert caps(token) == cap;
}

// `setTokenStakingParams()` reverts when expected
rule unit_setTokenStakingParamsRevertConditions() {
    env e;

    address token;
    bool canStake;
    uint256 cap;

    bool isOwner = owner() == e.msg.sender;
    bool isTokenZero = token == 0;
    bool isTokenAdded = tokenMap(token) != 0;
    bool isEtherSent = e.msg.value > 0;
    bool areParamsUnchanged = tokenAllowlist(token) == canStake && caps(token) == cap;

    bool isExpectedToRevert = 
        !isOwner ||
        isTokenZero ||
        !isTokenAdded ||
        isEtherSent ||
        areParamsUnchanged;

    setTokenStakingParams@withrevert(e, token, canStake, cap);

    assert lastReverted <=> isExpectedToRevert;
}

// `pause()` updates storage as expected
rule unit_pauseIntegrity() {
    env e;

    pause(e);

    assert paused(e);
}

// `pause()` reverts when expected
rule unit_pauseRevertConditions() {
    env e;

    bool isOwner = owner() == e.msg.sender;
    bool isPaused = paused(e);

    bool isExpectedToRevert = 
        !isOwner ||
        isPaused;

    pause@withrevert(e);

    assert lastReverted <=> isExpectedToRevert;
}

// `unpause()` updates storage as expected
rule unit_unpauseIntegrity() {
    env e;

    unpause(e);

    assert !paused(e);
}

// `unpause()` reverts when expected
rule unit_unpauseRevertConditions() {
    env e;

    bool isOwner = owner() == e.msg.sender;
    bool isPaused = paused(e);

    bool isExpectedToRevert = 
        !isOwner ||
        !isPaused;

    unpause@withrevert(e);

    assert lastReverted <=> isExpectedToRevert;
}

// `recoverERC20()` updates storage as expected
rule unit_recoverERC20Integrity() {
    env e;

    address token;
    address receiver;
    uint256 amount;

    applySafeAssumptions(e);
    require receiver != currentContract;

    uint256 balanceBefore = token.balanceOf(e, receiver);

    recoverERC20(e, token, receiver, amount);

    uint256 balanceAfter = token.balanceOf(e, receiver);

    assert require_uint256(balanceBefore + amount) == balanceAfter;
}

// `recoverERC20()` reverts when expected
rule unit_recoverERC20RevertConditions() {
    env e;

    address token;
    address receiver;
    uint256 amount;

    applySafeAssumptions(e);

    bool isOwner = owner() == e.msg.sender;
    bool isTokenAdded = tokenMap(token) != 0;
    bool isEtherSent = e.msg.value > 0;
    bool hasEnoughBalance = token.balanceOf(e, currentContract) >= amount;
    bool isReceiverZero = receiver == 0;

    bool isExpectedToRevert = 
        !isOwner ||
        isTokenAdded ||
        isEtherSent ||
        !hasEnoughBalance ||
        isReceiverZero;

    recoverERC20@withrevert(e, token, receiver, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `recoverERC20()` does not affect other entities
rule unit_recoverERC20DoesNotAffectOtherEntities() {
    env e;

    address token;
    address receiver;
    uint256 amount;
    address otherUser;

    require otherUser != receiver && otherUser != e.msg.sender && otherUser != currentContract;

    applySafeAssumptions(e);

    uint256 balanceBefore = token.balanceOf(e, otherUser);

    recoverERC20(e, token, receiver, amount);

    uint256 balanceAfter = token.balanceOf(e, otherUser);

    assert balanceBefore == balanceAfter;
}

// `renounceOwnership()` reverts when expected
rule unit_renounceOwnershipRevertConditions() {
    env e;

    renounceOwnership@withrevert(e);

    assert lastReverted;
}