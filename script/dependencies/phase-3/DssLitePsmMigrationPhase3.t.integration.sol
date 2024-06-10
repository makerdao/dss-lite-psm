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
import {DssLitePsmMigrationPhase1} from "../phase-1/DssLitePsmMigrationPhase1.sol";
import {DssLitePsmMigrationPhase2} from "../phase-2/DssLitePsmMigrationPhase2.sol";
import {DssLitePsmMigrationPhase3} from "./DssLitePsmMigrationPhase3.sol";

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
}

interface GemLike {
    function approve(address, uint256) external;
}

contract MigrationCaller {
    function initAndMigrate1(
        DssInstance memory dss,
        DssLitePsmInstance memory inst,
        address pocket
    ) external {
        DssLitePsmMigrationPhase1.initAndMigrate(dss, inst, pocket);
    }

    function migrate2(DssInstance memory dss) external {
        DssLitePsmMigrationPhase2.migrate(dss);
    }

    function migrate3(DssInstance memory dss) external {
        DssLitePsmMigrationPhase3.migrate(dss);
    }
}

contract DssLitePsmMigrationPhase3Test is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant DST_ILK = "LITE-PSM-USDC-A";
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
    DssLitePsmLike litePsm;
    GemLike gem;
    address pocket;
    address pip;
    MigrationCaller migCaller;

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

        litePsm = DssLitePsmLike(inst.litePsm);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
        vm.label(address(gem), "USDC");
        vm.label(address(srcPsm), "PsmUsdc");
        vm.label(inst.litePsm, "LitePsm");
        vm.label(pocket, "Pocket");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(address(autoLine), "AutoLine");

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.initAndMigrate1, (dss, inst, pocket)));
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate2, (dss)));
    }

    function testMigrationPhase3() public {
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");
        (uint256 pdstInk, uint256 pdstArt) = dss.vat.urns(DST_ILK, address(litePsm));

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate3, (dss)));

        // Sanity checks
        {
            assertEq(srcPsm.tin(), 0, "after: invalid src tin");
            assertEq(srcPsm.tout(), 0, "after: invalid src tout");
            assertEq(srcPsm.vow(), vow, "after: invalid src vow update");

            assertEq(litePsm.tin(), 0, "after: invalid dst tin");
            assertEq(litePsm.tout(), 0, "after: invalid dst tout");
            assertEq(litePsm.buf(), 400_000_000 * WAD, "after: invalid dst buf");
            assertEq(litePsm.vow(), vow, "after: invalid dst vow update");
        }

        // Old PSM ink is decreased by the correct amount
        {
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, 0, "after: src ink is not zero");
            assertEq(srcArt, 0, "after: src art is not zero");
        }

        // Old PSM ink and art were fully migrated to new PSM
        {
            (uint256 dstInk, uint256 dstArt) = dss.vat.urns(DST_ILK, address(litePsm));
            // LitePSM ink is never modified
            assertEq(dstInk, pdstInk, "after: invalid dst ink");
            assertEq(dstArt, pdstArt + psrcArt + 100_000_000 * WAD, "after: invalid dst art");
        }

        // Old PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl,,) = autoLine.ilks(SRC_ILK);
            assertEq(maxLine, 0, "after: AutoLine maxLine is not zero");
            assertEq(gap, 0, "after: AutoLine gap is not zero");
            assertEq(ttl, 0, "after: AutoLine ttl is not zero");
        }

        // New PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, 10_000_000_000 * RAD, "after: AutoLine invalid maxLine");
            assertEq(gap, 400_000_000 * RAD, "after: AutoLine invalid gap");
            assertEq(ttl, 12 hours, "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }
    }
}
