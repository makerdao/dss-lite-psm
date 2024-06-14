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
import {DssLitePsmMigrationPhase2, DssLitePsmMigrationConfigPhase2} from "../phase-2/DssLitePsmMigrationPhase2.sol";
import {DssLitePsmMigrationPhase3, DssLitePsmMigrationConfigPhase3} from "./DssLitePsmMigrationPhase3.sol";

interface DssPsmLike {
    function buyGem(address, uint256) external;
    function file(bytes32, uint256) external;
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

    function migrate3(DssInstance memory dss, DssLitePsmMigrationConfigPhase3 memory cfg) external {
        DssLitePsmMigrationPhase3.migrate(dss, cfg);
    }
}

contract DssLitePsmMigrationPhase3Test is DssTest {
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
    DssLitePsmMigrationConfigPhase3 mig3Cfg;

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
            srcTin: 0.01 ether,
            srcTout: 0.01 ether,
            srcMaxLine: 2_500_000_000 * RAD,
            srcGap: 100_000_000 * RAD,
            srcTtl: 12 hours
        });

        mig3Cfg = DssLitePsmMigrationConfigPhase3({
            dstPsmKey: DST_PSM_KEY,
            dstTin: 0,
            dstTout: 0,
            dstBuf: 400_000_000 * WAD,
            dstMaxLine: 10_000_000_000 * RAD,
            dstGap: 400_000_000 * RAD,
            dstTtl: 12 hours,
            srcPsmKey: SRC_PSM_KEY
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
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
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.initAndMigrate1, (dss, inst, mig1Cfg)));
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate2, (dss, mig2Cfg)));
    }

    /**
     * @dev No state change happens after migration phase 2.
     */
    function testMigrationPhase3BaseCase() public {
        _checkMigrationPhase3();
    }

    /**
     * @dev `line` for `dstPsm` reaches the max value defined by phase 1.
     */
    function testMigrationPhase3WhenSrcIsEmpty() public {
        vm.startPrank(address(pauseProxy));
        // Set `tout` to zero to make the calculation easier.
        srcPsm.file("tout", 0);
        vm.stopPrank();

        (uint256 ppsrcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 srcGemBalanceAmt = _wadToAmt(ppsrcInk);
        deal(address(dss.dai), address(this), ppsrcInk);
        dss.dai.approve(address(srcPsm), ppsrcInk);
        srcPsm.buyGem(address(this), srcGemBalanceAmt);

        // Sanity check
        (uint256 psrcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
        assertEq(psrcInk, 0);

        _checkMigrationPhase3();
    }

    /**
     * @dev `line` for `dstPsm` reaches the max value defined by phase 2.
     */
    function testMigrationPhase3WhenDstLineIsMax() public {
        vm.startPrank(address(pauseProxy));
        dss.vat.file("Line", dss.vat.Line() + mig2Cfg.dstMaxLine);
        dss.vat.file(DST_ILK, "line", mig2Cfg.dstMaxLine);
        vm.stopPrank();

        _checkMigrationPhase3();
    }

    /**
     * @dev `dstPsm` has no debt.
     */
    function testMigrationPhase3WhenDstArtIsZero() public {
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

        _checkMigrationPhase3();
    }

    /**
     * @dev `dstPsm` debt is maxxed out
     */
    function testMigrationPhase3WhenArtIsMaxxedOut() public {
        vm.startPrank(address(pauseProxy));
        dss.vat.file("Line", dss.vat.Line() + mig2Cfg.dstMaxLine);
        dss.vat.file(DST_ILK, "line", mig2Cfg.dstMaxLine);
        vm.stopPrank();

        gem.approve(address(dstPsm), type(uint256).max);
        // Sell gems into `dstPsm` until it is completely full
        do {
            if (dstPsm.rush() > 0) dstPsm.fill();
            uint256 dstGemAmt = _wadToAmt(dss.dai.balanceOf(address(dstPsm)));
            deal(address(gem), address(this), dstGemAmt);
            dstPsm.sellGem(address(this), dstGemAmt);
        } while (dstPsm.rush() > 0);

        // Sanity check
        (, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        assertEq(pdstArt, mig2Cfg.dstMaxLine / RAY);

        _checkMigrationPhase3();
    }

    /**
     * @dev Performs the migration and the relevant checks.
     */
    function _checkMigrationPhase3() internal {
        (uint256 psrcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 psrcVatGem = dss.vat.gem(SRC_ILK, address(srcPsm));
        uint256 psrcGemBalance = gem.balanceOf(address(srcPsm.gemJoin()));
        (uint256 pdstInk, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        uint256 pdstVatGem = dss.vat.gem(DST_ILK, address(dstPsm));
        uint256 pdstGemBalance = gem.balanceOf(address(pocket));

        uint256 expectedMoveWad = psrcInk;

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate3, (dss, mig3Cfg)));

        // Sanity checks
        assertEq(srcPsm.tin(), 0, "after: invalid src tin");
        assertEq(srcPsm.tout(), 0, "after: invalid src tout");
        assertEq(srcPsm.vow(), vow, "after: invalid src vow update");

        assertEq(dstPsm.tin(), mig3Cfg.dstTin, "after: invalid dst tin");
        assertEq(dstPsm.tout(), mig3Cfg.dstTout, "after: invalid dst tout");
        assertEq(dstPsm.buf(), mig3Cfg.dstBuf, "after: invalid dst buf");
        assertEq(dstPsm.vow(), vow, "after: invalid dst vow update");

        // Old PSM state is cleared correctly.
        {
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, 0, "after: src ink is not zero");
            assertEq(srcArt, 0, "after: src art is not zero");
            assertEq(dss.vat.gem(SRC_ILK, address(srcPsm)), psrcVatGem, "after: unexpected src vat gem change");
            assertEq(
                _amtToWad(gem.balanceOf(address(srcPsm.gemJoin()))),
                _amtToWad(psrcGemBalance) - expectedMoveWad,
                "after: invalid gem balance for src pocket"
            );
        }

        // Old PSM is properly removed from AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(SRC_ILK);
            assertEq(maxLine, 0, "after: src AutoLine maxLine is not zero");
            assertEq(gap, 0, "after: src AutoLine gap is not zero");
            assertEq(ttl, 0, "after: src AutoLine ttl is not zero");
            assertEq(last, 0, "after: src AutoLine invalid last");
            assertEq(lastInc, 0, "after: src AutoLine invalid lastInc");
        }

        // New PSM state is set correctly
        {
            // LitePSM ink is never modified
            (uint256 dstInk, uint256 dstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
            assertEq(dstInk, pdstInk, "after: unexpected dst ink chagne");
            // There might be extra `art` because of the calls to `fill`.
            assertGe(dstArt, pdstArt, "after: dst art is not increased at least by the moved amount");
            assertGe(dss.dai.balanceOf(address(dstPsm)), mig3Cfg.dstBuf, "after: invalid dst psm dai balance");
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
            assertEq(maxLine, mig3Cfg.dstMaxLine, "after: dst AutoLine invalid maxLine");
            assertEq(gap, mig3Cfg.dstGap, "after: dst AutoLine invalid gap");
            assertEq(ttl, uint48(mig3Cfg.dstTtl), "after: dst AutoLine invalid ttl");
            assertEq(last, block.number, "after: dst AutoLine invalid last");
            // Depending on the actual debt existing in `dstPsm`, AutoLine might not increase the line right the way.
            assertTrue(lastInc == block.timestamp || lastInc == 0, "after: dst AutoLine invalid lastInc");
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

    function _wadToAmt(uint256 amt) internal view returns (uint256) {
        return amt / dstPsm.to18ConversionFactor();
    }
}
