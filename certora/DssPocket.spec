// DssPocket.spec

using GemMock as gem;

methods {
    function wards(address) external returns (uint256) envfree;
    function gem.allowance(address, address) external returns (uint256) envfree;
}

// Verify that each storage layout is only modified in the corresponding functions
rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint gemAllowancePocketBefore = gem.allowance(currentContract, anyAddr);

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint gemAllowancePocketAfter = gem.allowance(currentContract, anyAddr);

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert gemAllowancePocketAfter != gemAllowancePocketBefore => f.selector == sig:hope(address).selector || f.selector == sig:nope(address).selector, "gem.allowance(pocket, x) changed in an unexpected function";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address otherAddr;
    require otherAddr != usr;

    mathint wardsOtherBefore = wards(otherAddr);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(otherAddr);

    assert wardsUsrAfter == 1, "rely did not set wards[usr]";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address otherAddr;
    require otherAddr != usr;

    mathint wardsOtherBefore = wards(otherAddr);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(otherAddr);

    assert wardsUsrAfter == 0, "deny did not set wards[usr]";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting hope
rule hope(address usr) {
    env e;

    hope(e, usr);

    mathint gemAllowancePocketUsrAfter = gem.allowance(currentContract, usr);

    assert gemAllowancePocketUsrAfter == max_uint256, "hope did not set gem.allowance(pocket, usr) to max_uint256";
}

// Verify revert rules on hope
rule hope_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    hope@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting nope
rule nope(address usr) {
    env e;

    nope(e, usr);

    mathint gemAllowancePocketUsrAfter = gem.allowance(currentContract, usr);

    assert gemAllowancePocketUsrAfter == 0, "nope did not set gem.allowance(pocket, usr) to 0";
}

// Verify revert rules on nope
rule nope_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    nope@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}
