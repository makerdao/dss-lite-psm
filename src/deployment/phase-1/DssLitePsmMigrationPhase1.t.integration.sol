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
import {DssLitePsmMigrationPhase1, DssLitePsmMigrationConfigPhase1} from "./DssLitePsmMigrationPhase1.sol";

interface DssPsmLike {
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
    function vow() external view returns (address);
}

interface DssLitePsmLike is DssPsmLike {
    function buf() external view returns (uint256);
    function to18ConversionFactor() external view returns (uint256);
}

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
    function balanceOf(address) external view returns (uint256);
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
    DssLitePsmLike dstPsm;
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

        dstPsm = DssLitePsmLike(inst.litePsm);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        migCfg = DssLitePsmMigrationConfigPhase1({
            psmMomKey: PSM_MOM_KEY,
            dstPsmKey: DST_PSM_KEY,
            dstPocketKey: DST_POCKET_KEY,
            dstPip: pip,
            dstIlk: DST_ILK,
            dstGem: address(gem),
            dstPocket: pocket,
            dstBuf: 20_000_000 * WAD,
            dstMaxLine: 50_000_000 * RAD,
            dstGap: 20_000_000 * RAD,
            dstTtl: 12 hours,
            dstWant: 20_000_000 * WAD,
            srcPsmKey: SRC_PSM_KEY,
            srcMaxLine: 10_000_000_000 * RAD,
            srcGap: 380_000_000 * RAD,
            srcTtl: 12 hours,
            srcKeep: 100_000_000 * WAD
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(address(pause), "Pause");
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
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 psrcTin = srcPsm.tin();
        uint256 psrcTout = srcPsm.tout();
        uint256 psrcVatGem = dss.vat.gem(SRC_ILK, address(srcPsm));
        uint256 pdstVatGem = dss.vat.gem(DST_ILK, address(dstPsm));

        // Pre-conditions
        {
            (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
            assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
            assertGt(psrcLine, 0, "before: src line is zero");
            assertGt(psrcArt, 0, "before: src art is zero");
            assertGt(psrcInk, 0, "before: src ink is zero");
        }

        // Simulate a spell casting for migration
        vm.prank(address(pause));
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.initAndMigrate, (dss, inst, migCfg)));

        // Sanity checks
        assertEq(srcPsm.tin(), psrcTin, "after: unexpected src tin update");
        assertEq(srcPsm.tout(), psrcTout, "after: unexpected src tout update");
        assertEq(srcPsm.vow(), vow, "after: unexpected src vow update");

        assertEq(dstPsm.buf(), migCfg.dstBuf, "after: invalid dst buf");
        assertEq(dstPsm.vow(), vow, "after: unexpected dst vow update");

        // Old PSM state is set correctly
        {
            (uint256 srcInk, uint256 srcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, psrcInk - migCfg.dstWant, "after: src ink is not decreased by want");
            assertEq(srcArt, psrcArt - migCfg.dstWant, "after: src art is not decreased by want");
            assertEq(dss.vat.gem(SRC_ILK, address(srcPsm)), psrcVatGem, "after: unexpected src vat gem change");
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

        // New PSM: `dstPsm`, `mom` and `pocket` are present in Chainlog
        assertEq(dss.chainlog.getAddress(migCfg.psmMomKey), inst.mom, "after: `mom` not in chainlog");
        assertEq(dss.chainlog.getAddress(migCfg.dstPsmKey), inst.litePsm, "after: `dstPsm` not in chainlog");
        assertEq(dss.chainlog.getAddress(migCfg.dstPocketKey), pocket, "after: `pocket` not in chainlog");

        // New PSM is properly configured on AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(DST_ILK);
            assertEq(maxLine, migCfg.dstMaxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, migCfg.dstGap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(migCfg.dstTtl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }

        // New PSM state is set correctly
        assertEq(dss.dai.balanceOf(address(dstPsm)), migCfg.dstBuf, "after: invalid dst psm dai balance");
        assertEq(dss.vat.gem(DST_ILK, address(dstPsm)), pdstVatGem, "after: unexpected dst vat gem change");
        assertEq(_amtToWad(gem.balanceOf(address(pocket))), migCfg.dstWant, "after: invalid gem balance for dst pocket");
    }

    function _amtToWad(uint256 amt) internal view returns (uint256) {
        return amt * dstPsm.to18ConversionFactor();
    }
}
