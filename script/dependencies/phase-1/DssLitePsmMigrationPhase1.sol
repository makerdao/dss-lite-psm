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

struct DssLitePsmMigrationConfigPhase1 {
    bytes32 psmMomKey;
    address dstPip;
    bytes32 dstPsmKey;
    bytes32 dstPocketKey;
    uint256 dstTin;
    uint256 dstTout;
    uint256 dstBuf;
    uint256 dstMaxLine;
    uint256 dstGap;
    uint256 dstTtl;
    uint256 dstWant;
    bytes32 srcPsmKey;
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
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

library DssLitePsmMigrationPhase1 {
    uint256 internal constant RAY = 10 ** 27;

    function initAndMigrate(
        DssInstance memory dss,
        DssLitePsmInstance memory inst,
        DssLitePsmMigrationConfigPhase1 memory cfg
    ) internal {
        // 1. Initialize the new PSM,
        DssLitePsmInit.init(
            dss,
            inst,
            DssLitePsmInitConfig({
                psmMomKey: cfg.psmMomKey,
                psmKey: cfg.dstPsmKey,
                pocketKey: cfg.dstPocketKey,
                buf: cfg.dstBuf,
                tin: cfg.dstTin,
                tout: cfg.dstTout,
                pip: cfg.dstPip
            })
        );

        // 2. Migrate some funds to the new PSM.
        MigrationResult memory res = DssLitePsmMigration.migrate(
            dss,
            MigrationConfig({
                srcPsmKey: cfg.srcPsmKey,
                dstPsmKey: cfg.dstPsmKey,
                dstWant: cfg.dstWant,
                dstBuf: cfg.dstBuf
            })
        );

        // 3. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 3.1. Update auto-line for `src.psm`
        autoLine.setIlk(res.src.ilk, cfg.srcMaxLine, cfg.srcGap, cfg.srcTtl);
        autoLine.exec(res.src.ilk);

        // 3.2. Update auto-line for `dst.psm`
        // Ensure we will be able to call `fill` below.
        require(cfg.dstMaxLine > res.dst.art * RAY, "DssLitePsmMigration/max-line-too-low");
        autoLine.setIlk(res.dst.ilk, cfg.dstMaxLine, cfg.dstGap, cfg.dstTtl);
        autoLine.exec(res.dst.ilk);

        // 4. Set the final params for `dst.psm`.
        DssLitePsmLike(res.dst.psm).file("tin", cfg.dstTin);
        DssLitePsmLike(res.dst.psm).file("tout", cfg.dstTout);
        DssLitePsmLike(res.dst.psm).file("buf", cfg.dstBuf);

        // 5. Fill `dst.psm` so there is liquidity available immediately.
        // Notice: `dst.psm.fill` must be called last because it is constrained by both `cfg.buf` and `cfg.maxLine`.
        DssLitePsmLike(res.dst.psm).fill();
    }
}
