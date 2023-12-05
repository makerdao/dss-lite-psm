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

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MCD, DssInstance} from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {DssLitePsmDeploy, DssLitePsmDeployParams} from "./dependencies/DssLitePsmDeploy.sol";
import {DssLitePsmInstance} from "./dependencies/DssLitePsmInstance.sol";

contract DssLitePsmDeployScript is Script {
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "dss-lite-psm-deploy";
    string config;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);
    address pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
    string ilkStr;
    bytes32 ilk;
    bytes32 gemId;
    address gem;
    DssLitePsmInstance inst;

    function run() external {
        config = ScriptTools.loadConfig();

        ilkStr = config.readString(".ilk", "FOUNDRY_ILK");
        ilk = ilkStr.stringToBytes32();
        gemId = config.readString(".gemId", "FOUNDRY_GEM_ID").stringToBytes32();
        gem = dss.chainlog.getAddress(gemId);

        vm.startBroadcast();

        inst = DssLitePsmDeploy.deploy(
            DssLitePsmDeployParams({
                deployer: msg.sender,
                owner: pauseProxy,
                ilk: ilk,
                gem: gem,
                daiJoin: address(dss.daiJoin)
            })
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "litePsm", inst.litePsm);
        ScriptTools.exportContract(NAME, "pocket", inst.pocket);
        ScriptTools.exportContract(NAME, "mom", inst.mom);
        ScriptTools.exportContract(NAME, "gem", gem);
        ScriptTools.exportValue(NAME, "ilk", ilkStr);
    }
}
