// DssLitePsm.spec

using Vat as vat;
using DaiJoin as daiJoin;
using Dai as dai;
using GemMock as gem;

methods {
    function ilk() external returns (bytes32) envfree;
    function to18ConversionFactor() external returns (uint256) envfree;
    function pocket() external returns (address) envfree;
    function wards(address) external returns (uint256) envfree;
    function bud(address) external returns (uint256) envfree;
    function vow() external returns (address) envfree;
    function tin() external returns (uint256) envfree;
    function tout() external returns (uint256) envfree;
    function buf() external returns (uint256) envfree;
    function rush() external returns (uint256) envfree;
    function gush() external returns (uint256) envfree;
    function cut() external returns (uint256) envfree;
    function vat.live() external returns (uint256) envfree;
    function vat.can(address, address) external returns (uint256) envfree;
    function vat.dai(address) external returns (uint256) envfree;
    function vat.debt() external returns (uint256) envfree;
    function vat.Line() external returns (uint256) envfree;
    function vat.ilks(bytes32) external returns (uint256, uint256, uint256, uint256, uint256) envfree;
    function vat.urns(bytes32, address) external returns (uint256, uint256) envfree;
    function daiJoin.live() external returns (uint256) envfree;
    function dai.wards(address) external returns (uint256) envfree;
    function dai.totalSupply() external returns (uint256) envfree;
    function dai.balanceOf(address) external returns (uint256) envfree;
    function dai.allowance(address, address) external returns (uint256) envfree;
    function gem.totalSupply() external returns (uint256) envfree;
    function gem.balanceOf(address) external returns (uint256) envfree;
    function gem.allowance(address, address) external returns (uint256) envfree;
}

definition WAD() returns mathint = 10^18;
definition RAY() returns mathint = 10^27;
definition max_int256() returns mathint = 2^255 - 1;
definition min(mathint x, mathint y) returns mathint = x < y ? x : y;
definition max(mathint x, mathint y) returns mathint = x > y ? x : y;
definition subCap(mathint x, mathint y) returns mathint = x > y ? x - y : 0;

