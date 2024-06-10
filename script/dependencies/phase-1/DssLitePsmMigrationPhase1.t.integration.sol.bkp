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
import {DssLitePsmMigrationPhase1, DssLitePsmMigrationConfigPhase1} from "./DssLitePsmMigrationPhase1.sol";

interface DssPsmLike {
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
    function vow() external view returns (address);
}

interface DssLitePsmLike is DssPsmLike {
    function buf() external view returns (uint256);
}

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
    function exec(bytes32) external;
}

interface IlkRegistryLike {
    function info(bytes32 ilk)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint256 class,
            uint256 dec,
            address gem,
            address pip,
            address join,
            address xlip
        );
}

interface GemLike {
    function approve(address, uint256) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract MigrationCaller {
    function initAndMigrate(
        DssInstance memory dss,
        DssLitePsmInstance memory inst,
        DssLitePsmMigrationConfigPhase1 memory cfg
    ) external {
        DssLitePsmMigrationPhase1.initAndMigrate(dss, inst, cfg);
    }
}

contract DssLitePsmMigrationPhase1Test is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 constant SRC_ILK = "PSM-USDC-A";
    bytes32 constant SRC_PSM_KEY = "MCD_PSM_USDC_A";
    uint256 constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    DssInstance dss;
    address pause;
    address vow;
    DssPsmLike srcPsm;
    address chief;
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsmInstance inst;
    DssLitePsmLike litePsm;
    GemLike gem;
    address pocket;
    address pip;
    MigrationCaller migCaller;
    DssLitePsmMigrationConfigPhase1 migCfg;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
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

        litePsm = DssLitePsmLike(inst.litePsm);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        migCfg = DssLitePsmMigrationConfigPhase1({
            psmMomKey: PSM_MOM_KEY,
            dstPip: pip,
            dstPsmKey: DST_PSM_KEY,
            dstPocketKey: DST_POCKET_KEY,
            dstTin: 0.025 ether,
            dstTout: 0.025 ether,
            dstBuf: 50_000_000 * WAD,
            dstGap: 50_000_000 * RAD,
            dstMaxLine: 50_000_000 * RAD,
            dstTtl: 12 hours,
            dstWant: 10_000_000 * WAD,
            srcPsmKey: SRC_PSM_KEY,
            srcMaxLine: 2_500_000_000 * RAD,
            srcGap: 100_000_000 * RAD,
            srcTtl: 12 hours
        });

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
        vm.label(address(autoLine), "AutoLine");
    }

    function testMigrationPhase1() public {
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 psrcTin = srcPsm.tin();
        uint256 psrcTout = srcPsm.tout();
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.initAndMigrate, (dss, inst, migCfg)));

        // Sanity checks
        {
            assertEq(srcPsm.tin(), psrcTin, "after: invalid src tin update");
            assertEq(srcPsm.tout(), psrcTout, "after: invalid src tout update");
            assertEq(srcPsm.vow(), vow, "after: invalid src vow update");

            assertEq(litePsm.tin(), migCfg.dstTin, "after: invalid dst tin");
            assertEq(litePsm.tout(), migCfg.dstTout, "after: invalid dst tout");
            assertEq(litePsm.buf(), migCfg.dstBuf, "after: invalid dst buf");
            assertEq(litePsm.vow(), vow, "after: invalid dst vow update");
        }

        // Old PSM ink is decreased by the correct amount
        {
            (uint256 srcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, psrcInk - migCfg.dstWant, "after: src ink is not decreased by want");
        }

        // Old PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last,) = autoLine.ilks(SRC_ILK);
            assertEq(maxLine, migCfg.srcMaxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, migCfg.srcGap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(migCfg.srcTtl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
        }

        // New PSM info is added to IlkRegistry
        {
            (
                string memory name,
                string memory symbol,
                uint256 _class,
                uint256 decimals,
                address _gem,
                address _pip,
                address gemJoin,
                address clip
            ) = reg.info(DST_ILK);

            assertEq(name, gem.name(), "after: reg name mismatch");
            assertEq(symbol, gem.symbol(), "after: reg symbol mismatch");
            assertEq(_class, REG_CLASS_JOINLESS, "after: reg class mismatch");
            assertEq(decimals, gem.decimals(), "after: reg dec mismatch");
            assertEq(_gem, address(gem), "after: reg gem mismatch");
            assertEq(_pip, pip, "after: reg pip mismatch");
            assertEq(gemJoin, address(0), "after: invalid reg gemJoin");
            assertEq(clip, address(0), "after: invalid reg xlip");
        }

        // New PSM: `litePsm`, `mom` and `pocket` are present in Chainlog
        {
            assertEq(dss.chainlog.getAddress(migCfg.psmMomKey), inst.mom, "after: `mom` not in chainlog");
            assertEq(dss.chainlog.getAddress(migCfg.dstPsmKey), inst.litePsm, "after: `litePsm` not in chainlog");
            assertEq(dss.chainlog.getAddress(migCfg.dstPocketKey), pocket, "after: `pocket` not in chainlog");
        }

        // New PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, migCfg.dstMaxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, migCfg.dstGap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(migCfg.dstTtl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }
    }
}
