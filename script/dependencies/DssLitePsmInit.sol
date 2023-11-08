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
import {DssLitePsmInstance} from "./DssLitePsmDeploy.sol";

struct DssLitePsmInitConfig {
    bytes32 srcPsmKey;
    bytes32 dstPsmKey;
    bytes32 dstPocketKey;
    uint256 buf;
    uint256 tin;
    uint256 tout;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
}

interface DssLitePsmLike {
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

interface DssPocketLike {
    function gem() external view returns (address);
    function hope(address) external;
    function rely(address) external;
}

interface DssPsmLike {
    function gemJoin() external view returns (address);
    function ilk() external view returns (bytes32);
}

interface PipLike {
    function read() external view returns (bytes32);
}

interface GemJoinLike {
    function exit(address, uint256) external;
    function gem() external view returns (address);
}

interface GemLike {
    function approve(address, uint256) external;
}

interface AutoLineLike {
    function exec(bytes32) external returns (uint256);
    function remIlk(bytes32) external;
    function setIlk(bytes32, uint256, uint256, uint256) external;
}

library DssLitePsmInit {
    /// @dev Workaround to explicitly revert with an arithmetic error.
    string internal constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAY = 10 ** 27;

    ///@dev Safely converts `uint256` to `int256`. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) internal {
        // Sanity checks
        require(cfg.srcPsmKey != cfg.dstPsmKey, "DssLitePsmInit/src-psm-same-key-dst-psm");
        require(cfg.srcPsmKey != cfg.dstPocketKey, "DssLitePsmInit/src-psm-same-key-pocket");
        require(cfg.dstPsmKey != cfg.dstPocketKey, "DssLitePsmInit/dst-psm-same-key-pocket");

        require(DssLitePsmLike(inst.litePsm).pocket() == inst.pocket, "DssLitePsmInit/pocket-address-mismatch");
        require(DssLitePsmLike(inst.litePsm).daiJoin() == address(dss.daiJoin), "DssLitePsmInit/dai-join-mismatch");

        bytes32 ilk = DssLitePsmLike(inst.litePsm).ilk();

        address srcPsm = dss.chainlog.getAddress(cfg.srcPsmKey);
        bytes32 srcIlk = DssPsmLike(srcPsm).ilk();
        require(srcIlk != ilk, "DssLitePsmInit/invalid-ilk-reuse");

        GemJoinLike srcGemJoin = GemJoinLike(DssPsmLike(srcPsm).gemJoin());
        address gem = DssLitePsmLike(inst.litePsm).gem();
        {
            require(DssPocketLike(inst.pocket).gem() == gem, "DssLitePsmInit/pocket-gem-mismatch");
            require(srcGemJoin.gem() == gem, "DssLitePsmInit/src-gem-mismatch");
        }

        uint256 srcArt;
        uint256 srcLine;
        {
            uint256 srcIlkArt;
            uint256 srcInk;
            (srcIlkArt,,, srcLine,) = dss.vat.ilks(srcIlk);
            (srcInk, srcArt) = dss.vat.urns(srcIlk, srcPsm);
            require(srcIlkArt == srcArt, "DssLitePsmInit/src-ilk-urn-art-mismatch");
            require(srcInk == srcArt, "DssLitePsmInit/src-ink-art-mismatch");
        }

        // 0. Wire `litePsm` and `pocket`.
        DssPocketLike(inst.pocket).hope(inst.litePsm);

        // 1. Initialize the new ilk
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.spotter.file(ilk, "mat", 1 * RAY);
        {
            (address pip,) = dss.spotter.ilks(srcIlk);
            require(uint256(PipLike(pip).read()) == 1 * WAD, "DssLitePsmInit/invalid-pip-val");
            dss.spotter.file(ilk, "pip", pip);
            dss.spotter.poke(ilk);
        }

        // 2. Set interim params to accommodate the new PSM.
        {
            uint256 initLine = srcArt * RAY;
            // Ensure we will be able to call `fill` on step 7.
            require(cfg.maxLine > initLine, "DssLitePsmInit/max-line-too-low");
            dss.vat.file("Line", dss.vat.Line() + initLine);
            dss.vat.file(ilk, "line", initLine);
        }

        // 3. Initial `litePsm` setup

        // 3.1. Add unlimited virtual collateral to `litePsm`.
        {
            // Set `ink` to the largest value that won't cause an overflow for `ink * spot`.
            // Notice that `litePsm` assumes that:
            //   a. `spotter.par == RAY`
            //   b. `vat.ilks[ilk].spot == RAY`
            int256 vink = int256(type(uint256).max / RAY);
            dss.vat.slip(ilk, inst.litePsm, vink);
            dss.vat.grab(ilk, inst.litePsm, inst.litePsm, address(0), vink, 0);
        }

        // 3.2. Pre-mint enough Dai liquidity to clear `srcPsm`.
        DssLitePsmLike(inst.litePsm).file("buf", srcArt);
        DssLitePsmLike(inst.litePsm).file("tin", 0);
        DssLitePsmLike(inst.litePsm).file("tout", 0);
        DssLitePsmLike(inst.litePsm).fill();

        // 4. Move PSM gems.

        // 4.1. Grab the entire collateral and the entire debt from the source PSM into the executing contract.
        {
            // Notice that we enforce that `srcInk == srcArt`.
            int256 dart = -_int256(srcArt);
            dss.vat.grab(srcIlk, srcPsm, address(this), address(this), dart, dart);
        }

        // 4.2. Transfer the grabbed collateral to the executing contract.
        uint256 srcGemAmt = srcArt / DssLitePsmLike(inst.litePsm).to18ConversionFactor();
        srcGemJoin.exit(address(this), srcGemAmt);

        // 4.3. Sell the grabbed collateral gems into the new PSM.
        GemLike(gem).approve(inst.litePsm, srcGemAmt);
        uint256 daiOutWad = DssLitePsmLike(inst.litePsm).sellGem(address(this), srcGemAmt);
        require(daiOutWad == srcArt, "DssLitePsmInit/invalid-dai-amount");

        // 4.4. Convert ERC20 Dai into Vat Dai.
        dss.dai.approve(address(dss.daiJoin), daiOutWad);
        dss.daiJoin.join(address(this), daiOutWad);

        // 4.5. Erase the bad debt generated in 4.1.
        dss.vat.heal(srcArt * RAY);

        // 5. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));

        // 5.1. Set `srcPsm` debt ceiling to zero.
        autoLine.remIlk(srcIlk);
        dss.vat.file(srcIlk, "line", 0);
        dss.vat.file("Line", dss.vat.Line() - srcLine);

        // 5.2. Set auto-line for the new PSM.
        autoLine.setIlk(ilk, cfg.maxLine, cfg.gap, cfg.ttl);
        autoLine.exec(ilk);

        // 6. Set `litePsm` config params.
        DssLitePsmLike(inst.litePsm).file("buf", cfg.buf);
        DssLitePsmLike(inst.litePsm).file("tin", cfg.tin);
        DssLitePsmLike(inst.litePsm).file("tout", cfg.tout);

        // 7. Fill `litePsm` so there is liquidity available immediately.
        DssLitePsmLike(inst.litePsm).fill();

        // 8. Add `litePsm` and `pocket` to the chainlog.
        dss.chainlog.setAddress(cfg.dstPsmKey, inst.litePsm);
        dss.chainlog.setAddress(cfg.dstPocketKey, inst.pocket);
    }
}
