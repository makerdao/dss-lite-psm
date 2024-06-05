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
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract MigrationCaller {
    function migrate(DssInstance memory dss, MigrationConfig memory cfg) external {
        DssLitePsmMigration.migrate(dss, cfg);
    }
}

contract DssLitePsmMigrationTest is DssTest {
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
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig initCfg;
    MigrationConfig migCfg;
    DssLitePsmLike litePsm;
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

        litePsm = DssLitePsmLike(inst.litePsm);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        initCfg = DssLitePsmInitConfig({
            psmKey: DST_PSM_KEY,
            psmMomKey: PSM_MOM_KEY,
            pocketKey: DST_POCKET_KEY,
            pip: pip,
            tin: 0.01 ether,
            tout: 0.01 ether,
            buf: 50_000_000 * WAD
        });

        migCfg = MigrationConfig({
            srcPsmKey: SRC_PSM_KEY,
            dstPsmKey: DST_PSM_KEY,
            dstWant: 10_000_000 * WAD,
            dstBuf: initCfg.buf
        });

        // Simulate a spell casting for initialization
        vm.prank(pause);
        pauseProxy.exec(address(initCaller), abi.encodeCall(initCaller.init, (dss, inst, initCfg)));

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

    function testLitePsmMigration() public {
        (uint256 psrcIlkArt,,, uint256 psrcLine,) = dss.vat.ilks(SRC_ILK);
        (uint256 psrcInk, uint256 psrcArt) = dss.vat.urns(SRC_ILK, address(srcPsm));
        uint256 psrcTin = srcPsm.tin();
        uint256 psrcTout = srcPsm.tout();
        uint256 pdstTin = litePsm.tin();
        uint256 pdstTout = litePsm.tout();
        uint256 pdstBuf = litePsm.buf();
        assertGt(psrcIlkArt, 0, "before: src ilk Art is zero");
        assertGt(psrcLine, 0, "before: src line is zero");
        assertGt(psrcArt, 0, "before: src art is zero");
        assertGt(psrcInk, 0, "before: src ink is zero");

        // Simulate a spell casting for migration
        vm.prank(pause);
        pauseProxy.exec(address(migCaller), abi.encodeCall(migCaller.migrate, (dss, migCfg)));

        // Sanity checks
        {
            assertEq(srcPsm.tin(), psrcTin, "after: invalid src tin update");
            assertEq(srcPsm.tout(), psrcTout, "after: invalid src tout update");
            assertEq(srcPsm.vow(), vow, "after: invalid src vow update");

            assertEq(litePsm.tin(), pdstTin, "after: invalid dst tin update");
            assertEq(litePsm.tout(), pdstTout, "after: invalid dst tout update");
            assertEq(litePsm.buf(), pdstBuf, "after: invalid dst buf update");
            assertEq(litePsm.vow(), vow, "after: invalid dst vow update");
        }

        // Old PSM ink is decreased by the correct amount
        {
            (uint256 srcInk,) = dss.vat.urns(SRC_ILK, address(srcPsm));
            assertEq(srcInk, psrcInk - migCfg.dstWant, "after: src ink is not decreased by dstWant");
        }
    }
}
