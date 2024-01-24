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

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {MCD, DssInstance, ScriptTools} from "dss-test/DssTest.sol";
import {DssLitePsmInstance} from "./dependencies/DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "./dependencies/DssLitePsmInit.sol";

uint256 constant WAD = 10**18;
uint256 constant RAD = 10**45;

interface ProxyLike {
    function owner() external view returns (address);
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

contract DssSpell {
    address public constant LITE_PSM = 0x215c6081Bc6889763D8f8B01B662285B63F3e90F;
    address public constant MOM = 0x4028de7008bBFa80617c3FB5F48041dfB5a960c6;
    address public constant POCKET = 0x2374B28e213f07bCa1789f047433ED81eE1d909E;

    address public constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 public constant GEM_KEY = "USDC";
    bytes32 public constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 public constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 public constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 public constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 public constant SRC_ILK = "PSM-USDC-A";
    bytes32 public constant SRC_PSM_KEY = "MCD_PSM_USDC_A";
    uint256 public constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    function cast(DssInstance calldata dss, DssLitePsmInstance calldata inst, DssLitePsmInitConfig calldata cfg)
        public
    {
        DssLitePsmInit.init(dss, inst, cfg);
    }
}

contract DssLitePsmCastSpellScript is Script {
    using stdStorage for StdStorage;
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "dss-lite-psm-cast-spell";
    string config;
    string deps;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);

    function run() external {
        config = ScriptTools.loadConfig();
        deps = ScriptTools.loadDependencies();

        string memory srcPsmKey = config.readString(".srcPsmKey");
        string memory dstPsmKey = config.readString(".dstPsmKey");
        string memory dstPocketKey = config.readString(".dstPocketKey");
        string memory psmMomKey = config.readString(".psmMomKey");
        uint256 buf = config.readUint(".buf") * WAD;
        uint256 maxLine = config.readUint(".maxLine") * RAD;
        uint256 gap = config.readUint(".gap") * RAD;
        uint256 ttl = config.readUint(".ttl");

        address pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");

        DssLitePsmInstance memory inst = DssLitePsmInstance({
            litePsm: deps.readAddress(".litePsm"),
            pocket: deps.readAddress(".pocket"),
            mom: deps.readAddress(".mom")
        });

        DssLitePsmInitConfig memory cfg = DssLitePsmInitConfig({
            srcPsmKey: srcPsmKey.stringToBytes32(),
            dstPsmKey: dstPsmKey.stringToBytes32(),
            dstPocketKey: dstPocketKey.stringToBytes32(),
            psmMomKey: psmMomKey.stringToBytes32(),
            buf: buf,
            tin: 0,
            tout: 0,
            maxLine: maxLine,
            gap: gap,
            ttl: ttl
        });


        vm.startBroadcast();

        // Simulate a spell casting:
        // Requirement: the caller must be set as the `owner` of `MCD_PAUSE_PROXY`
        DssSpell spell = new DssSpell();
        ProxyLike(pauseProxy).exec(address(spell), abi.encodeCall(spell.cast, (dss, inst, cfg)));

        vm.stopBroadcast();
    }
}
