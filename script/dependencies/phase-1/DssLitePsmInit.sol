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

struct DssLitePsmInitConfig {
    bytes32 psmKey;
    bytes32 pocketKey;
    bytes32 psmMomKey;
    address pocket;
    address pip;
    uint256 buf;
    uint256 tin;
    uint256 tout;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
}

interface DssLitePsmLike {
    function daiJoin() external view returns (address);
    function file(bytes32, address) external;
    function file(bytes32, uint256) external;
    function fill() external returns (uint256);
    function gem() external view returns (address);
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
}

library DssLitePsmInit {
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

    function init(DssInstance memory dss, DssLitePsmInstance memory inst, DssLitePsmInitConfig memory cfg) internal {
        // Sanity checks
        require(cfg.psmKey != cfg.pocketKey, "DssLitePsmInit/dst-psm-same-key-pocket");

        require(cfg.buf > 0, "DssLitePsmInit/invalid-buf");
        require(cfg.gap > 0, "DssLitePsmInit/invalid-gap");

        require(DssLitePsmLike(inst.litePsm).daiJoin() == address(dss.daiJoin), "DssLitePsmInit/dai-join-mismatch");
        require(DssLitePsmLike(inst.litePsm).pocket() == cfg.pocket, "DssLitePsmInit/pocket-mismatch");

        bytes32 ilk = DssLitePsmLike(inst.litePsm).ilk();
        address gem = DssLitePsmLike(inst.litePsm).gem();

        IlkRegistryLike reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));

        // 0. Ensure `litePsm` can spend `gem` on behalf of `pocket`.
        require(
            GemLike(gem).allowance(cfg.pocket, inst.litePsm) == type(uint256).max,
            "DssLitePsmInit/invalid-pocket-allowance"
        );

        // 1. Initialize the new ilk
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.spotter.file(ilk, "mat", 1 * RAY);
        require(uint256(PipLike(cfg.pip).read()) == 1 * WAD, "DssLitePsmInit/invalid-pip-val");
        dss.spotter.file(ilk, "pip", cfg.pip);
        dss.spotter.poke(ilk);

        // 2. Initial `litePsm` setup

        {
            // Set `ink` to the largest value that won't cause an overflow for `ink * spot`.
            // Notice that `litePsm` assumes that:
            //   a. `spotter.par == RAY`
            //   b. `vat.ilks[ilk].spot == RAY`
            int256 vink = int256(type(uint256).max / RAY);
            dss.vat.slip(ilk, inst.litePsm, vink);
            dss.vat.grab(ilk, inst.litePsm, inst.litePsm, address(0), vink, 0);
        }

        // 3. Update auto-line.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        autoLine.setIlk(ilk, cfg.maxLine, cfg.gap, cfg.ttl);
        autoLine.exec(ilk);

        // 4. Set `litePsm` config params.
        DssLitePsmLike(inst.litePsm).file("buf", cfg.buf);
        DssLitePsmLike(inst.litePsm).file("tin", cfg.tin);
        DssLitePsmLike(inst.litePsm).file("tout", cfg.tout);
        DssLitePsmLike(inst.litePsm).file("vow", dss.chainlog.getAddress("MCD_VOW"));

        // 7. Fill `litePsm` so there is liquidity available immediately.
        DssLitePsmLike(inst.litePsm).fill();

        // 8. Rely `mom` on `litePsm`
        DssLitePsmLike(inst.litePsm).rely(inst.mom);

        // 9. Set the chief as authority for `mom`.
        DssLitePsmMomLike(inst.mom).setAuthority(dss.chainlog.getAddress("MCD_ADM"));

        // 10. Add `litePsm` to `IlkRegistry`
        reg.put(
            ilk,
            address(0), // No `gemJoin` for `litePsm`
            gem,
            GemLike(gem).decimals(),
            REG_CLASS_JOINLESS,
            cfg.pip,
            address(0), // No `clip` for `litePsm`
            GemLike(gem).name(),
            GemLike(gem).symbol()
        );

        // 11. Add `litePsm`, `mom` and `pocket` to the chainlog.
        dss.chainlog.setAddress(cfg.psmKey, inst.litePsm);
        dss.chainlog.setAddress(cfg.psmMomKey, inst.mom);
        dss.chainlog.setAddress(cfg.pocketKey, cfg.pocket);
    }
}
