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
import {DssPocket} from "src/DssPocket.sol";
import {DssLitePsm} from "src/DssLitePsm.sol";
import {DssLitePsmDeploy, DssLitePsmDeployParams, DssLitePsmInstance} from "./DssLitePsmDeploy.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "./DssLitePsmInit.sol";

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract DssLitePsmInitTest is DssTest {
    address constant CHANGELOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant ILK = "LITE-PSM-USDC-A";
    bytes32 constant SRC_ILK = "PSM-USDC-A";
    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant SRC_PSM_KEY = "MCD_PSM_USDC_A";
    address pause;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssInstance dss;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig cfg;
    InitCaller caller;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(CHANGELOG);
        pause = dss.chainlog.getAddress("MCD_PAUSE");
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        caller = new InitCaller();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                ilk: ILK,
                gem: dss.chainlog.getAddress(GEM_KEY),
                daiJoin: address(dss.daiJoin)
            })
        );

        cfg = DssLitePsmInitConfig({
            srcPsm: dss.chainlog.getAddress(SRC_PSM_KEY),
            buf: 50_000_000 * WAD,
            tin: 0,
            tout: 0,
            maxLine: 1_000_000_000 * RAD,
            gap: 50_000_000 * RAD,
            ttl: 8 hours
        });

        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"), "AutoLine");
        vm.label(address(cfg.srcPsm), "PsmUsdc");
    }

    function testOnboarding() public {
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, cfg.srcPsm);
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");

        {
            (uint256 pilkArt,,, uint256 pline,) = dss.vat.ilks(ILK);
            (uint256 pink, uint256 part) = dss.vat.urns(ILK, inst.litePsm);
            assertEq(pilkArt, 0, "before: ilk Art is not zero");
            assertEq(pline, 0, "before: line is not zero");
            assertEq(part, 0, "before: art is not zero");
            assertEq(pink, 0, "before: ink is not zero");
        }

        // Source PSM is present on AutoLiine
        {
            (uint256 psrcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertGt(psrcMaxLine, 0, "before: src ilk not in AutoLine");
        }

        // `litePsm` not present on AutoLine
        {
            (uint256 pmaxLine,,,,) = autoLine.ilks(ILK);
            assertEq(pmaxLine, 0, "before: ilk already in AutoLine");
        }

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(address(caller), abi.encodeCall(caller.init, (dss, inst, cfg)));

        // All collateral and debt has been migrated from the source PSM
        {
            (uint256 srcIlkArt,,, uint256 srcLine,) = dss.vat.ilks(SRC_ILK);
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, cfg.srcPsm);
            assertEq(srcIlkArt, 0, "after: src ilk Art is not zero");
            assertEq(srcLine, 0, "after: src line is not zero");
            assertEq(srcArt, 0, "after: src art is not zero");
            assertEq(srcInk, 0, "after: src ink is not zero");
        }

        // New PSM is properly setup
        {
            (uint256 ilkArt,,, uint256 line,) = dss.vat.ilks(ILK);
            (uint256 ink, uint256 art) = dss.vat.urns(ILK, inst.litePsm);
            assertEq(ilkArt, psrcIlkArt + cfg.buf, "after: invalid ilk Art");
            assertEq(line, (psrcIlkArt + 2 * cfg.buf) * RAY, "after: invalid line");
            assertEq(art, psrcIlkArt + cfg.buf, "after: invalid art");
            assertGt(ink, 0, "after: ink is zero");
        }

        // Source PSM has been removed from AutoLine
        {
            (uint256 srcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertEq(srcMaxLine, 0, "after: src ilk not removed from AutoLine");
        }

        // Source PSM is present on AutoLiine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl,,) = autoLine.ilks(ILK);
            assertEq(maxLine, cfg.maxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, cfg.gap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(cfg.ttl), "after: AutoLine invalid ttl");
        }
    }
}
