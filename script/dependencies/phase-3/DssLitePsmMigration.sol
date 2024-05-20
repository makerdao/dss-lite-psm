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

struct DssLitePsmMigrationConfig {
    bytes32 srcPsmKey;
    bytes32 dstPsmKey;
    uint256 buf;
    uint256 tin;
    uint256 tout;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
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
    function file(bytes32, address) external;
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function gem() external view returns (address);
    function daiJoin() external view returns (address);
    function ilk() external view returns (bytes32);
    function pocket() external view returns (address);
    function rely(address) external;
    function sellGem(address, uint256) external returns (uint256);
    function to18ConversionFactor() external view returns (uint256);
}

interface DssLitePsmMomLike {
    function setAuthority(address) external;
}

interface DssPsmLike {
    function ilk() external view returns (bytes32);
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

library DssLitePsmMigration {
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

    function migrate(DssInstance memory dss, DssLitePsmMigrationConfig memory cfg) internal {
        // Sanity checks
        require(cfg.srcPsmKey != cfg.dstPsmKey, "DssLitePsmMigration/src-psm-same-key-dst-psm");
        require(cfg.buf > 0, "DssLitePsmMigration/invalid-buf");
        require(cfg.gap > 0, "DssLitePsmMigration/invalid-gap");

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

        require(dst.ilk != src.ilk, "DssLitePsmMigration/invalid-ilk-reuse");
        require(dst.gem == src.gem, "DssLitePsmMigration/dst-src-gem-mismatch");
        require(src.ink == src.art, "DssLitePsmMigration/src-ink-art-mismatch");

        // 1. Set interim params to accommodate the migration.

        // 1.1. Ensure we will be able to call `fill` below by leaving enough room in the debt ceiling.
        uint256 totalLine = (dst.art + src.art) * RAY;
        require(cfg.maxLine > totalLine, "DssLitePsmMigration/max-line-too-low");
        dss.vat.file("Line", dss.vat.Line() + (src.art * RAY));
        dss.vat.file(dst.ilk, "line", totalLine);

        // 2. Pre-mint enough Dai liquidity to clear `src.psm`.
        DssLitePsmLike(dst.psm).file("buf", src.art);
        DssLitePsmLike(dst.psm).file("tin", 0);
        DssLitePsmLike(dst.psm).file("tout", 0);
        DssLitePsmLike(dst.psm).fill();

        // 3. Move gems from `src.psm` to `dst.psm`.
        uint256 srcGemAmt = src.ink / DssLitePsmLike(dst.psm).to18ConversionFactor();

        // 3.1. Grab the entire collateral and the entire debt from the `src.psm` into the executing contract.
        dss.vat.grab(src.ilk, src.psm, address(this), address(this), -_int256(src.ink), -_int256(src.art));

        // 3.2. Transfer the grabbed collateral to the executing contract.
        GemJoinLike(src.gemJoin).exit(address(this), srcGemAmt);

        // 3.3. Sell the grabbed collateral gems to `dst.psm`.
        GemLike(dst.gem).approve(dst.psm, srcGemAmt);
        uint256 daiOutWad = DssLitePsmLike(dst.psm).sellGem(address(this), srcGemAmt);
        require(daiOutWad == src.art, "DssLitePsmMigration/invalid-dai-amount");

        // 3.4. Convert ERC20 Dai into Vat Dai.
        dss.dai.approve(address(dss.daiJoin), daiOutWad);
        dss.daiJoin.join(address(this), daiOutWad);

        // 3.5. Erase the bad debt generated by `vat.grab()`.
        dss.vat.heal(src.art * RAY);

        // 4. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 4.1. Remove `src.psm` from auto-line.
        autoLine.remIlk(src.ilk);

        // 4.2. Set `src.psm` debt ceiling to zero.
        dss.vat.file(src.ilk, "line", 0);
        dss.vat.file("Line", dss.vat.Line() - (src.art * RAY));

        // 4.3. Update auto-line for `dst.psm`.
        autoLine.setIlk(dst.ilk, cfg.maxLine, cfg.gap, cfg.ttl);
        autoLine.exec(dst.ilk);

        // 5. Set `dst.pam` config params.
        DssLitePsmLike(dst.psm).file("buf", cfg.buf);
        DssLitePsmLike(dst.psm).file("tin", cfg.tin);
        DssLitePsmLike(dst.psm).file("tout", cfg.tout);

        // 6. Fill `dst.psm` so there is liquidity available immediately.
        DssLitePsmLike(dst.psm).fill();
    }
}