rule storageAffected(method f) {
    env e;

    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    mathint budBefore = bud(anyAddr);
    address vowBefore = vow();
    mathint tinBefore = tin();
    mathint toutBefore = tout();
    mathint bufBefore = buf();

    calldataarg args;
    f(e, args);

    mathint wardsAfter = wards(anyAddr);
    mathint budAfter = bud(anyAddr);
    address vowAfter = vow();
    mathint tinAfter = tin();
    mathint toutAfter = tout();
    mathint bufAfter = buf();

    assert wardsAfter != wardsBefore => f.selector == sig:rely(address).selector || f.selector == sig:deny(address).selector, "wards[x] changed in an unexpected function";
    assert budAfter != budBefore => f.selector == sig:kiss(address).selector || f.selector == sig:diss(address).selector, "bud[x] changed in an unexpected function";
    assert vowAfter != vowBefore => f.selector == sig:file(bytes32, address).selector, "vow changed in an unexpected function";
    assert tinAfter != tinBefore => f.selector == sig:file(bytes32, uint256).selector, "tin changed in an unexpected function";
    assert toutAfter != toutBefore => f.selector == sig:file(bytes32, uint256).selector, "tout changed in an unexpected function";
    assert bufAfter != bufBefore => f.selector == sig:file(bytes32, uint256).selector, "buf changed in an unexpected function";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address otherAddr;
    require otherAddr != usr;
    address anyAddr;

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
    address anyAddr;

    mathint wardsOtherBefore = wards(otherAddr);
    mathint budBefore = bud(anyAddr);

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

// Verify correct storage changes for non reverting kiss
rule kiss(address usr) {
    env e;

    address otherAddr;
    require otherAddr != usr;
    address anyAddr;

    mathint budOtherBefore = bud(otherAddr);

    kiss(e, usr);

    mathint budUsrAfter = bud(usr);
    mathint budOtherAfter = bud(otherAddr);

    assert budUsrAfter == 1, "kiss did not set bud[usr]";
    assert budOtherAfter == budOtherBefore, "kiss did not keep unchanged the rest of bud[x]";
}

// Verify revert rules on kiss
rule kiss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    kiss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting diss
rule diss(address usr) {
    env e;

    address otherAddr;
    require otherAddr != usr;
    address anyAddr;

    mathint budOtherBefore = bud(otherAddr);

    diss(e, usr);

    mathint budUsrAfter = bud(usr);
    mathint budOtherAfter = bud(otherAddr);

    assert budUsrAfter == 0, "diss did not set bud[usr]";
    assert budOtherAfter == budOtherBefore, "diss did not keep unchanged the rest of bud[x]";
}

// Verify revert rules on diss
rule diss_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    diss@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting file
rule file_address(bytes32 what, address data) {
    env e;

    address anyAddr;

    file(e, what, data);

    address vowAfter = vow();

    assert vowAfter == data, "file did not set vow";
}

// Verify revert rules on file
rule file_address_revert(bytes32 what, address data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x766f770000000000000000000000000000000000000000000000000000000000);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting file
rule file_uint256(bytes32 what, uint256 data) {
    env e;

    address anyAddr;

    mathint tinBefore = tin();
    mathint toutBefore = tout();
    mathint bufBefore = buf();

    file(e, what, data);

    mathint tinAfter = tin();
    mathint toutAfter = tout();
    mathint bufAfter = buf();

    assert what == to_bytes32(0x74696e0000000000000000000000000000000000000000000000000000000000)
           => tinAfter == to_mathint(data), "file did not set tin";
    assert what != to_bytes32(0x74696e0000000000000000000000000000000000000000000000000000000000)
           => tinAfter == tinBefore, "file did not keep unchanged tin";
    assert what == to_bytes32(0x746f757400000000000000000000000000000000000000000000000000000000)
           => toutAfter == to_mathint(data), "file did not set tout";
    assert what != to_bytes32(0x746f757400000000000000000000000000000000000000000000000000000000)
           => toutAfter == toutBefore, "file did not keep unchanged tout";
    assert what == to_bytes32(0x6275660000000000000000000000000000000000000000000000000000000000)
           => bufAfter == to_mathint(data), "file did not set buf";
    assert what != to_bytes32(0x6275660000000000000000000000000000000000000000000000000000000000)
           => bufAfter == bufBefore, "file did not keep unchanged buf";
}

// Verify revert rules on file
rule file_uint256_revert(bytes32 what, uint256 data) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;
    bool revert3 = what != to_bytes32(0x74696e0000000000000000000000000000000000000000000000000000000000) &&
                   what != to_bytes32(0x746f757400000000000000000000000000000000000000000000000000000000) &&
                   what != to_bytes32(0x6275660000000000000000000000000000000000000000000000000000000000);
    bool revert4 = (what == to_bytes32(0x74696e0000000000000000000000000000000000000000000000000000000000) ||
                   what == to_bytes32(0x746f757400000000000000000000000000000000000000000000000000000000)) &&
                   to_mathint(data) > WAD();

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting sellGem
rule sellGem(address usr, uint256 gemAmt) {
    env e;

    address anyAddr;

    mathint tin = tin();
    require tin <= WAD();

    address pocket = pocket();
    require pocket != e.msg.sender;
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfUsrBefore = dai.balanceOf(usr);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrBefore = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);
    require gemBalanceOfUsrBefore + gemBalanceOfPocketBefore <= to_mathint(gem.totalSupply());

    mathint gemAmtWad = gemAmt * to18ConversionFactor;
    mathint calcDaiOutWad = gemAmtWad - gemAmtWad * tin / WAD();

    mathint daiOutWad = sellGem(e, usr, gemAmt);

    mathint daiBalanceOfUsrAfter = dai.balanceOf(usr);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrAfter = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfPocketAfter = gem.balanceOf(pocket);

    assert daiOutWad == calcDaiOutWad, "sellGem did not return the expected daiOutWad";
    assert gemBalanceOfUsrAfter == gemBalanceOfUsrBefore - gemAmt, "sellGem did not decrease gem.balanceOf(sender) by gemAmt";
    assert gemBalanceOfPocketAfter == gemBalanceOfPocketBefore + gemAmt, "sellGem did not increase gem.balanceOf(pocket) by gemAmt";
    assert usr != currentContract => daiBalanceOfUsrAfter == daiBalanceOfUsrBefore + daiOutWad, "sellGem did not increase dai.balanceOf(usr) by daiOutWad";
    assert usr != currentContract => daiBalanceOfPsmAfter == daiBalanceOfPsmBefore - daiOutWad, "sellGem did not decrease dai.balanceOf(psm) by daiOutWad";
    assert usr == currentContract => daiBalanceOfUsrAfter == daiBalanceOfUsrBefore, "sellGem did not keep the same dai.balanceOf(usr/psm)";
}

