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

import {DssInstance} from "dss-test/MCD.sol";
import {DssLitePsmMigration, MigrationConfig, MigrationResult} from "../DssLitePsmMigration.sol";

interface DssPsmLike {
    function file(bytes32, uint256) external;
}

interface DssLitePsmLike {
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function rush() external view returns (uint256);
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

library DssLitePsmMigrationPhase2 {
    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAD = 10 ** 45;

    function migrate(DssInstance memory dss) internal {
        // 1. Migrate funds to the new PSM.
        MigrationResult memory res = DssLitePsmMigration.migrate(
            dss,
            MigrationConfig({
                srcPsmKey: "MCD_PSM_USDC_A",
                dstPsmKey: "MCD_LITE_PSM_USDC_A",
                move: type(uint256).max,
                leave: 100_000_000 * WAD
            })
        );

        // 2. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 2.1. Update auto-line for `srcPsm`
        autoLine.setIlk(res.srcIlk, 2_500_000_000 * RAD, 100_000_000 * RAD, 12 hours);
        autoLine.exec(res.srcIlk);

        // 2.2. Update auto-line for `dstPsm`
        autoLine.setIlk(res.dstIlk, 7_500_000_000 * RAD, 300_000_000 * RAD, 12 hours);
        autoLine.exec(res.dstIlk);

        // 3. Set the final params for both PSMs.
        DssPsmLike(res.srcPsm).file("tin", 0.001 ether);
        DssPsmLike(res.srcPsm).file("tout", 0.001 ether);

        DssLitePsmLike(res.dstPsm).file("buf", 300_000_000 * WAD);

        // 4. Fill `dstPsm` so there is liquidity available immediately.
        // Notice: `dstPsm.fill` must be called last because it is constrained by both `cfg.buf` and `cfg.maxLine`.
        if (DssLitePsmLike(res.dstPsm).rush() > 0) {
            DssLitePsmLike(res.dstPsm).fill();
        }
    }
}
