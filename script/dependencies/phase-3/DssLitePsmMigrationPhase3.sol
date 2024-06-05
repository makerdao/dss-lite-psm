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
import {DssLitePsmInstance} from "../DssLitePsmInstance.sol";
import {DssLitePsmInit, DssLitePsmInitConfig} from "../DssLitePsmInit.sol";
import {DssLitePsmMigration, MigrationConfig, MigrationResult} from "../DssLitePsmMigration.sol";

struct DssLitePsmMigrationConfigPhase3 {
    bytes32 dstPsmKey;
    uint256 dstTin;
    uint256 dstTout;
    uint256 dstBuf;
    uint256 dstMaxLine;
    uint256 dstGap;
    uint256 dstTtl;
    bytes32 srcPsmKey;
}

interface DssPsmLike {
    function file(bytes32, uint256) external;
    function ilk() external view returns (bytes32);
}

interface DssLitePsmLike {
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function rush() external view returns (uint256);
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function remIlk(bytes32) external;
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

library DssLitePsmMigrationPhase3 {
    uint256 internal constant RAY = 10 ** 27;

    function migrate(DssInstance memory dss, DssLitePsmMigrationConfigPhase3 memory cfg) internal {
        // 1. Get the remaining amount of collateral from src PSM.
        address srcPsm = dss.chainlog.getAddress(cfg.srcPsmKey);
        bytes32 srcIlk = DssPsmLike(srcPsm).ilk();
        (uint256 srcInk,) = dss.vat.urns(srcIlk, srcPsm);

        // 2. Migrate all funds to the new PSM.
        MigrationResult memory res = DssLitePsmMigration.migrate(
            dss,
            MigrationConfig({srcPsmKey: cfg.srcPsmKey, dstPsmKey: cfg.dstPsmKey, dstWant: srcInk, dstBuf: cfg.dstBuf})
        );

        // 3. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 3.1. Remove `src.psm` from AutoLine
        autoLine.remIlk(res.src.ilk);
        dss.vat.file(res.src.ilk, "line", 0);

        // 3.2. Update auto-line for `dst.psm`
        // Ensure we will be able to call `fill` below.
        require(cfg.dstMaxLine > res.dst.art * RAY, "DssLitePsmMigrationPhase3/max-line-too-low");
        autoLine.setIlk(res.dst.ilk, cfg.dstMaxLine, cfg.dstGap, cfg.dstTtl);
        autoLine.exec(res.dst.ilk);

        // 4. Set the final params for both PSMs.
        DssPsmLike(res.src.psm).file("tin", 0);
        DssPsmLike(res.src.psm).file("tout", 0);

        DssLitePsmLike(res.dst.psm).file("tin", cfg.dstTin);
        DssLitePsmLike(res.dst.psm).file("tout", cfg.dstTout);
        DssLitePsmLike(res.dst.psm).file("buf", cfg.dstBuf);

        // 5. Fill `dst.psm` so there is liquidity available immediately.
        // Notice: `dst.psm.fill` must be called last because it is constrained by both `cfg.buf` and `cfg.maxLine`.
        if (DssLitePsmLike(res.dst.psm).rush() > 0) {
            DssLitePsmLike(res.dst.psm).fill();
        }
    }
}