// Verify revert rules on sellGem
rule sellGem_revert(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    mathint tin = tin();
    require tin <= WAD();

    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    require daiBalanceOfPsm + dai.balanceOf(usr) <= to_mathint(dai.totalSupply());
    mathint gemAllowanceSenderPsm = gem.allowance(e.msg.sender, currentContract);
    mathint gemBalanceOfSender = gem.balanceOf(e.msg.sender);
    require gemBalanceOfSender + gem.balanceOf(pocket()) <= to_mathint(gem.totalSupply());

    mathint gemAmtWad = gemAmt * to18ConversionFactor;
    mathint daiOutWad = gemAmtWad - gemAmtWad * tin / WAD();

    sellGem@withrevert(e, usr, gemAmt);

    bool revert1 = e.msg.value > 0;
    bool revert2 = gemAmtWad > max_uint256;
    bool revert3 = gemAmtWad * tin > max_uint256;
    bool revert4 = gemAllowanceSenderPsm < to_mathint(gemAmt);
    bool revert5 = gemBalanceOfSender < to_mathint(gemAmt);
    bool revert6 = daiBalanceOfPsm < daiOutWad;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting sellGemNoFee
rule sellGemNoFee(address usr, uint256 gemAmt) {
    env e;

    address anyAddr;

    address pocket = pocket();
    require pocket != e.msg.sender;
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfUsrBefore = dai.balanceOf(usr);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);
    require gemBalanceOfSenderBefore + gemBalanceOfPocketBefore <= to_mathint(gem.totalSupply());

    mathint calcDaiOutWad = gemAmt * to18ConversionFactor;

    mathint daiOutWad = sellGemNoFee(e, usr, gemAmt);

    mathint daiBalanceOfUsrAfter = dai.balanceOf(usr);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint gemBalanceOfSenderAfter = gem.balanceOf(e.msg.sender);
    mathint gemBalanceOfPocketAfter = gem.balanceOf(pocket);

    assert daiOutWad == calcDaiOutWad, "sellGemNoFee did not return the expected daiOutWad";
    assert gemBalanceOfSenderAfter == gemBalanceOfSenderBefore - gemAmt, "sellGemNoFee did not decrease gem.balanceOf(sender) by gemAmt";
    assert gemBalanceOfPocketAfter == gemBalanceOfPocketBefore + gemAmt, "sellGemNoFee did not increase gem.balanceOf(pocket) by gemAmt";
    assert usr != currentContract => daiBalanceOfUsrAfter == daiBalanceOfUsrBefore + daiOutWad, "sellGemNoFee did not increase dai.balanceOf(usr) by daiOutWad";
    assert usr != currentContract => daiBalanceOfPsmAfter == daiBalanceOfPsmBefore - daiOutWad, "sellGemNoFee did not decrease dai.balanceOf(psm) by daiOutWad";
    assert usr == currentContract => daiBalanceOfUsrAfter == daiBalanceOfUsrBefore, "sellGemNoFee did not keep the same dai.balanceOf(usr/psm)";
}

// Verify revert rules on sellGemNoFee
rule sellGemNoFee_revert(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    mathint budSender = bud(e.msg.sender);

    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    require daiBalanceOfPsm + dai.balanceOf(usr) <= to_mathint(dai.totalSupply());
    mathint gemAllowanceSenderPsm = gem.allowance(e.msg.sender, currentContract);
    mathint gemBalanceOfSender = gem.balanceOf(e.msg.sender);
    require gemBalanceOfSender + gem.balanceOf(pocket()) <= to_mathint(gem.totalSupply());

    mathint daiOutWad = gemAmt * to18ConversionFactor;

    sellGemNoFee@withrevert(e, usr, gemAmt);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budSender != 1;
    bool revert3 = daiOutWad > max_uint256;
    bool revert4 = gemAllowanceSenderPsm < to_mathint(gemAmt);
    bool revert5 = gemBalanceOfSender < to_mathint(gemAmt);
    bool revert6 = daiBalanceOfPsm < daiOutWad;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting buyGem
rule buyGem(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    address anyAddr;

    mathint tout = tout();
    require tout <= WAD();

    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfSenderBefore = dai.balanceOf(e.msg.sender);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrBefore = gem.balanceOf(usr);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);
    require gemBalanceOfUsrBefore + gemBalanceOfPocketBefore <= to_mathint(gem.totalSupply());

    mathint gemAmtWad = gemAmt * to18ConversionFactor;
    mathint calcDaiInWad = gemAmtWad + gemAmtWad * tout / WAD();

    mathint daiInWad = buyGem(e, usr, gemAmt);

    mathint daiBalanceOfSenderAfter = dai.balanceOf(e.msg.sender);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrAfter = gem.balanceOf(usr);
    mathint gemBalanceOfPocketAfter = gem.balanceOf(pocket);

    assert daiInWad == calcDaiInWad, "buyGem did not return the expected daiInWad";
    assert daiBalanceOfSenderAfter == daiBalanceOfSenderBefore - daiInWad, "buyGem did not decrease dai.balanceOf(sender) by daiInWad";
    assert daiBalanceOfPsmAfter == daiBalanceOfPsmBefore + daiInWad, "buyGem did not increase dai.balanceOf(psm) by daiInWad";
    assert usr != pocket => gemBalanceOfUsrAfter == gemBalanceOfUsrBefore + gemAmt, "buyGem did not increase gem.balanceOf(usr) by gemAmt";
    assert usr != pocket => gemBalanceOfPocketAfter == gemBalanceOfPocketBefore - gemAmt, "buyGem did not decrease gem.balanceOf(pocket) by gemAmt";
    assert usr == pocket => gemBalanceOfUsrAfter == gemBalanceOfUsrBefore, "buyGem did not keep unchanged gem.balanceOf(usr/pocket)";
}

