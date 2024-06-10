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

interface GemLike {
    function approve(address, uint256) external;
    function decimals() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

contract InitCaller {
    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) external {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract DssLitePsmInitTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant GEM_KEY = "USDC";
    bytes32 constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 constant ILK = "LITE-PSM-USDC-A";
    bytes32 constant PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 constant POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    uint256 constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    DssInstance dss;
    address pause;
    address vow;
    address chief;
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssLitePsmInstance inst;
    DssLitePsmInitConfig cfg;
    DssLitePsm litePsm;
    DssLitePsmMom mom;
    GemLike gem;
    address pocket;
    address pip;
    InitCaller caller;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        chief = dss.chainlog.getAddress("MCD_ADM");
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        gem = GemLike(dss.chainlog.getAddress(GEM_KEY));
        pocket = makeAddr("Pocket");
        pip = dss.chainlog.getAddress("PIP_USDC");

        caller = new InitCaller();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                ilk: ILK,
                gem: address(gem),
                daiJoin: address(dss.daiJoin),
                pocket: pocket
            })
        );

        litePsm = DssLitePsm(inst.litePsm);
        mom = DssLitePsmMom(inst.mom);

        vm.prank(pocket);
        gem.approve(inst.litePsm, type(uint256).max);

        cfg = DssLitePsmInitConfig({
            psmKey: PSM_KEY,
            psmMomKey: PSM_MOM_KEY,
            pocketKey: POCKET_KEY,
            pip: pip,
            ilk: ILK,
            gem: address(gem),
            pocket: pocket
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
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

    function testLitePsmInit() public {
        {
            (uint256 pilkArt,,, uint256 pline,) = dss.vat.ilks(ILK);
            (uint256 pink, uint256 part) = dss.vat.urns(ILK, inst.litePsm);
            assertEq(pilkArt, 0, "before: ilk Art is not zero");
            assertEq(pline, 0, "before: line is not zero");
            assertEq(part, 0, "before: art is not zero");
            assertEq(pink, 0, "before: ink is not zero");
        }

        // `litePsm`, `mom` and `pocket` are not present in Chainlog
        {
            vm.expectRevert("dss-chain-log/invalid-key");
            dss.chainlog.getAddress(cfg.psmKey);

            vm.expectRevert("dss-chain-log/invalid-key");
            dss.chainlog.getAddress(cfg.psmMomKey);

            vm.expectRevert("dss-chain-log/invalid-key");
            dss.chainlog.getAddress(cfg.pocketKey);
        }

        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(address(caller), abi.encodeCall(caller.init, (dss, inst, cfg)));

        // Sanity checks
        {
            assertEq(litePsm.vow(), vow, "after: invalid vow");
        }

        // New PSM is properly setup
        {
            (uint256 ink,) = dss.vat.urns(ILK, inst.litePsm);
            // Unlimited virtual ink is set properly
            assertEq(ink, type(uint256).max / RAY, "after: invalid ink");
        }

        // `mom` was properly set up
        {
            assertEq(mom.authority(), chief, "after: `mom` authority not set");
        }

        // `mom` is ward on `litePsm`
        {
            assertEq(litePsm.wards(inst.mom), 1, "after: `mom` not ward of `litePsm`");
        }

        // `litePsm` info is added to IlkRegistry
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
            ) = reg.info(ILK);

            assertEq(name, gem.name(), "after: reg name mismatch");
            assertEq(symbol, gem.symbol(), "after: reg symbol mismatch");
            assertEq(_class, REG_CLASS_JOINLESS, "after: reg class mismatch");
            assertEq(decimals, gem.decimals(), "after: reg dec mismatch");
            assertEq(_gem, address(gem), "after: reg gem mismatch");
            assertEq(_pip, pip, "after: reg pip mismatch");
            assertEq(gemJoin, address(0), "after: invalid reg gemJoin");
            assertEq(clip, address(0), "after: invalid reg xlip");
        }

        // `litePsm`, `mom` and `pocket` are present in Chainlog
        {
            assertEq(dss.chainlog.getAddress(cfg.psmKey), inst.litePsm, "after: `litePsm` not in chainlog");
            assertEq(dss.chainlog.getAddress(cfg.psmMomKey), inst.mom, "after: `mom` not in chainlog");
            assertEq(dss.chainlog.getAddress(cfg.pocketKey), pocket, "after: `pocket` not in chainlog");
        }
    }
}
