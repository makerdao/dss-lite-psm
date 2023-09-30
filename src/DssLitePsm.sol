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
pragma solidity 0.8.16;

import {console2} from "forge-std/console2.sol";

interface VatLike {
    function hope(address usr) external;
    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function ilks(bytes32)
        external
        view
        returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
    function live() external view returns (uint256);
}

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface DaiJoinLike {
    function exit(address usr, uint256 wad) external;
    function join(address usr, uint256 wad) external;
    function dai() external view returns (address);
    function vat() external view returns (address);
}

/**
 * @title A lightweight PSM implementation.
 * @notice Swaps Dai for `gem` at a 1:1 exchange rate.
 * @notice Fees `tin` and `tout` might apply.
 * @dev `gem` balance is kept in `keg` instead of this contract.
 * @dev A few assumptions are made:
 *      1. There are no other urns for the same `ilk`
 *      2. Stability fee is always zero for the `ilk`
 *      3. The `spot` price for gem is always 1.
 *      4. This contract can freely transfer `gem` on behalf of `keg`.
 */
contract DssLitePsm {
    /// @notice Collateral type identifier.
    bytes32 public immutable ilk;
    /// @notice Maker Protocol core engine.
    VatLike public immutable vat;
    /// @notice Dai adapter.
    DaiJoinLike public immutable daiJoin;
    /// @notice Dai token.
    GemLike public immutable dai;
    /// @notice Gem to exchange with Dai.
    GemLike public immutable gem;
    /// @notice Precision conversion factor for `gem`, since Dai is expected to always have 18 decimals.
    uint256 internal immutable to18ConversionFactor;
    /// @notice The ultimate holder of the gems.
    /// @dev This contract should be able freely transfer `gem` on behalf of `keg`.
    address public immutable keg;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with permission to swap with no fees. `bud[usr]`
    mapping(address => uint256) public bud;
    /// @notice Maker Protocol balance sheet.
    address public vow;
    /// @notice Fee for selling gems.
    /// @dev `wad` precision. 1 * WAD means a 100% fee.
    uint256 public tin;
    /// @notice Fee for buying gems.
    /// @dev `wad` precision. 1 * WAD means a 100% fee.
    uint256 public tout;
    /// @notice Outstanding swapping fees accumulated into this contract.
    /// @dev `wad` precision.
    uint256 public cut;

    /// @dev `wad` precision.
    uint256 internal constant WAD = 10 ** 18;
    /// @dev `ray` precision for `vat` manipulation.
    uint256 internal constant RAY = 10 ** 27;
    /// @dev Workaround to explicitly revert with an arithmetic error.
    string internal constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice `who` was granted permission to swap without any fees.
     * @param who The user address.
     */
    event Kiss(address indexed who);
    /**
     * @notice Permission revoked for `who` to swap without any fees.
     * @param who The user address.
     */
    event Diss(address indexed who);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["vow"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, uint256 data);
    /**
     * @notice The contract was filled with Dai.
     * @param wad The amount of Dai filled.
     */
    event Fill(uint256 wad);
    /**
     * @notice The contract was trimmed of excess Dai.
     * @param wad The amount of Dai trimmed.
     */
    event Trim(uint256 wad);
    /**
     * @notice Dai accumulated as swap fees was added to the surplus buffer..
     * @param wad The amount of Dai added.
     */
    event Chug(uint256 wad);
    /**
     * @notice A user sold `gem` for Dai>
     * @param owner The user address.
     * @param amt The amount of `gem` sold.
     * @param fee The fee paid by the user.
     */
    event SellGem(address indexed owner, uint256 amt, uint256 fee);
    /**
     * @notice A user bought `gem` with Dai.
     * @param owner The user address.
     * @param amt The amount of `gem` bought.
     * @param fee The fee paid by the user.
     */
    event BuyGem(address indexed owner, uint256 amt, uint256 fee);
    /**
     * @notice A user has gotten `gem` tokens after Emergency Shutdown
     * @param usr The user address.
     * @param amt The amount of `gem` received.
     */
    event Exit(address indexed usr, uint256 amt);

    modifier auth() {
        require(wards[msg.sender] == 1, "LitePsm/not-authorized");
        _;
    }

    modifier onlyBud() {
        require(bud[msg.sender] == 1, "LitePsm/not-bud");
        _;
    }

    /**
     * @param ilk_ The collateral type identifier.
     * @param gem_ The gem to exchange with Dai.
     * @param daiJoin_ The Dai adapter.
     * @param keg_ The ultimate holder of `gem`.
     */
    constructor(bytes32 ilk_, address gem_, address daiJoin_, address keg_) {
        ilk = ilk_;
        gem = GemLike(gem_);
        daiJoin = DaiJoinLike(daiJoin_);
        vat = VatLike(daiJoin.vat());
        dai = GemLike(daiJoin.dai());
        keg = keg_;

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        dai.approve(daiJoin_, type(uint256).max);
        vat.hope(daiJoin_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    ///@dev Safely converts uint256 to int256. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    ///@dev Returns the min between `x` and `y`.
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x < y ? x : y;
    }

    ///@dev Returns the max between `x` and `y`.
    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x > y ? x : y;
    }

    ///@dev Capped subtraction: returns `x - y` if `x > y` or `0` otherwise.
    function _subCap(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x > y) {
            unchecked {
                return x - y;
            }
        }
        return 0;
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Grants `who` permission to swap without any fees.
     * @param who The user address.
     */
    function kiss(address who) public auth {
        bud[who] = 1;
        emit Kiss(who);
    }

    /**
     * @notice Revokes `who` permission to swap without any fees.
     * @param who The user address.
     */
    function diss(address who) public auth {
        bud[who] = 0;
        emit Diss(who);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. ["vow"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "vow") {
            vow = data;
        } else {
            revert("LitePsm/file-unrecognized-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, uint256 data) external auth {
        require(data <= WAD, "LitePsm/out-of-range");

        if (what == "tin") {
            tin = data;
        } else if (what == "tout") {
            tout = data;
        } else {
            revert("LitePsm/file-unrecognized-param");
        }

        emit File(what, data);
    }

    /*//////////////////////////////////
                  Swapping
    //////////////////////////////////*/

    /**
     * @notice Swaps `gem` into Dai.
     * @dev If there is not enough Dai liquidity in this contract, it will pull more liquidity up to the debt ceiling
     *      automatically before proceeding with the swap. If there is not enough room in the debt ceiling to cover
     *      `daiOutWad`, the transaction will fail.
     * @param usr The destination of the swapped Dai.
     * @param gemAmt The amount of gem to swap. [`gem` precision].
     * @return daiOutWad The amount of Dai swapped.
     */
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad) {
        daiOutWad = gemAmt * to18ConversionFactor;
        uint256 fee = daiOutWad * tin / WAD;

        if (fee > 0) {
            unchecked {
                // Safe because the sum of fees can never be larger than Dai total supply.
                cut += fee;
                // Since `tin` is bounded to 100%, this can never underflow.
                daiOutWad -= fee;
            }
        }

        // Trigger a fill only if there is not enough Dai available to cover the gem sell.
        if (cash() < daiOutWad) {
            // Fill up to 2x the swapped amount + fee if there is room in the debt ceiling,
            // so the pool is perfectly balanced aftewards.
            _doFill(2 * daiOutWad + fee);
        }

        require(gem.transferFrom(msg.sender, keg, gemAmt), "LitePsm/gem-transfer-failed");
        require(dai.transfer(usr, daiOutWad), "LitePsm/dai-transfer-failed");

        emit SellGem(usr, gemAmt, fee);
        return daiOutWad;
    }

    /**
     * @notice Swaps `gem` into Dai without any fees.
     * @dev Only users whitelisted through `kiss()` can call this function.
     * @dev If there is not enough Dai liquidity in this contract, it will pull more liquidity up to the debt ceiling
     *      automatically before proceeding with the swap. If there is not enough room in the debt ceiling to cover
     *      `daiOutWad`, the transaction will fail.
     * @param usr The destination of the swapped Dai.
     * @param gemAmt The amount of gem to swap. [`gem` precision].
     * @return daiOutWad The amount of Dai swapped.
     */
    function sellGemNoFee(address usr, uint256 gemAmt) external onlyBud returns (uint256 daiOutWad) {
        daiOutWad = gemAmt * to18ConversionFactor;

        // Trigger a fill only if there is not enough Dai available to cover the gem sell.
        if (cash() < daiOutWad) {
            // Fill up to 2x the swapped amount if there is room in the debt ceiling,
            // so the pool is perfectly balanced aftewards.
            _doFill(2 * daiOutWad);
        }

        require(gem.transferFrom(msg.sender, keg, gemAmt), "LitePsm/gem-transfer-failed");
        require(dai.transfer(usr, daiOutWad), "LitePsm/dai-transfer-failed");

        emit SellGem(usr, gemAmt, 0);
        return daiOutWad;
    }

    /**
     * @notice Swaps Dai into `gem`.
     * @param usr The destination of the swapped gems.
     * @param gemAmt The amount of gem to swap. [`gem` precision].
     * @return daiInWad The amount of Dai required for swapping.
     */
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        daiInWad = gemAmt * to18ConversionFactor;
        uint256 fee = daiInWad * tout / WAD;

        if (fee > 0) {
            // Safe because the sum of fees and the swapped amount can never be larger than Dai total supply.
            unchecked {
                cut += fee;
                daiInWad += fee;
            }
        }

        require(dai.transferFrom(msg.sender, address(this), daiInWad), "LitePsm/dai-transfer-failed");
        require(gem.transferFrom(keg, usr, gemAmt), "LitePsm/gem-transfer-failed");

        emit BuyGem(usr, gemAmt, fee);
        return daiInWad;
    }

    /**
     * @notice Swaps Dai into `gem` without any fees.
     * @dev Only users whitelisted through `kiss()` can call this function.
     * @param usr The destination of the swapped gems.
     * @param gemAmt The amount of gem to swap. [`gem` precision].
     * @return daiInWad The amount of Dai required for swapping.
     */
    function buyGemNoFee(address usr, uint256 gemAmt) external onlyBud returns (uint256 daiInWad) {
        daiInWad = gemAmt * to18ConversionFactor;

        require(dai.transferFrom(msg.sender, address(this), daiInWad), "LitePsm/dai-transfer-failed");
        require(gem.transferFrom(keg, usr, gemAmt), "LitePsm/gem-transfer-failed");

        emit BuyGem(usr, gemAmt, 0);
        return daiInWad;
    }

    /*//////////////////////////////////
                Bookkeeping
    //////////////////////////////////*/

    /**
     * @notice Mints Dai into this contract to try to match USDC balance of `keg`.
     * @dev The actual minted amount can be limited by the debt ceiling (`line`).
     * @return wad The amount of Dai minted.
     */
    function fill() public returns (uint256 wad) {
        uint256 gemLiq = gem.balanceOf(address(keg)) * to18ConversionFactor;
        uint256 daiLiq = cash();
        require(gemLiq > daiLiq, "LitePsm/fill-unavailable");

        uint256 max;
        unchecked {
            max = gemLiq - daiLiq;
        }
        return _doFill(max);
    }

    /**
     * @notice Mints up to `max` Dai into this contract.
     * @dev The actual minted amount can be limited by the debt ceiling (`line`).
     * @param max The maximum amount of Dai to mint.
     * @return wad The amount of Dai minted.
     */
    function _doFill(uint256 max) internal returns (uint256 wad) {
        // There is only 1 `urn`, so we can use `ilk.Art` instead of `urn.art`.
        // `rate` is assumed to be 1 (10 ** 27)
        // `spot` is assumed to be 1 (10 ** 27)
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        uint256 debt = Art * RAY;
        require(line > debt, "LitePsm/fill-line-exceeded");

        wad = _min((line - debt) / RAY, max);

        vat.slip(ilk, address(this), _int256(wad));
        vat.frob(ilk, address(this), address(this), address(this), _int256(wad), _int256(wad));
        daiJoin.exit(address(this), wad);

        emit Fill(wad);
        return wad;
    }

    /**
     * @notice Burns any excess of Dai from this contract.
     * @dev The total outstanding debt can still be larger than the debt celing after `trim`.
     * Additional `buyGem` calls will enable further `trim` calls.
     * @return wad The amount of Dai burned.
     */
    function trim() external returns (uint256 wad) {
        wad = gush();
        require(wad > 0, "LitePsm/trim-unavailable");
        int256 swad = _int256(wad);

        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), address(this), -swad, -swad);
        vat.slip(ilk, address(this), -swad);

        emit Trim(wad);
        return wad;
    }

    /**
     * @notice Incorporates any outstanding accumulated fees into the surplus buffer.
     * @return wad The amount added to the surplus buffer.
     */
    function chug() external returns (uint256 wad) {
        require(vow != address(0), "LitePsm/chug-missing-vow");
        require(cut > 0, "LitePsm/chug-unavailable");

        daiJoin.join(vow, cut);
        wad = cut;
        cut = 0;

        emit Chug(wad);
        return wad;
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    /**
     * @notice Withdraws `gem` after Emergency Shutdown.
     * @param usr The destination of the gems.
     * @param gemAmt The amount of gem to withdraw. [`gem` precision].
     */
    function exit(address usr, uint256 gemAmt) external {
        vat.slip(ilk, msg.sender, -_int256(gemAmt * to18ConversionFactor));
        require(gem.transferFrom(keg, usr, gemAmt), "LitePsm/gem-transfer-failed");

        emit Exit(usr, gemAmt);
    }

    /*//////////////////////////////////
                  Getters
    //////////////////////////////////*/

    /**
     * @notice Returns the amount of Dai available for swapping through this contract.
     * @dev The Dai balance of this contract minus the accumulated fees.
     * @return wad The amount of Dai.
     */
    function cash() public view returns (uint256 wad) {
        return _subCap(dai.balanceOf(address(this)), cut);
    }

    /**
     * @notice Returns the missing amount of Dai that can be minted into this contract.
     * @return wad The amount of Dai.
     */
    function rush() public view returns (uint256 wad) {
        uint256 gemLiq = gem.balanceOf(address(keg)) * to18ConversionFactor;
        uint256 daiLiq = cash();
        // There is only 1 `urn`, so we can use `ilk.Art` instead of `urn.art`.
        // `rate` is assumed to be 1 (10 ** 27)
        // `spot` is assumed to be 1 (10 ** 27)
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        uint256 debt = Art * RAY;

        return _min(
            // Dai gap relative to gem liquidity.
            _subCap(gemLiq, daiLiq),
            // Remaining debt available, in `wad`.
            _subCap(line, debt) / RAY
        );
    }

    /**
     * @notice Returns the excess Dai that can be burnt from this contract.
     * @return wad The amount of Dai.
     */
    function gush() public view returns (uint256 wad) {
        uint256 daiLiq = cash();
        uint256 gemLiq = gem.balanceOf(address(keg)) * to18ConversionFactor;
        (,,, uint256 line,) = vat.ilks(ilk);

        return _max(
            // Excess Dai relative to gem liquidity.
            _subCap(daiLiq, gemLiq),
            // Excess Dai relative to the debt ceiling.
            _subCap(daiLiq, (line / RAY))
        );
    }
}
