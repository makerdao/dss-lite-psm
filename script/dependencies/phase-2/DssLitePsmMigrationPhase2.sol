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

struct DssLitePsmMigrationPhase2Config {
    bytes32 srcPsmKey;  // Chainlog key
    uint256 srcTin;     // [wad] 10**18 == 100%
    uint256 srcTout;    // [wad] 10**18 == 100%
    uint256 srcMaxLine; // [rad]
    uint256 srcGap;     // [rad]
    uint256 srcTtl;     // [seconds]
    uint256 srcRump;    // [wad] Gems remaining in the source PSM after the migration .
    bytes32 dstPsmKey;  // Chainlog key
    uint256 dstTin;     // [wad] 10**18 = 100%
    uint256 dstTout;    // [wad] 10**18 = 100%
    uint256 dstMaxLine; // [rad]
    uint256 dstGap;     // [rad]
    uint256 dstTtl;     // [seconds]
    uint256 dstBuf;     // [wad]
}

// Required to avoid "stack too deep" errors
struct SrcPsm {
    bytes32 ilk;
    address psm;
    address gem;
    address gemJoin;
    uint256 line;
    uint256 ink;
    uint256 art;
}

// Required to avoid "stack too deep" errors
struct DstPsm {
    bytes32 ilk;
    address psm;
    address gem;
    uint256 line;
    uint256 art;
}

interface DssLitePsmLike {
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function ilk() external view returns (bytes32);
    function sellGem(address, uint256) external returns (uint256);
    function to18ConversionFactor() external view returns (uint256);
}

interface DssPsmLike {
    function ilk() external view returns (bytes32);
    function file(bytes32, uint256) external;
}

interface DssLitePsmMomLike {
    function setAuthority(address) external;
}

interface PipLike {
    function read() external view returns (bytes32);
}

interface GemJoinLike {
    function exit(address, uint256) external;
}

interface GemLike {
    function approve(address, uint256) external;
    function allowance(address, address) external view returns (uint256);
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function remIlk(bytes32) external;
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

interface IlkRegistryLike {
    function gem(bytes32 ilk) external view returns (address);
    function join(bytes32 ilk) external view returns (address);
}

library DssLitePsmMigrationPhase2 {
    /// @dev Workaround to explicitly revert with an arithmetic error.
    string internal constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAY = 10 ** 27;

    // New `IlkRegistry` class
    uint256 internal constant REG_CLASS_JOINLESS = 6;

    ///@dev Safely converts `uint256` to `int256`. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    function migrate(DssInstance memory dss, DssLitePsmMigrationPhase2Config memory cfg) internal {
        // Sanity checks
        require(cfg.srcPsmKey != cfg.dstPsmKey, "DssLitePsmMigrationPhase2/src-psm-same-key-dst-psm");
        require(cfg.dstBuf > 0, "DssLitePsmMigrationPhase2/invalid-buf");
        require(cfg.dstGap > 0, "DssLitePsmMigrationPhase2/invalid-gap");

        IlkRegistryLike reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));

        DstPsm memory dst;
        dst.psm = dss.chainlog.getAddress(cfg.dstPsmKey);
        dst.ilk = DssLitePsmLike(dst.psm).ilk();
        dst.gem = reg.gem(dst.ilk);
        (, dst.art) = dss.vat.urns(dst.ilk, dst.psm);

        SrcPsm memory src;
        src.psm = dss.chainlog.getAddress(cfg.srcPsmKey);
        src.ilk = DssPsmLike(src.psm).ilk();
        src.gem = reg.gem(src.ilk);
        src.gemJoin = reg.join(src.ilk);
        (src.ink, src.art) = dss.vat.urns(src.ilk, src.psm);

        require(dst.ilk != src.ilk, "DssLitePsmMigrationPhase2/invalid-ilk-reuse");
        require(dst.gem == src.gem, "DssLitePsmMigrationPhase2/dst-src-gem-mismatch");
        require(src.ink == src.art, "DssLitePsmMigrationPhase2/src-ink-art-mismatch");

        // 1. Set interim params to accommodate the migration.

        // 1.1. Ensure we will be able to call `fill` below by leaving enough room in the debt ceiling.
        uint256 totalLine = (dst.art + src.art) * RAY;
        require(cfg.dstMaxLine > totalLine, "DssLitePsmMigrationPhase2/max-line-too-low");
        dss.vat.file("Line", dss.vat.Line() + (src.art * RAY));
        dss.vat.file(dst.ilk, "line", totalLine);

        // 2. Pre-mint enough Dai liquidity to clear `src.psm`.
        DssLitePsmLike(dst.psm).file("buf", src.art);
        DssLitePsmLike(dst.psm).file("tin", 0);
        DssLitePsmLike(dst.psm).file("tout", 0);
        DssLitePsmLike(dst.psm).fill();

        // 3. Move gems from `src.psm` to `dst.psm`. cfg.srcRump amount is left behind on `src.psm`
        uint256 srcGemAmt = ((src.ink - cfg.srcRump) / DssLitePsmLike(dst.psm).to18ConversionFactor());

        // 3.1. Grab the collateral from `src.psm` into the executing contract, debt also grabbed here to maintain src.ink == src.art
        dss.vat.grab(src.ilk, src.psm, address(this), address(this), -_int256(src.ink - cfg.srcRump), -_int256(src.art - cfg.srcRump));

        // 3.2. Transfer the grabbed collateral to the executing contract.
        GemJoinLike(src.gemJoin).exit(address(this), srcGemAmt);

        // 3.3. Sell the grabbed collateral gems to `dst.psm`.
        GemLike(dst.gem).approve(dst.psm, srcGemAmt);
        uint256 daiOutWad = DssLitePsmLike(dst.psm).sellGem(address(this), srcGemAmt);
        require(daiOutWad == src.art - cfg.srcRump, "DssLitePsmMigrationPhase2/invalid-dai-amount");

        // 3.4. Convert ERC20 Dai into Vat Dai.
        dss.dai.approve(address(dss.daiJoin), daiOutWad);
        dss.daiJoin.join(address(this), daiOutWad);

        // 3.5. Erase the bad debt generated by `vat.grab()`.
        dss.vat.heal((src.art - cfg.srcRump) * RAY);

        // 4. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 4.1. Update auto-line for `dst.psm`.
        autoLine.setIlk(dst.ilk, cfg.dstMaxLine, cfg.dstGap, cfg.dstTtl);
        autoLine.exec(dst.ilk);

        // 4.2. Update auto-line for `src.psm`.
        autoLine.setIlk(src.ilk, cfg.srcMaxLine, cfg.srcGap, cfg.srcTtl);
        autoLine.exec(src.ilk);

        // 5. Set `dst.psm` config params.
        DssLitePsmLike(dst.psm).file("buf", cfg.dstBuf);
        DssLitePsmLike(dst.psm).file("tin", cfg.dstTin);
        DssLitePsmLike(dst.psm).file("tout", cfg.dstTout);

        // 6. Set `src.psm` config params
        DssPsmLike(src.psm).file("tin", cfg.srcTin);
        DssPsmLike(src.psm).file("tout", cfg.srcTout);
    }
}
