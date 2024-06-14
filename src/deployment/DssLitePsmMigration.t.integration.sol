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
import {DssLitePsmDeploy, DssLitePsmDeployParams} from "./DssLitePsmDeploy.sol";
import {DssLitePsmInstance} from "./DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "./DssLitePsmInit.sol";
import {DssLitePsmMigration, MigrationConfig, MigrationResult} from "./DssLitePsmMigration.sol";

interface DssPsmLike {
    function gemJoin() external view returns (address);
}

interface DssLitePsmLike {
    function buf() external view returns (uint256);
    function file(bytes32, uint256) external;
    function fill() external;
    function rush() external view returns (uint256);
    function to18ConversionFactor() external view returns (uint256);
}

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface GemLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract MigrationCaller {
    function migrate(DssInstance memory dss, MigrationConfig memory cfg) external returns (MigrationResult memory) {
        return DssLitePsmMigration.migrate(dss, cfg);
    }
}

contract DssLitePsmMigrationTest is DssTest {
    using MCD for DssInstance;

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
    DssLitePsmInstance inst;
    DssLitePsmInitConfig initCfg;
    MigrationConfig migCfg;
    DssLitePsmLike dstPsm;
    GemLike gem;
    address pocket;
    address pip;
    InitCaller initCaller;
    MigrationCaller migCaller;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);
        dss.giveAdminAccess(address(this));

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        chief = dss.chainlog.getAddress("MCD_ADM");
        srcPsm = DssPsmLike(dss.chainlog.getAddress(SRC_PSM_KEY));
        gem = GemLike(dss.chainlog.getAddress(GEM_KEY));
        pocket = makeAddr("Pocket");
        pip = dss.chainlog.getAddress("PIP_USDC");

        initCaller = new InitCaller();
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

        initCfg = DssLitePsmInitConfig({
            psmKey: DST_PSM_KEY,
            psmMomKey: PSM_MOM_KEY,
            pocketKey: DST_POCKET_KEY,
            pip: pip,
            ilk: DST_ILK,
            pocket: pocket,
            gem: address(gem)
        });

        migCfg = MigrationConfig({
            srcPsmKey: SRC_PSM_KEY,
            dstPsmKey: DST_PSM_KEY,
            srcKeep: 200_000_000 * WAD,
            dstWant: 10_000_000 * WAD
        });

        // Simulate a spell casting for initialization
        vm.prank(pause);
        pauseProxy.exec(address(initCaller), abi.encodeCall(initCaller.init, (dss, inst, initCfg)));

        // Set non-zero parameters
        vm.startPrank(address(pauseProxy));
        dss.vat.file(DST_ILK, "line", 200_000_000 * RAD);
        dss.vat.file("Line", dss.vat.Line() + 200_000_000 * RAD);
        dstPsm.file("buf", 50_000_000 * WAD);
        dstPsm.file("tin", 0.01 ether);
        dstPsm.file("tout", 0.01 ether);
        dstPsm.fill();
        vm.stopPrank();

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
        vm.label(address(srcPsm), "PsmUsdc");
        vm.label(inst.litePsm, "LitePsm");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
    }

    struct TestSrcParams {
        uint256 ink;
        uint256 art;
        uint256 gemBalance;
    }

    struct TestDstParams {
        uint256 buf;
        uint256 art;
        uint256 line;
        uint256 gemBalance;
        uint256 daiBalance;
    }

    struct TestPauseProxyParams {
        uint256 daiBalance; // [wad]
        uint256 vatDaiBalance; // [rad]
        uint256 vatSin; // [rad]
    }

    function testLitePsmMigration_Fuzz(uint256 srcKeep, uint256 dstWant) public {
        // Remove potential rounding issues.
        uint256 to18CF = dstPsm.to18ConversionFactor();
        srcKeep = (srcKeep / to18CF) * to18CF;
        dstWant = (dstWant / to18CF) * to18CF;
        // Overwrite config with the fuzz parameters
        migCfg.srcKeep = srcKeep;
        migCfg.dstWant = dstWant;

        TestSrcParams memory psrc;
        (psrc.ink, psrc.art) = dss.vat.urns(SRC_ILK, address(srcPsm));
        psrc.gemBalance = gem.balanceOf(srcPsm.gemJoin());

        TestDstParams memory pdst;
        (, pdst.art) = dss.vat.urns(DST_ILK, address(dstPsm));
        (,,, pdst.line,) = dss.vat.ilks(DST_ILK);
        pdst.buf = dstPsm.buf();
        pdst.gemBalance = gem.balanceOf(address(pocket));
        pdst.daiBalance = dss.dai.balanceOf(address(dstPsm));

        TestPauseProxyParams memory ppp;
        ppp.daiBalance = dss.dai.balanceOf(address(pauseProxy));
        ppp.vatDaiBalance = dss.vat.dai(address(pauseProxy));
        ppp.vatSin = dss.vat.sin(address(pauseProxy));

        uint256 pglobalLine = dss.vat.Line();
        uint256 expectedSap = _min(migCfg.dstWant, _subcap(psrc.ink, migCfg.srcKeep));

        // Simulate a spell casting for migration
        vm.prank(pause);
        bytes memory out = pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate, (dss, migCfg)));
        (MigrationResult memory res) = abi.decode(out, (MigrationResult));

        // Check results
        assertEq(res.srcPsm, address(srcPsm), "res: invalid src psm");
        assertEq(res.srcIlk, SRC_ILK, "res: invalid src ilk");
        assertEq(res.dstPsm, address(dstPsm), "res: invalid dst psm");
        assertEq(res.dstIlk, DST_ILK, "res: invalid dst ilk");
        assertEq(res.sap, expectedSap, "res: invalid moved amount");

        assertEq(dss.vat.Line(), pglobalLine, "after: unexpected global line change");

        // PauseProxy state should not have changed
        assertEq(
            dss.dai.balanceOf(address(pauseProxy)), ppp.daiBalance, "after: unexpected pauseProxy dai balance change"
        );
        assertEq(
            dss.vat.dai(address(pauseProxy)), ppp.vatDaiBalance, "after: unexpected pauseProxy vat dai balance change"
        );
        assertEq(dss.vat.sin(address(pauseProxy)), ppp.vatSin, "after: unexpected pauseProxy vat sin change");

        // Old PSM state was properly updated
        (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        assertEq(srcInk, psrc.ink - expectedSap, "after: invalid src ink");
        assertEq(srcArt, _subcap(psrc.art, expectedSap), "after: invalid src art");
        assertEq(
            _amtToWad(gem.balanceOf(srcPsm.gemJoin())),
            _amtToWad(psrc.gemBalance) - expectedSap,
            "after: invalid src gem balance"
        );

        // New PSM state was properly updated
        (, uint256 dstArt) = dss.vat.urns(DST_ILK, address(dstPsm));
        assertEq(dstArt, pdst.art + _subcap(expectedSap, pdst.daiBalance), "after: invalid dst art");
        (,,, uint256 dstIlkLine,) = dss.vat.ilks(DST_ILK);
        assertEq(dstIlkLine, pdst.line, "after: unexpected ilk line change");
        assertEq(dstPsm.buf(), pdst.buf, "after: unexpected buf change");
        // assertEq(dstPsm.rush(), 0, "after: dst psm not filled");
        assertEq(
            _amtToWad(gem.balanceOf(pocket)),
            _amtToWad(pdst.gemBalance) + expectedSap,
            "after: invalid dst gem balance in pocket"
        );
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
}
