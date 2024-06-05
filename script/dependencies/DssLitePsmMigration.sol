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
import {DssLitePsmInstance} from "./DssLitePsmInstance.sol";

struct MigrationConfig {
    bytes32 srcPsmKey; // Chainlog key
    bytes32 dstPsmKey; // Chainlog key
    uint256 dstWant; // [wad] Gems to move from `srcPsm` to `dstPsm`
    uint256 dstBuf; // [wad] Amount of pre-minted Dai
}

struct SrcPsm {
    bytes32 ilk;
    address psm;
    address gem;
    address gemJoin;
    uint256 line; // [rad]
    uint256 ink; // [wad]
    uint256 art; // [wad]
}

struct DstPsm {
    bytes32 ilk;
    address psm;
    address gem;
    uint256 line; // [rad]
    uint256 art; // [wad]
    uint256 buf; // [wad]
    uint256 tin; // [wad] 10**18 == 100%
    uint256 tout; // [wad] 10**18 == 100%
}

struct MigrationResult {
    uint256 sap; // [wad] Amount of collateral actually moved;
    SrcPsm src;
    DstPsm dst;
}


interface DssLitePsmLike {
    function buf() external view returns (uint256);
    function daiJoin() external view returns (address);
    function file(bytes32, address) external;
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function gem() external view returns (address);
    function ilk() external view returns (bytes32);
    function pocket() external view returns (address);
    function rely(address) external;
    function sellGem(address, uint256) external returns (uint256);
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
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
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external;
    function decimals() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function remIlk(bytes32) external;
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

interface IlkRegistryLike {
    function put(
        bytes32 _ilk,
        address _join,
        address _gem,
        uint256 _dec,
        uint256 _class,
        address _pip,
        address _xlip,
        string memory _name,
        string memory _symbol
    ) external;
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

    /// @dev Safely converts `uint256` to `int256`. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    /// @dev Returns the difference between `x` and `y` or zero if `x` is lower than `y`.
    function _subcap(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? 0 : x - y;
    }

    function _getParamsFromKeys(DssInstance memory dss, bytes32 srcPsmKey, bytes32 dstPsmKey)
        internal
        view
        returns (SrcPsm memory src, DstPsm memory dst)
    {
        // Sanity checks
        require(srcPsmKey != dstPsmKey, "DssLitePsmMigration/src-psm-same-key-dst-psm");

        IlkRegistryLike reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));

        dst.psm = dss.chainlog.getAddress(dstPsmKey);
        dst.ilk = DssLitePsmLike(dst.psm).ilk();
        dst.gem = reg.gem(dst.ilk);
        (, dst.art) = dss.vat.urns(dst.ilk, dst.psm);
        dst.buf = DssLitePsmLike(dst.psm).buf();
        dst.tin = DssLitePsmLike(dst.psm).tin();
        dst.tout = DssLitePsmLike(dst.psm).tout();

        src.psm = dss.chainlog.getAddress(srcPsmKey);
        src.ilk = DssPsmLike(src.psm).ilk();
        src.gem = reg.gem(src.ilk);
        src.gemJoin = reg.join(src.ilk);
        (src.ink, src.art) = dss.vat.urns(src.ilk, src.psm);

        require(dst.ilk != src.ilk, "DssLitePsmMigration/invalid-ilk-reuse");
        require(dst.gem == src.gem, "DssLitePsmMigration/dst-src-gem-mismatch");
    }

    /**
     * @dev Migrates funds from `src` to `dst`.
     * @param dss The DSS instance.
     * @param cfg [wad] The migration config.
     * @return res The state of both PSMs after migration.
     */
    function migrate(DssInstance memory dss, MigrationConfig memory cfg)
        internal
        returns (MigrationResult memory res)
    {
        (SrcPsm memory src, DstPsm memory dst) = _getParamsFromKeys(dss, cfg.srcPsmKey, cfg.dstPsmKey);

        // Sanity checks
        {
            require(src.ink > 0, "DssLitePsmMigration/src-psm-not-initialized");
            require(src.ink >= src.art, "DssLitePsmMigration/src-ink-lower-than-art");
            (, uint256 srcRate,,,) = dss.vat.ilks(src.ilk);
            (, uint256 dstRate,,,) = dss.vat.ilks(dst.ilk);
            // We assume stability fees should be set to zero for both PSMs.
            require(srcRate == RAY, "DssLitePsmMigration/invalid-src-ilk-rate");
            require(dstRate == RAY, "DssLitePsmMigration/invalid-dst-ilk-rate");
        }

        // Ensure it does not try to migrate more than the existing collateral.
        uint256 mink = _min(src.ink, cfg.dstWant);
        // Ensure it does not try to erase more than the existing debt.
        uint256 mart = _min(src.art, mink);
        // Store current params to reset them at the end.
        uint256 currentGlobalLine = dss.vat.Line();

        // 1. Set interim params to accommodate the migration.
        uint256 lineInc = (mart + cfg.dstBuf) * RAY;
        dss.vat.file("Line", currentGlobalLine + lineInc);
        dss.vat.file(dst.ilk, "line", dst.line + lineInc);

        // 2. Pre-mint enough Dai liquidity to move funds from `src.psm`.
        DssLitePsmLike(dst.psm).file("buf", mink);
        DssLitePsmLike(dst.psm).file("tin", 0);
        DssLitePsmLike(dst.psm).file("tout", 0);
        DssLitePsmLike(dst.psm).fill();

        // 3. Move gems from `src.psm` to `dst.psm`.

        // 3.1. Grab the collateral from `src.psm` into the executing contract.
        dss.vat.grab(src.ilk, src.psm, address(this), address(this), -_int256(mink), -_int256(mart));

        // 3.2. Transfer the grabbed collateral to the executing contract.
        uint256 srcGemAmt = mink / DssLitePsmLike(dst.psm).to18ConversionFactor();
        GemJoinLike(src.gemJoin).exit(address(this), srcGemAmt);

        // 3.3. Sell the grabbed collateral gems to `dst.psm`.
        GemLike(dst.gem).approve(dst.psm, srcGemAmt);
        uint256 daiOutWad = DssLitePsmLike(dst.psm).sellGem(address(this), srcGemAmt);
        require(daiOutWad == mink, "DssLitePsmMigration/invalid-dai-amount");

        // 3.4. Convert ERC20 Dai into Vat Dai.
        dss.dai.approve(address(dss.daiJoin), daiOutWad);
        dss.daiJoin.join(address(this), daiOutWad);

        // 3.5. Erase the bad debt generated by `vat.grab()`.
        dss.vat.heal(mart * RAY);

        // 3.6. Incorporate any outstanding Dai into the surplus buffer.
        // Notice: this can happen when `daiOutWad > mart` (i.e.: Vat Dai donation to `src.psm`).
        dss.vat.move(address(this), address(dss.vow), _subcap(daiOutWad, mart));

        // 4. Reset the previous params.
        DssLitePsmLike(dst.psm).file("tout", dst.tout);
        DssLitePsmLike(dst.psm).file("tin", dst.tin);
        DssLitePsmLike(dst.psm).file("buf", dst.buf);
        dss.vat.file(dst.ilk, "line", dst.line);
        dss.vat.file("Line", currentGlobalLine);

        // 5. Return the state after migration
        res.sap = mink;
        (res.src, res.dst) = _getParamsFromKeys(dss, cfg.srcPsmKey, cfg.dstPsmKey);
    }
}