// Verify revert rules on buyGem
rule buyGem_revert(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    mathint tout = tout();
    require tout <= WAD();

    mathint to18ConversionFactor = to18ConversionFactor();

    address pocket = pocket();
    require pocket != currentContract;

    mathint daiBalanceOfSender = dai.balanceOf(e.msg.sender);
    require daiBalanceOfSender + dai.balanceOf(currentContract) <= to_mathint(dai.totalSupply());
    mathint daiAllowanceSenderPsm = dai.allowance(e.msg.sender, currentContract);
    mathint gemAllowancePocketPsm = gem.allowance(pocket, currentContract);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    require gemBalanceOfPocket + gem.balanceOf(usr) <= to_mathint(gem.totalSupply());

    mathint gemAmtWad = gemAmt * to18ConversionFactor;
    mathint daiInWad = gemAmtWad + gemAmtWad * tout / WAD();

    buyGem@withrevert(e, usr, gemAmt);

    bool revert1 = e.msg.value > 0;
    bool revert2 = gemAmtWad > max_uint256;
    bool revert3 = gemAmtWad * tout > max_uint256;
    bool revert4 = daiAllowanceSenderPsm < daiInWad;
    bool revert5 = daiBalanceOfSender < daiInWad;
    bool revert6 = gemAllowancePocketPsm < to_mathint(gemAmt);
    bool revert7 = gemBalanceOfPocket < to_mathint(gemAmt);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert revert7 => lastReverted, "revert7 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting buyGemNoFee
rule buyGemNoFee(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    address anyAddr;

    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint daiBalanceOfSenderBefore = dai.balanceOf(e.msg.sender);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrBefore = gem.balanceOf(usr);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);
    require gemBalanceOfUsrBefore + gemBalanceOfPocketBefore <= to_mathint(gem.totalSupply());

    mathint calcDaiInWad = gemAmt * to18ConversionFactor;

    mathint daiInWad = buyGemNoFee(e, usr, gemAmt);

    mathint daiBalanceOfSenderAfter = dai.balanceOf(e.msg.sender);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint gemBalanceOfUsrAfter = gem.balanceOf(usr);
    mathint gemBalanceOfPocketAfter = gem.balanceOf(pocket);

    assert daiInWad == calcDaiInWad, "buyGemNoFee did not return the expected daiInWad";
    assert daiBalanceOfSenderAfter == daiBalanceOfSenderBefore - daiInWad, "buyGemNoFee did not decrease dai.balanceOf(sender) by daiInWad";
    assert daiBalanceOfPsmAfter == daiBalanceOfPsmBefore + daiInWad, "buyGemNoFee did not increase dai.balanceOf(psm) by daiInWad";
    assert usr != pocket => gemBalanceOfUsrAfter == gemBalanceOfUsrBefore + gemAmt, "buyGemNoFee did not increase gem.balanceOf(usr) by gemAmt";
    assert usr != pocket => gemBalanceOfPocketAfter == gemBalanceOfPocketBefore - gemAmt, "buyGemNoFee did not decrease gem.balanceOf(pocket) by gemAmt";
    assert usr == pocket => gemBalanceOfUsrAfter == gemBalanceOfUsrBefore, "buyGemNoFee did not keep unchanged gem.balanceOf(usr/pocket)";
}

