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
import {DssLitePsm} from "src/DssLitePsm.sol";
import {DssLitePsmMom} from "src/DssLitePsmMom.sol";
import {DssLitePsmDeploy, DssLitePsmDeployParams} from "../phase-1/DssLitePsmDeploy.sol";
import {DssLitePsmInstance} from "../phase-1/DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "../phase-1/DssLitePsmInit.sol";
import {DssLitePsmMigrationPhase3, DssLitePsmMigrationPhase3Config} from "../phase-3/DssLitePsmMigrationPhase3.sol";

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
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
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract MigrationCaller {
    function migrate(DssInstance memory dss, DssLitePsmMigrationPhase3Config memory cfg) external {
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
    uint256 constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    DssInstance dss;
    address pause;
    address vow;
    address srcPsm;
    address chief;
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig initCfg;
    DssLitePsmMigrationPhase3Config migCfg;
    DssLitePsm litePsm;
    DssLitePsmMom mom;
    GemLike gem;
    address pocket;
    address pip;
    InitCaller initCaller;
    MigrationCaller migCaller;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        chief = dss.chainlog.getAddress("MCD_ADM");
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        srcPsm = dss.chainlog.getAddress(SRC_PSM_KEY);
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

        litePsm = DssLitePsm(inst.litePsm);
        mom = DssLitePsmMom(inst.mom);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        initCfg = DssLitePsmInitConfig({
            psmKey: DST_PSM_KEY,
            psmMomKey: PSM_MOM_KEY,
            pocketKey: DST_POCKET_KEY,
            pocket: pocket,
            pip: pip,
            buf: 50_000_000 * WAD,
            tin: 0.01 ether,
            tout: 0.01 ether,
            maxLine: 50_000_000 * RAD,
            gap: 10_000_000 * RAD,
            ttl: 8 hours
        });

        migCfg = DssLitePsmMigrationPhase3Config({
            srcPsmKey: SRC_PSM_KEY,
            dstPsmKey: DST_PSM_KEY,
            buf: 50_000_000 * WAD,
            tin: 0.025 ether,
            tout: 0.025 ether,
            maxLine: 10_000_000_000 * RAD,
            gap: 200_000_000 * RAD,
            ttl: 8 hours
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
        vm.label(srcPsm, "PsmUsdc");
        vm.label(inst.litePsm, "LitePsm");
        vm.label(inst.mom, "LitePsmMom");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(address(autoLine), "AutoLine");
    }

    function testLitePsmMigration() public {
        // Simulate a spell casting for initialization
        vm.prank(pause);
        pauseProxy.exec(address(initCaller), abi.encodeCall(initCaller.init, (dss, inst, initCfg)));

        uint256 pglobalLine = dss.vat.Line();
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, srcPsm);
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");

        // Source PSM is present in AutoLiine
        {
            (uint256 psrcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertGt(psrcMaxLine, 0, "before: src ilk not in AutoLine");
        }

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate, (dss, migCfg)));

        // Sanity checks
        {
            assertEq(litePsm.tin(), migCfg.tin, "after: invalid tin");
            assertEq(litePsm.tout(), migCfg.tout, "after: invalid tout");
            assertEq(litePsm.buf(), migCfg.buf, "after: invalid buf");
            assertEq(litePsm.vow(), vow, "after: invalid vow");
        }

        // Global Line should be adjusted by increasing the new PSM line, taking into account the old values
        {
            uint256 globalLine = dss.vat.Line();
            assertEq(globalLine, pglobalLine + (migCfg.gap - initCfg.gap), "after: invalid Line change");
        }

        // All collateral and debt has been migrated from the source PSM
        {
            (uint256 srcIlkArt,,, uint256 srcLine,) = dss.vat.ilks(SRC_ILK);
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, srcPsm);
            assertEq(srcIlkArt, 0, "after: src ilk Art is not zero");
            assertEq(srcLine, 0, "after: src line is not zero");
            assertEq(srcArt, 0, "after: src art is not zero");
            assertEq(srcInk, 0, "after: src ink is not zero");
        }

        // Source PSM has been removed from AutoLine
        {
            (uint256 srcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertEq(srcMaxLine, 0, "after: src ilk not removed from AutoLine");
        }

        // New PSM is configured in AutoLiine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, migCfg.maxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, migCfg.gap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(migCfg.ttl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }
    }
}
