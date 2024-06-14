// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import {DssLitePsmDeploy, DssLitePsmDeployParams} from "../DssLitePsmDeploy.sol";
import {DssLitePsmInstance} from "../DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "../DssLitePsmInit.sol";
import {DssLitePsmMigration} from "../DssLitePsmMigration.sol";
import {DssLitePsmMigrationPhase1, DssLitePsmMigrationConfigPhase1} from "../phase-1/DssLitePsmMigrationPhase1.sol";
import {DssLitePsmMigrationPhase2, DssLitePsmMigrationConfigPhase2} from "./DssLitePsmMigrationPhase2.sol";

interface DssPsmLike {
    function buyGem(address, uint256) external;
    function gemJoin() external view returns (address);
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
    function vow() external view returns (address);
}

interface DssLitePsmLike {
    function buf() external view returns (uint256);
    function buyGem(address, uint256) external returns (uint256);
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function pocket() external view returns (address);
    function rush() external view returns (uint256);
    function sellGem(address, uint256) external returns (uint256);
    function tin() external view returns (uint256);
    function to18ConversionFactor() external view returns (uint256);
    function tout() external view returns (uint256);
    function trim() external returns (uint256);
    function vow() external view returns (address);
}

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
}

interface GemLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

contract MigrationCaller {
    function initAndMigrate1(
        DssInstance memory dss,
        DssLitePsmInstance memory inst,
        DssLitePsmMigrationConfigPhase1 memory cfg
    ) external {
        DssLitePsmMigrationPhase1.initAndMigrate(dss, inst, cfg);
    }

    function migrate2(DssInstance memory dss, DssLitePsmMigrationConfigPhase2 memory cfg) external {
        DssLitePsmMigrationPhase2.migrate(dss, cfg);
    }
}