// Verify revert rules on buyGemNoFee
rule buyGemNoFee_revert(address usr, uint256 gemAmt) {
    env e;

    require e.msg.sender != currentContract;

    mathint to18ConversionFactor = to18ConversionFactor();

    mathint budSender = bud(e.msg.sender);

    address pocket = pocket();
    require pocket != currentContract;

    mathint daiBalanceOfSender = dai.balanceOf(e.msg.sender);
    require daiBalanceOfSender + dai.balanceOf(currentContract) <= to_mathint(dai.totalSupply());
    mathint daiAllowanceSenderPsm = dai.allowance(e.msg.sender, currentContract);
    mathint gemAllowancePocketPsm = gem.allowance(pocket, currentContract);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    require gemBalanceOfPocket + gem.balanceOf(usr) <= to_mathint(gem.totalSupply());

    mathint daiInWad = gemAmt * to18ConversionFactor;

    buyGemNoFee@withrevert(e, usr, gemAmt);

    bool revert1 = e.msg.value > 0;
    bool revert2 = budSender != 1;
    bool revert3 = daiInWad > max_uint256;
    bool revert4 = daiAllowanceSenderPsm < daiInWad;
    bool revert5 = daiBalanceOfSender < daiInWad;
    bool revert6 = gemAllowancePocketPsm < to_mathint(gemAmt);
    bool revert7 = gemBalanceOfPocket < to_mathint(gemAmt);

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert revert7 => lastReverted, "revert7 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting fill
rule fill() {
    env e;

    address anyAddr;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint vatDebtBefore = vat.debt();
    mathint vatLineBefore = vat.Line();
    mathint vatIlkArtBefore; mathint a; mathint b; mathint vatIlkLineBefore; mathint c;
    vatIlkArtBefore, a, b, vatIlkLineBefore, c = vat.ilks(ilk);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);

    mathint calcWad = min(
                        min(
                            subCap(gemBalanceOfPocketBefore * to18ConversionFactor + buf(), vatIlkArtBefore),
                            subCap(vatIlkLineBefore / RAY(), vatIlkArtBefore)
                        ),
                        subCap(vatLineBefore, vatDebtBefore) / RAY()
                    );

    mathint wad = fill(e);

    mathint vatIlkArtAfter; mathint d;
    vatIlkArtAfter, a, b, c, d = vat.ilks(ilk);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);

    assert wad == calcWad, "fill did not return the expected wad";
    assert vatIlkArtAfter == vatIlkArtBefore + wad, "fill did not increase vat.ilks(ilk).Art by wad";
    assert daiBalanceOfPsmAfter == daiBalanceOfPsmBefore + wad, "fill did not increase dai.balanceOf(psm) by wad";
}

