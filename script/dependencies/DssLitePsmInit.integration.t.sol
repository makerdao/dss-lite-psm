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
import {DssLitePsmDeploy, DssLitePsmDeployParams} from "./DssLitePsmDeploy.sol";
import {DssLitePsmInstance} from "./DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "./DssLitePsmInit.sol";

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

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract DssLitePsmInitTest is DssTest {
    address constant CHANGELOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 constant SRC_ILK = "PSM-USDC-A";
    bytes32 constant SRC_PSM_KEY = "MCD_PSM_USDC_A";
    DssInstance dss;
    address pause;
    address vow;
    address srcPsm;
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsm litePsm;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig cfg;
    InitCaller caller;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(CHANGELOG);
        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        srcPsm = dss.chainlog.getAddress(SRC_PSM_KEY);
        caller = new InitCaller();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                ilk: DST_ILK,
                gem: dss.chainlog.getAddress(GEM_KEY),
                daiJoin: address(dss.daiJoin)
            })
        );

        litePsm = DssLitePsm(inst.litePsm);

        cfg = DssLitePsmInitConfig({
            srcPsmKey: SRC_PSM_KEY,
            dstPsmKey: DST_PSM_KEY,
            dstPocketKey: DST_POCKET_KEY,
            buf: 50_000_000 * WAD,
            tin: 0.01 ether,
            tout: 0.01 ether,
            maxLine: 1_000_000_000 * RAD,
            gap: 100_000_000 * RAD,
            ttl: 8 hours
        });

        vm.label(CHANGELOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
        vm.label(srcPsm, "PsmUsdc");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(address(autoLine), "AutoLine");
    }

    function testLitePsmOnboarding() public {
        uint256 pglobalLine = dss.vat.Line();
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, srcPsm);
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");

        {
            (uint256 pilkArt,,, uint256 pline,) = dss.vat.ilks(DST_ILK);
            (uint256 pink, uint256 part) = dss.vat.urns(DST_ILK, inst.litePsm);
            assertEq(pilkArt, 0, "before: ilk Art is not zero");
            assertEq(pline, 0, "before: line is not zero");
            assertEq(part, 0, "before: art is not zero");
            assertEq(pink, 0, "before: ink is not zero");
        }

        // Source PSM is present in AutoLiine
        {
            (uint256 psrcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertGt(psrcMaxLine, 0, "before: src ilk not in AutoLine");
        }

        // `litePsm` not present in AutoLine
        {
            (uint256 pmaxLine,,,,) = autoLine.ilks(DST_ILK);
            assertEq(pmaxLine, 0, "before: ilk already in AutoLine");
        }

        // `litePsm` and `pocket` are not present in Chainlog
        {
            vm.expectRevert("dss-chain-log/invalid-key");
            dss.chainlog.getAddress(cfg.dstPsmKey);

            vm.expectRevert("dss-chain-log/invalid-key");
            dss.chainlog.getAddress(cfg.dstPocketKey);
        }

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(address(caller), abi.encodeCall(caller.init, (dss, inst, cfg)));

        // Sanity checks
        {
            assertEq(litePsm.tin(), cfg.tin, "after: invalid tin");
            assertEq(litePsm.tout(), cfg.tout, "after: invalid tout");
            assertEq(litePsm.buf(), cfg.buf, "after: invalid buf");
            assertEq(litePsm.vow(), vow, "after: invalid vow");
        }

        // Global Line should be adjusted by increasing the new PSM line and reducing the old one
        {
            uint256 globalLine = dss.vat.Line();
            assertEq(globalLine, pglobalLine - psrcLine + psrcArt * RAY + cfg.gap, "after: invalid Line change");
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

        // New PSM is properly setup
        {
            (uint256 ilkArt,,, uint256 line,) = dss.vat.ilks(DST_ILK);
            (uint256 ink, uint256 art) = dss.vat.urns(DST_ILK, inst.litePsm);
            assertEq(ilkArt, psrcIlkArt + cfg.buf, "after: invalid ilk Art");
            assertEq(line, psrcArt * RAY + cfg.gap, "after: invalid line");
            assertEq(art, psrcIlkArt + cfg.buf, "after: invalid art");
            // Unlimited virtual ink is set properly
            assertEq(ink, type(uint256).max / RAY, "after: invalid ink");
        }

        // Source PSM has been removed from AutoLine
        {
            (uint256 srcMaxLine,,,,) = autoLine.ilks(SRC_ILK);
            assertEq(srcMaxLine, 0, "after: src ilk not removed from AutoLine");
        }

        // New PSM is present in AutoLiine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, cfg.maxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, cfg.gap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(cfg.ttl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }

        // `litePsm` info is added to IlkRegistry
        {
            (
                string memory srcName,
                string memory srcSymbol,
                uint256 srcClass,
                uint256 srcDec,
                address srcGem,
                address srcPip,
                ,
            ) = reg.info(SRC_ILK);

            (
                string memory dstName,
                string memory dstSymbol,
                uint256 dstClass,
                uint256 dstDec,
                address dstGem,
                address dstPip,
                address dstGemJoin,
                address dstXlip
            ) = reg.info(DST_ILK);

            assertEq(dstName, srcName, "after: reg name mismatch");
            assertEq(dstSymbol, srcSymbol, "after: reg symbol mismatch");
            assertEq(dstClass, srcClass, "after: reg class mismatch");
            assertEq(dstDec, srcDec, "after: reg dec mismatch");
            assertEq(dstGem, srcGem, "after: reg gem mismatch");
            assertEq(dstPip, srcPip, "after: reg pip mismatch");
            assertEq(dstGemJoin, address(0), "after: invalid reg gemJoin");
            assertEq(dstXlip, address(0), "after: invalid reg xlip");
        }

        // `litePsm` and `pocket` are present in Chainlog
        {
            assertEq(dss.chainlog.getAddress(cfg.dstPsmKey), inst.litePsm, "after: `litePsm` not in chainlog");
            assertEq(dss.chainlog.getAddress(cfg.dstPocketKey), inst.pocket, "after: `pocket` not in chainlog");
        }
    }
}
