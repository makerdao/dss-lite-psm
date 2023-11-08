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
import {DssInstance, MCD} from "dss-test/MCD.sol";

import {DssLitePsmDeploy, DssLitePsmDeployParams, DssLitePsmInstance} from "script/dependencies/DssLitePsmDeploy.sol";
import {DssLitePsmInitConfig, DssLitePsmInit} from "script/dependencies/DssLitePsmInit.sol";

import {DssPocket} from "src/DssPocket.sol";
import {DssLitePsm} from "src/DssLitePsm.sol";
import {DssLitePsmMom} from "src/DssLitePsmMom.sol";

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface ChiefLike {
    function hat() external view returns (address);
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract DssLitePsmMomTest is DssTest {
    using stdStorage for StdStorage;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    bytes32 constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 constant SRC_PSM_KEY = "MCD_PSM_USDC_A";

    DssLitePsm litePsm;
    DssLitePsmMom mom;
    ProxyLike pauseProxy;
    address pause;
    DssInstance dss;
    ChiefLike chief;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig cfg;
    InitCaller caller = new InitCaller();

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);
        MCD.giveAdminAccess(dss);

        chief = ChiefLike(dss.chainlog.getAddress("MCD_ADM"));
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        pause = dss.chainlog.getAddress("MCD_PAUSE");

        caller = new InitCaller();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                chainlog: CHAINLOG,
                ilk: DST_ILK,
                gem: dss.chainlog.getAddress("USDC"),
                daiJoin: address(dss.daiJoin)
            })
        );

        litePsm = DssLitePsm(inst.litePsm);
        mom = DssLitePsmMom(inst.mom);

        cfg = DssLitePsmInitConfig({
            srcPsmKey: SRC_PSM_KEY,
            dstPsmKey: DST_PSM_KEY,
            psmMomKey: PSM_MOM_KEY,
            dstPocketKey: DST_POCKET_KEY,
            buf: 50_000_000 * WAD,
            tin: 0,
            tout: 0,
            maxLine: 1_000_000_000 * RAD,
            gap: 50_000_000 * RAD,
            ttl: 8 hours
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(inst.litePsm, "LitePsm");
        vm.label(inst.mom, "LitePsmMom");
        vm.label(inst.pocket, "Pocket");

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(address(caller), abi.encodeCall(caller.init, (dss, inst, cfg)));
    }

    function testSetOwner() public {
        vm.expectEmit(true, true, true, true);
        emit SetOwner(address(0x1234));
        vm.prank(address(pauseProxy));
        mom.setOwner(address(0x1234));
        assertEq(mom.owner(), address(0x1234));
    }

    function testSetOwnerNotAuthed() public {
        vm.expectRevert("DssLitePsmMom/not-owner");
        vm.prank(address(0x1337));
        mom.setOwner(address(0x1234));
    }

    function testSetAuthority() public {
        vm.expectEmit(true, true, true, true);
        emit SetAuthority(address(0x1234));
        vm.prank(address(pauseProxy));
        mom.setAuthority(address(0x1234));
        assertEq(mom.authority(), address(0x1234));
    }

    function testSetAuthorityNotAuthed() public {
        vm.expectRevert("DssLitePsmMom/not-owner");
        vm.prank(address(0x1337));
        mom.setAuthority(address(0x1234));
    }

    function doFile(address sender, bytes32 what, uint256 data) internal {
        require(what == "tin" || what == "tout", "doFile: invalid parameter");

        vm.expectEmit(true, true, true, true);
        emit File(what, data);

        vm.prank(sender);
        mom.file(cfg.dstPsmKey, what, data);

        if (what == "tin") {
            assertEq(litePsm.tin(), data, "doFile: tin not set");
        } else {
            assertEq(litePsm.tout(), data, "doFile: tout not set");
        }
    }

    function testFileFromOwner() public {
        doFile(address(pauseProxy), "tin", type(uint256).max);
        doFile(address(pauseProxy), "tout", type(uint256).max);
    }

    function testFileFromHat() public {
        doFile(address(chief.hat()), "tin", type(uint256).max);
        doFile(address(chief.hat()), "tout", type(uint256).max);
    }

    event SetOwner(address indexed _owner);
    event SetAuthority(address indexed _authority);
}