// Verify revert rules on fill
rule fill_revert() {
    env e;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint vatLive = vat.live();
    mathint vatDebt = vat.debt();
    mathint vatLine = vat.Line();
    mathint vatUrnInk; mathint vatUrnArt;
    vatUrnInk, vatUrnArt = vat.urns(ilk, currentContract);
    mathint vatIlkArt; mathint vatIlkRate; mathint vatIlkSpot; mathint vatIlkLine; mathint vatIlkDust;
    vatIlkArt, vatIlkRate, vatIlkSpot, vatIlkLine, vatIlkDust = vat.ilks(ilk);
    require vatUrnArt == vatIlkArt;
    require vatIlkDust == 0;
    mathint daiJoinLive = daiJoin.live();
    mathint vatDaiPsm = vat.dai(currentContract);
    mathint vatDaiDaiJoin = vat.dai(daiJoin);
    mathint vatCanDaiJoinPsm = vat.can(currentContract, daiJoin);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    require dai.wards(daiJoin) == 1;
    mathint daiTotalSupply = dai.totalSupply();
    require daiTotalSupply >= to_mathint(dai.balanceOf(currentContract));

    mathint wad = min(
                        min(
                            subCap(gemBalanceOfPocket * to18ConversionFactor + buf, vatIlkArt),
                            subCap(vatIlkLine / RAY(), vatIlkArt)
                        ),
                        subCap(vatLine, vatDebt) / RAY()
                    );

    fill@withrevert(e);

    bool revert1  = e.msg.value > 0;
    bool revert2  = vatIlkRate != RAY();
    bool revert3  = gemBalanceOfPocket * to18ConversionFactor + buf > max_uint256;
    bool revert4  = wad == 0;
    bool revert5  = vatLive != 1;
    bool revert6  = vatUrnArt + wad > max_uint256;
    bool revert7  = vatIlkArt + wad > max_uint256;
    bool revert8  = wad * RAY() > max_int256();
    bool revert9  = vatDebt + (wad * RAY()) > max_uint256;
    bool revert10 = vatUrnInk * vatIlkSpot > max_uint256;
    bool revert11 = (vatUrnArt + wad) * RAY() > vatUrnInk * vatIlkSpot;
    bool revert12 = vatDaiPsm + wad * RAY() > max_uint256;
    bool revert13 = daiJoinLive != 1;
    bool revert14 = vatCanDaiJoinPsm != 1;
    bool revert15 = vatDaiDaiJoin + (wad * RAY()) > max_uint256;
    bool revert16 = daiTotalSupply + wad > max_uint256;

    assert revert1  => lastReverted, "revert1 failed";
    assert revert2  => lastReverted, "revert2 failed";
    assert revert3  => lastReverted, "revert3 failed";
    assert revert4  => lastReverted, "revert4 failed";
    assert revert5  => lastReverted, "revert5 failed";
    assert revert6  => lastReverted, "revert6 failed";
    assert revert7  => lastReverted, "revert7 failed";
    assert revert8  => lastReverted, "revert8 failed";
    assert revert9  => lastReverted, "revert9 failed";
    assert revert10 => lastReverted, "revert10 failed";
    assert revert11 => lastReverted, "revert11 failed";
    assert revert12 => lastReverted, "revert12 failed";
    assert revert13 => lastReverted, "revert13 failed";
    assert revert14 => lastReverted, "revert14 failed";
    assert revert15 => lastReverted, "revert15 failed";
    assert revert16 => lastReverted, "revert16 failed";
    assert lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11 || revert12 ||
                           revert13 || revert14 || revert15 ||
                           revert16, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting trim
rule trim() {
    env e;

    address anyAddr;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint vatIlkArtBefore; mathint a; mathint b; mathint vatIlkLineBefore; mathint c;
    vatIlkArtBefore, a, b, vatIlkLineBefore, c = vat.ilks(ilk);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);

    mathint calcWad = min(
                        max(
                            subCap(vatIlkArtBefore, gemBalanceOfPocketBefore * to18ConversionFactor + buf()),
                            subCap(vatIlkArtBefore, vatIlkLineBefore / RAY())
                        ),
                        daiBalanceOfPsmBefore
                    );

    mathint wad = trim(e);

    mathint vatIlkArtAfter; mathint d;
    vatIlkArtAfter, a, b, c, d = vat.ilks(ilk);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);

    assert wad == calcWad, "trim did not return the expected wad";
    assert vatIlkArtAfter == vatIlkArtBefore - wad, "trim did not decrease vat.ilks(ilk).Art by wad";
    assert daiBalanceOfPsmAfter == daiBalanceOfPsmBefore - wad, "trim did not decrease dai.balanceOf(psm) by wad";
}

