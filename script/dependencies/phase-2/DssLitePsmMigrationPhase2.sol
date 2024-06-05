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

struct DssLitePsmMigrationConfigPhase2 {
    bytes32 dstPsmKey;
    uint256 dstTin;
    uint256 dstTout;
    uint256 dstBuf;
    uint256 dstMaxLine;
    uint256 dstGap;
    uint256 dstTtl;
    uint256 dstWant;
    bytes32 srcPsmKey;
    uint256 srcTin;
    uint256 srcTout;
    uint256 srcMaxLine;
    uint256 srcGap;
    uint256 srcTtl;
}

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
    uint256 internal constant RAY = 10 ** 27;

    function migrate(DssInstance memory dss, DssLitePsmMigrationConfigPhase2 memory cfg) internal {
        // 1. Migrate funds to the new PSM.
        MigrationResult memory res = DssLitePsmMigration.migrate(
            dss,
            MigrationConfig({
                srcPsmKey: cfg.srcPsmKey,
                dstPsmKey: cfg.dstPsmKey,
                dstWant: cfg.dstWant,
                dstBuf: cfg.dstBuf
            })
        );

        // 2. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 2.1. Update auto-line for `src.psm`
        autoLine.setIlk(res.src.ilk, cfg.srcMaxLine, cfg.srcGap, cfg.srcTtl);
        autoLine.exec(res.src.ilk);

        // 2.2. Update auto-line for `dst.psm`
        // Ensure we will be able to call `fill` below.
        require(cfg.dstMaxLine > res.dst.art * RAY, "DssLitePsmMigrationPhase2/max-line-too-low");
        autoLine.setIlk(res.dst.ilk, cfg.dstMaxLine, cfg.dstGap, cfg.dstTtl);
        autoLine.exec(res.dst.ilk);

        // 3. Set the final params for both PSMs.
        DssPsmLike(res.src.psm).file("tin", cfg.srcTin);
        DssPsmLike(res.src.psm).file("tout", cfg.srcTout);

        DssLitePsmLike(res.dst.psm).file("tin", cfg.dstTin);
        DssLitePsmLike(res.dst.psm).file("tout", cfg.dstTout);
        DssLitePsmLike(res.dst.psm).file("buf", cfg.dstBuf);

        // 4. Fill `dst.psm` so there is liquidity available immediately.
        // Notice: `dst.psm.fill` must be called last because it is constrained by both `cfg.buf` and `cfg.maxLine`.
        if (DssLitePsmLike(res.dst.psm).rush() > 0) {
            DssLitePsmLike(res.dst.psm).fill();
        }
    }
}