contract DssLitePsmMigrationPhase2Test is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 constant SRC_ILK = "PSM-USDC-A";
    bytes32 constant SRC_PSM_KEY = "MCD_PSM_USDC_A";

    DssInstance dss;
    address pause;
    address vow;
    DssPsmLike srcPsm;
    address chief;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsmInstance inst;
    DssLitePsmLike dstPsm;
    GemLike gem;
    address pocket;
    address pip;
    MigrationCaller migCaller;
    DssLitePsmMigrationConfigPhase1 mig1Cfg;
    DssLitePsmMigrationConfigPhase2 mig2Cfg;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        chief = dss.chainlog.getAddress("MCD_ADM");
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        srcPsm = DssPsmLike(dss.chainlog.getAddress(SRC_PSM_KEY));
        gem = GemLike(dss.chainlog.getAddress(GEM_KEY));
        pocket = makeAddr("Pocket");
        pip = dss.chainlog.getAddress("PIP_USDC");

        migCaller = new MigrationCaller();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                ilk: DST_ILK,
                gem: address(gem),
                daiJoin: address(dss.daiJoin),
                pocket: pocket
            })
        );

        dstPsm = DssLitePsmLike(inst.litePsm);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        mig1Cfg = DssLitePsmMigrationConfigPhase1({
            psmMomKey: PSM_MOM_KEY,
            dstPsmKey: DST_PSM_KEY,
            dstPocketKey: DST_POCKET_KEY,
            dstPip: pip,
            dstIlk: DST_ILK,
            dstGem: address(gem),
            dstPocket: pocket,
            dstTin: 0,
            dstTout: 0,
            dstBuf: 20_000_000 * WAD,
            dstMaxLine: 50_000_000 * RAD,
            dstGap: 20_000_000 * RAD,
            dstTtl: 12 hours,
            dstWant: 10_000_000 * WAD,
            srcPsmKey: SRC_PSM_KEY,
            srcKeep: 0 * WAD,
            srcMaxLine: 10_000_000_000 * RAD,
            srcGap: 350_000_000 * RAD,
            srcTtl: 12 hours
        });

        mig2Cfg = DssLitePsmMigrationConfigPhase2({
            dstPsmKey: DST_PSM_KEY,
            dstTin: 0,
            dstTout: 0,
            dstBuf: 300_000_000 * WAD,
            dstMaxLine: 7_500_000_000 * RAD,
            dstGap: 300_000_000 * RAD,
            dstTtl: 12 hours,
            dstWant: type(uint256).max,
            srcPsmKey: SRC_PSM_KEY,
            srcKeep: 100_000_000 * WAD,
            srcTin: 0.001 ether,
            srcTout: 0.001 ether,
            srcMaxLine: 2_500_000_000 * RAD,
            srcGap: 100_000_000 * RAD,
            srcTtl: 12 hours
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(address(pause), "Pause");
        vm.label(vow, "Vow");
        vm.label(address(gem), "USDC");
        vm.label(address(srcPsm), "PsmUsdc");
        vm.label(inst.litePsm, "LitePsm");
        vm.label(DssLitePsmLike(inst.litePsm).pocket(), "Pocket");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(address(autoLine), "AutoLine");

        // Simulate a spell casting for migration
        vm.prank(address(pause));
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.initAndMigrate1, (dss, inst, mig1Cfg)));
    }

    /**
     * @dev No state change happens after migration phase 1.
     */
    function testMigrationPhase2BaseCase() public {
        this._checkMigrationPhase2();
    }

    /**
     * @dev `line` for `dstPsm` reaches the max value defined by phase 1.
     */
    function testMigrationPhase2WhenDstLineIsMax() public {
        vm.startPrank(address(pauseProxy));
        dss.vat.file("Line", dss.vat.Line() + mig1Cfg.dstMaxLine);
        dss.vat.file(DST_ILK, "line", mig1Cfg.dstMaxLine);
        vm.stopPrank();

        _checkMigrationPhase2();
    }

    /**
     * @dev `dstPsm` has no debt.
     */
    function testMigrationPhase2WhenDstArtIsZero() public {
        vm.startPrank(address(pauseProxy));
        // Need to set buf to 0 to be able to wipe all debt.
        dstPsm.file("buf", 0);
        vm.stopPrank();

        // Buy all gems from `dstPsm`
        uint256 dstGemBalanceAmt = gem.balanceOf(address(pocket));
        deal(address(dss.dai), address(this), _amtToWad(dstGemBalanceAmt));
        dss.dai.approve(address(dstPsm), _amtToWad(dstGemBalanceAmt));
        dstPsm.buyGem(address(this), dstGemBalanceAmt);
        // Wipe all debt
        dstPsm.trim();

        // Sanity check
        (, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        assertEq(pdstArt, 0);

        _checkMigrationPhase2();
    }

    /**
     * @dev `dstPsm` debt is maxxed out
     */
    function testMigrationPhase2WhenArtIsMaxxedOut() public {
        vm.startPrank(address(pauseProxy));
        dss.vat.file("Line", dss.vat.Line() + mig1Cfg.dstMaxLine);
        dss.vat.file(DST_ILK, "line", mig1Cfg.dstMaxLine);
        vm.stopPrank();

        gem.approve(address(dstPsm), type(uint256).max);
        do {
            if (dstPsm.rush() > 0) dstPsm.fill();
            uint256 dstGemAmt = _wadToAmt(dss.dai.balanceOf(address(dstPsm)));
            deal(address(gem), address(this), dstGemAmt);
            dstPsm.sellGem(address(this), dstGemAmt);
        } while (dstPsm.rush() > 0);

        // Sanity check
        (, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        assertEq(pdstArt, mig1Cfg.dstMaxLine / RAY);

        _checkMigrationPhase2();
    }

    /**
     * @dev The spell reverts if `srcInk` is lower than `srcKeep`.
     */
    function testRevertMigrationPhase2WhenSrcInkLowerThanSrcKeep_Fuzz(uint256 deficit) public {
        deficit = bound(deficit, 1 * WAD, mig2Cfg.srcKeep);

        (uint256 psrcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 buyWad = psrcInk - mig2Cfg.srcKeep + deficit;
        deal(address(dss.dai), address(this), buyWad);
        assertGe(dss.dai.balanceOf(address(this)), buyWad);
        dss.dai.approve(address(srcPsm), buyWad);
        srcPsm.buyGem(address(this), _wadToAmt(buyWad));

        // `vm.expectRevert` only works properly here if we use the CALL opcode.
        vm.expectRevert("ds-pause-delegatecall-error");
        this._checkMigrationPhase2();
    }

    /**
     * @dev Performs the migration and the relevant checks.
     *      It needs to be `public` to work with `vm.expectRevert`.
     */
    function _checkMigrationPhase2() public {
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 psrcVatGem = dss.vat.gem(SRC_ILK, address(srcPsm));
        uint256 psrcGemBalance = gem.balanceOf(address(srcPsm.gemJoin()));
        (uint256 pdstInk, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        uint256 pdstVatGem = dss.vat.gem(DST_ILK, address(dstPsm));
        uint256 pdstGemBalance = gem.balanceOf(address(pocket));

        uint256 expectedMoveWad = _min(psrcInk, _min(mig2Cfg.dstWant, _subcap(psrcInk, mig2Cfg.srcKeep)));

        // Simulate a spell casting for migration
        vm.prank(address(pause));
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate2, (dss, mig2Cfg)));

        // Sanity checks
        assertEq(srcPsm.tin(), mig2Cfg.srcTin, "after: invalid src tin");
        assertEq(srcPsm.tout(), mig2Cfg.srcTout, "after: invalid src tout");
        assertEq(srcPsm.vow(), vow, "after: unexpected src vow update");

        assertEq(dstPsm.tin(), mig2Cfg.dstTin, "after: invalid dst tin");
        assertEq(dstPsm.tout(), mig2Cfg.dstTout, "after: invalid dst tout");
        assertEq(dstPsm.buf(), mig2Cfg.dstBuf, "after: invalid dst buf");
        assertEq(dstPsm.vow(), vow, "after: unexpected dst vow update");

        // Old PSM state is set correctly
        {
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, psrcInk - expectedMoveWad, "after: src ink is not decreased by the moved amount");
            assertGe(srcInk, mig2Cfg.srcKeep, "after: src ink is lower than src keep");
            assertEq(srcArt, psrcArt - expectedMoveWad, "after: src art is not decreased by the moved amount");
            assertEq(dss.vat.gem(SRC_ILK, address(srcPsm)), psrcVatGem, "after: unexpected src vat gem change");
            assertEq(
                _amtToWad(gem.balanceOf(address(srcPsm.gemJoin()))),
                _amtToWad(psrcGemBalance) - expectedMoveWad,
                "after: invalid gem balance for src pocket"
            );
        }

        // Old PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last,) = autoLine.ilks(SRC_ILK);
            assertEq(maxLine, mig2Cfg.srcMaxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, mig2Cfg.srcGap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(mig2Cfg.srcTtl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
        }

        // New PSM state is set correctly
        {
            // LitePSM ink is never modified
            (uint256 dstInk, uint256 dstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
            assertEq(dstInk, pdstInk, "after: unexpected dst ink chagne");
            // There might be extra `art` because of the calls to `fill`.
            assertGe(dstArt, pdstArt + expectedMoveWad, "after: dst art is not increased at least by the moved amount");
            assertEq(dss.dai.balanceOf(address(dstPsm)), mig2Cfg.dstBuf, "after: invalid dst psm dai balance");
            assertEq(dss.vat.gem(DST_ILK, address(dstPsm)), pdstVatGem, "after: unexpected dst vat gem change");
            assertEq(
                _amtToWad(gem.balanceOf(address(pocket))),
                _amtToWad(pdstGemBalance) + expectedMoveWad,
                "after: invalid gem balance for dst pocket"
            );
        }

        // New PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, mig2Cfg.dstMaxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, mig2Cfg.dstGap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(mig2Cfg.dstTtl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function _subcap(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? 0 : x - y;
    }

    function _amtToWad(uint256 amt) internal view returns (uint256) {
        return amt * dstPsm.to18ConversionFactor();
    }

    function _wadToAmt(uint256 wad) internal view returns (uint256) {
        return wad / dstPsm.to18ConversionFactor();
    }
}