// Verify revert rules on trim
rule trim_revert() {
    env e;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint vatLive = vat.live();
    mathint vatDebt = vat.debt();
    mathint vatLine = vat.Line();
    mathint vatUrnInk; mathint vatUrnArt;
    vatUrnInk, vatUrnArt = vat.urns(ilk, currentContract);
    mathint vatIlkArt; mathint vatIlkRate; mathint vatIlkSpot; mathint vatIlkLine; mathint vatIlkDust;
    vatIlkArt, vatIlkRate, vatIlkSpot, vatIlkLine, vatIlkDust = vat.ilks(ilk);
    require vatIlkSpot == RAY(); // Fix 1:1 price to avoid timeout
    require vatUrnArt == vatIlkArt;
    require vatIlkDust == 0;
    require vatDebt >= vatIlkArt * RAY();
    mathint vatDaiPsm = vat.dai(currentContract);
    mathint vatDaiDaiJoin = vat.dai(daiJoin);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    mathint daiAllowancePsmDaiJoin = dai.allowance(currentContract, daiJoin);
    require to_mathint(dai.totalSupply()) >= daiBalanceOfPsm;

    mathint wad = min(
                        max(
                            subCap(vatIlkArt, gemBalanceOfPocket * to18ConversionFactor + buf),
                            subCap(vatIlkArt, vatIlkLine / RAY())
                        ),
                        daiBalanceOfPsm
                    );

    trim@withrevert(e);

    bool revert1  = e.msg.value > 0;
    bool revert2  = vatIlkRate != RAY();
    bool revert3  = gemBalanceOfPocket * to18ConversionFactor + buf > max_uint256;
    bool revert4  = wad == 0;
    bool revert5  = vatDaiDaiJoin < wad * RAY();
    bool revert6  = vatDaiPsm + wad * RAY() > max_uint256;
    bool revert7  = daiBalanceOfPsm < wad;
    bool revert8  = daiAllowancePsmDaiJoin < wad;
    bool revert9  = vatLive != 1;
    bool revert10 = wad * RAY() > max_int256();
    bool revert11 = vatUrnInk * vatIlkSpot > max_uint256;

    assert revert1  => lastReverted, "revert1 failed";
    assert revert2  => lastReverted, "revert2 failed";
    assert revert3  => lastReverted, "revert3 failed";
    assert revert4  => lastReverted, "revert4 failed";
    assert revert5  => lastReverted, "revert5 failed";
    assert revert6  => lastReverted, "revert6 failed";
    assert revert7  => lastReverted, "revert7 failed";
    assert revert8  => lastReverted, "revert8 failed";
    assert revert9  => lastReverted, "revert9 failed";
    assert revert10 => lastReverted, "revert10 failed";
    assert revert11 => lastReverted, "revert11 failed";
    assert lastReverted => revert1  || revert2  || revert3  ||
                           revert4  || revert5  || revert6  ||
                           revert7  || revert8  || revert9  ||
                           revert10 || revert11, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting chug
rule chug() {
    env e;

    address anyAddr;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint a; mathint vatUrnPsmArt;
    a, vatUrnPsmArt = vat.urns(ilk, currentContract);
    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);
    address vow = vow();
    mathint vatDaiVowBefore = vat.dai(vow);

    mathint calcWad = min(
                        daiBalanceOfPsmBefore,
                        daiBalanceOfPsmBefore + gemBalanceOfPocketBefore * to18ConversionFactor - vatUrnPsmArt
                    );

    mathint wad = chug(e);

    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint vatDaiVowAfter = vat.dai(vow);

    assert wad == calcWad, "chug did not return the expected wad";
    assert daiBalanceOfPsmAfter == daiBalanceOfPsmBefore - wad, "chug did not decrease dai.balanceOf(psm) by wad";
    assert vow != daiJoin => vatDaiVowAfter == vatDaiVowBefore + wad * RAY(), "chug did not increase vat.dai(vow) by wad * RAY";
}

// Verify revert rules on chug
rule chug_revert() {
    env e;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    address vow = vow();

    mathint a; mathint vatUrnPsmArt;
    a, vatUrnPsmArt = vat.urns(ilk, currentContract);
    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    mathint daiAllowancePsmDaiJoin = dai.allowance(currentContract, daiJoin);
    mathint vatDaiDaiJoin = vat.dai(daiJoin);
    mathint vatDaiVow = vat.dai(vow);
    require dai.totalSupply() >= dai.balanceOf(currentContract);

    mathint wad = min(
                        daiBalanceOfPsm,
                        daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor - vatUrnPsmArt
                    );

    chug@withrevert(e);

    bool revert1 = e.msg.value > 0;
    bool revert2 = vow == 0;
    bool revert3 = daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor > max_uint256;
    bool revert4 = daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor - vatUrnPsmArt < 0;
    bool revert5 = wad == 0;
    bool revert6 = daiAllowancePsmDaiJoin < wad;
    bool revert7 = vatDaiDaiJoin < wad * RAY();
    bool revert8 = wad * RAY() > max_uint256;
    bool revert9 = vow != daiJoin && vatDaiVow + wad * RAY() > max_uint256;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert revert3 => lastReverted, "revert3 failed";
    assert revert4 => lastReverted, "revert4 failed";
    assert revert5 => lastReverted, "revert5 failed";
    assert revert6 => lastReverted, "revert6 failed";
    assert revert7 => lastReverted, "revert7 failed";
    assert revert8 => lastReverted, "revert8 failed";
    assert revert9 => lastReverted, "revert9 failed";
    assert lastReverted => revert1 || revert2 || revert3 ||
                           revert4 || revert5 || revert6 ||
                           revert7 || revert8 || revert9, "Revert rules are not covering all the cases";
}

// Verify correct return value comes from rush getter
rule rush() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint vatDebt = vat.debt();
    mathint vatLine = vat.Line();
    mathint vatIlkArt; mathint a; mathint b; mathint vatIlkLine; mathint c;
    vatIlkArt, a, b, vatIlkLine, c = vat.ilks(ilk);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);

    mathint calcWad = min(
                        min(
                            subCap(gemBalanceOfPocket * to18ConversionFactor + buf, vatIlkArt),
                            subCap(vatIlkLine / RAY(), vatIlkArt)
                        ),
                        subCap(vatLine, vatDebt) / RAY()
                    );

    mathint wad = rush();

    assert wad == calcWad, "rush did not return the expected wad";
}

