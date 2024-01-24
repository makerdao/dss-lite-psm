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

import {MCD, DssInstance} from "dss-test/DssTest.sol";
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

contract DssSpell {
    address public constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address public constant LITE_PSM = 0x215c6081Bc6889763D8f8B01B662285B63F3e90F;
    address public constant MOM = 0x4028de7008bBFa80617c3FB5F48041dfB5a960c6;
    address public constant POCKET = 0x2374B28e213f07bCa1789f047433ED81eE1d909E;

    bytes32 public constant GEM_KEY = "USDC";
    bytes32 public constant PSM_MOM_KEY = "MCD_LITE_PSM_MOM";
    bytes32 public constant DST_ILK = "LITE-PSM-USDC-A";
    bytes32 public constant DST_PSM_KEY = "MCD_LITE_PSM_USDC_A";
    bytes32 public constant DST_POCKET_KEY = "MCD_POCKET_LITE_PSM_USDC_A";
    bytes32 public constant SRC_ILK = "PSM-USDC-A";
    bytes32 public constant SRC_PSM_KEY = "MCD_PSM_USDC_A";
    uint256 public constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    uint256 public constant WAD = 10**18;
    uint256 public constant RAD = 10**45;

    function cast() public {
        DssInstance memory dss = MCD.loadFromChainlog(CHAINLOG);

        DssLitePsmInstance memory inst = DssLitePsmInstance({
            litePsm: LITE_PSM,
            pocket: POCKET,
            mom: MOM
        });

        DssLitePsmInitConfig memory cfg = DssLitePsmInitConfig({
            srcPsmKey: "MCD_PSM_USDC_A",
            dstPsmKey: "MCD_LITE_PSM_USDC_A",
            dstPocketKey: "MCD_LITE_PSM_POCKET_USDC_A",
            psmMomKey: "MCD_LITE_PSM_MOM",
            buf: 10_000_000 * WAD,
            tin: 0,
            tout: 0,
            maxLine: 1_000_000_000 * RAD,
            gap: 10_000_000 * RAD,
            ttl: 8 hours
        });

        DssLitePsmInit.init(dss, inst, cfg);
    }
}
