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

import {ScriptTools} from "dss-test/ScriptTools.sol";
import {DssPocket} from "src/DssPocket.sol";
import {DssLitePsm} from "src/DssLitePsm.sol";
import {DssLitePsmMom} from "src/DssLitePsmMom.sol";
import {DssLitePsmInstance} from "./DssLitePsmInstance.sol";

struct DssLitePsmDeployParams {
    address deployer;
    address owner;
    bytes32 ilk;
    address chainlog;
    address gem;
    address daiJoin;
}

library DssLitePsmDeploy {
    function deploy(DssLitePsmDeployParams memory p) internal returns (DssLitePsmInstance memory r) {
        r.pocket = address(new DssPocket(p.gem));
        r.litePsm = address(new DssLitePsm(p.ilk, p.gem, p.daiJoin, r.pocket));
        r.mom = address(new DssLitePsmMom(p.chainlog));

        ScriptTools.switchOwner(r.pocket, p.deployer, p.owner);
        ScriptTools.switchOwner(r.litePsm, p.deployer, p.owner);
        DssLitePsmMom(r.mom).setOwner(p.owner);
    }
}