// Verify revert rules on rush getter
rule rush_revert() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint a; mathint vatIlkRate; mathint b; mathint c; mathint d;
    a, vatIlkRate, b, c, d = vat.ilks(ilk);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);

    rush@withrevert();

    bool revert1 = vatIlkRate != RAY();
    bool revert2 = gemBalanceOfPocket * to18ConversionFactor + buf > max_uint256;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct return value comes from gush getter
rule gush() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint vatIlkArt; mathint a; mathint b; mathint vatIlkLine; mathint c;
    vatIlkArt, a, b, vatIlkLine, c = vat.ilks(ilk);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);
    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);

    mathint calcWad = min(
                        max(
                            subCap(vatIlkArt, gemBalanceOfPocket * to18ConversionFactor + buf),
                            subCap(vatIlkArt, vatIlkLine / RAY())
                        ),
                        daiBalanceOfPsm
                    );

    mathint wad = gush();

    assert wad == calcWad, "gush did not return the expected wad";
}

// Verify revert rules on gush getter
rule gush_revert() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();
    mathint buf = buf();

    mathint a; mathint vatIlkRate; mathint b; mathint c; mathint d;
    a, vatIlkRate, b, c, d = vat.ilks(ilk);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);

    gush@withrevert();

    bool revert1 = vatIlkRate != RAY();
    bool revert2 = gemBalanceOfPocket * to18ConversionFactor + buf > max_uint256;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct return value comes from cut getter
rule cut() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint a; mathint vatUrnPsmArt;
    a, vatUrnPsmArt = vat.urns(ilk, currentContract);
    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);

    mathint calcWad = min(
                        daiBalanceOfPsm,
                        daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor - vatUrnPsmArt
                    );

    mathint wad = cut();

    assert wad == calcWad, "cut did not return the expected wad";
}

// Verify revert rules on cut getter
rule cut_revert() {
    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint a; mathint vatUrnPsmArt;
    a, vatUrnPsmArt = vat.urns(ilk, currentContract);
    mathint daiBalanceOfPsm = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocket = gem.balanceOf(pocket);

    cut@withrevert();

    bool revert1 = daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor > max_uint256;
    bool revert2 = daiBalanceOfPsm + gemBalanceOfPocket * to18ConversionFactor - vatUrnPsmArt < 0;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify assets (dai + gem) is always greater or equal to the Art
// This could be an invariant but is replaced with a rule for easier synthax
rule assetsGreaterOrEqualArt(method f) {
    env e;

    bytes32 ilk = ilk();
    address pocket = pocket();
    mathint to18ConversionFactor = to18ConversionFactor();

    mathint aBefore; mathint vatUrnPsmArtBefore;
    aBefore, vatUrnPsmArtBefore = vat.urns(ilk, currentContract);

    mathint daiBalanceOfPsmBefore = dai.balanceOf(currentContract);
    mathint daiBalanceOfSenderBefore = dai.balanceOf(e.msg.sender);
    
    mathint gemBalanceOfPocketBefore = gem.balanceOf(pocket);  
    mathint gemBalanceOfSenderBefore = gem.balanceOf(e.msg.sender);

    mathint tinBefore = tin();
    mathint toutBefore = tout();

    require e.msg.sender != currentContract;
    require e.msg.sender != pocket;

    require daiBalanceOfSenderBefore + daiBalanceOfPsmBefore <= to_mathint(dai.totalSupply());
    require gemBalanceOfSenderBefore + gemBalanceOfPocketBefore <= to_mathint(gem.totalSupply());

    require tinBefore <= WAD();
    require toutBefore <= WAD();

    // require invariant holds before
    require daiBalanceOfPsmBefore + gemBalanceOfPocketBefore * to18ConversionFactor >= vatUrnPsmArtBefore;

    calldataarg arg;
    f(e, arg);

    mathint aAfter; mathint vatUrnPsmArtAfter;
    aAfter, vatUrnPsmArtAfter = vat.urns(ilk, currentContract);
    mathint daiBalanceOfPsmAfter = dai.balanceOf(currentContract);
    mathint gemBalanceOfPocketAfter = gem.balanceOf(pocket);

    // assert invariant holds after
    assert daiBalanceOfPsmAfter + gemBalanceOfPocketAfter * to18ConversionFactor >= vatUrnPsmArtAfter;
}
