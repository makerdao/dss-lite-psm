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
import {DssLitePsm} from "../../src/DssLitePsm.sol";
import {DssPocket} from "../../src/DssPocket.sol";

struct DssLitePsmDeployParams {
    address deployer;
    address owner;
    bytes32 ilk;
    address gem;
    address daiJoin;
}

struct DssLitePsmInstance {
    address litePsm;
    address pocket;
}

library DssLitePsmDeploy {
    function deploy(DssLitePsmDeployParams memory p) internal returns (DssLitePsmInstance memory r) {
        address pocket = address(new DssPocket(p.gem));
        address litePsm = address(new DssLitePsm(p.ilk, p.gem, p.daiJoin, pocket));

        ScriptTools.switchOwner(pocket, p.deployer, p.owner);
        ScriptTools.switchOwner(litePsm, p.deployer, p.owner);

        r.pocket = pocket;
        r.litePsm = litePsm;
    }
}
