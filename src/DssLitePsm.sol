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

interface VatLike {
    function hope(address usr) external;
    function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function ilks(bytes32)
        external
        view
        returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
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
 *      4. The `keg` has given infinite approval for `gem` to this contract.
 */
contract DssLitePsm {
    /// @notice Maker Protocol core engine.
    VatLike public immutable vat;

    /// @notice Collateral type identifier.
    bytes32 public immutable ilk;

    /// @notice Gem to exchange with Dai.
    GemLike public immutable gem;

    /// @notice Precision conversion factor for `gem`, since Dai is expected to always have 18 decimals.
    uint256 internal immutable to18ConversionFactor;

    /// @notice Dai adapter.
    DaiJoinLike public immutable daiJoin;

    /// @notice Dai token.
    GemLike public immutable dai;

    /// @notice The ultimate holder of the gems.
    /// @dev `keg` **MUST** give infinite approval for `gem` to this contract.
    address public immutable keg;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;

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
    uint256 public fees;

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
    event Gulp(uint256 wad);
    /**
     * @notice A user sold `gem` for Dai>
     * @param owner The user address.
     * @param amt The amount of `gem` sold.
     * @param fee The amount of fees paid by the user.
     */
    event SellGem(address indexed owner, uint256 amt, uint256 fee);
    /**
     * @notice A user bought `gem` with Dai.
     * @param owner The user address.
     * @param amt The amount of `gem` bought.
     * @param fee The amount of fees paid by the user.
     */
    event BuyGem(address indexed owner, uint256 amt, uint256 fee);
    /**
     * @notice A user has gotten `gem` tokens after Emergency Shutdown
     * @param usr The user address.
     * @param amt The amount of `gem` received.
     */
    event Redeem(address indexed usr, uint256 amt);

    modifier auth() {
        require(wards[msg.sender] == 1, "LitePsm/not-authorized");
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
                Bookkeeping
    //////////////////////////////////*/

    /**
     * @notice Mints Dai into this contract up to the debt ceiling.
     * @return wad The amount filled.
     */
    function fill() public returns (uint256 wad) {
        // There is only 1 `urn`, so we can use `ilk.Art` instead of `urn.art`.
        // `rate` is assumed to be 1 (10 ** 27)
        // `spot` is assumed to be 1 (10 ** 27)
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk); // ilk = LIGHT_PSM_USDC_A - 1.24B
        uint256 debt = Art * RAY;
        require(line > debt && (wad = (line - debt) / RAY) > 0, "LitePsm/fill-unavailable");

        vat.slip(ilk, address(this), _int256(wad));
        vat.frob(ilk, address(this), address(this), address(this), _int256(wad), _int256(wad));
        daiJoin.exit(address(this), wad);

        emit Fill(wad);
    }

    /**
     * @notice Burns any excess of Dai from this contract.
     * @return wad The amount trimmed.
     */
    function trim() external returns (uint256 wad) {
        // There is only 1 `urn`, so we can use `ilk.Art` instead of `urn.art`.
        // `rate` is assumed to be 1 (10 ** 27)
        // `spot` is assumed to be 1 (10 ** 27)
        (uint256 Art,,, uint256 line,) = vat.ilks(ilk);
        uint256 debt = Art * RAY;
        require(debt > line && (wad = (debt - line) / RAY) > 0, "LitePsm/trim-unavailable");

        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), address(this), -_int256(wad), -_int256(wad));
        vat.slip(ilk, address(this), -_int256(wad));

        emit Trim(wad);
    }

    /**
     * @notice Incorporates any outstanding accumulated fees into the surplus buffer.
     * @return wad The amount added to the surplus buffer.
     */
    function gulp() external returns (uint256 wad) {
        require(vow != address(0), "LitePsm/gulp-without-vow");
        require(fees > 0, "LitePsm/gulp-unavailable");

        daiJoin.join(vow, fees);
        wad = fees;
        fees = 0;

        emit Gulp(wad);
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
        uint256 gemWad = gemAmt * to18ConversionFactor;
        uint256 fee = gemWad * tin / WAD;
        daiOutWad = gemWad;

        if (fee > 0) {
            fees += fee;
            // Since `tin` is bounded to 100%, this can never underflow.
            unchecked {
                daiOutWad -= fee;
            }
        }

        // Trigger a fill only if there is not enough Dai to cover the gem sell.
        if (dai.balanceOf(address(this)) < daiOutWad) {
            fill();
        }

        require(gem.transferFrom(msg.sender, keg, gemAmt), "LitePsm/gem-transfer-failed");
        require(dai.transfer(usr, daiOutWad), "LitePsm/dai-transfer-failed");

        emit SellGem(usr, gemAmt, fee);
    }

    /**
     * @notice Swaps Dai into `gem`.
     * @param usr The destination of the swapped gems.
     * @param gemAmt The amount of gem to swap. [`gem` precision].
     * @return daiInWad The amount of Dai required for swapping.
     */
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        uint256 gemWad = gemAmt * to18ConversionFactor;
        uint256 fee = gemWad * tout / WAD;
        daiInWad = gemWad;

        if (fee > 0) {
            fees += fee;
            daiInWad += fee;
        }

        require(dai.transferFrom(msg.sender, address(this), daiInWad), "LitePsm/dai-transfer-failed");
        require(gem.transferFrom(keg, usr, gemAmt), "LitePsm/gem-transfer-failed");

        emit BuyGem(usr, gemAmt, fee);
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    /**
     * @notice Withdraws `gem` after Emergency Shutdown.
     * @param usr The destination of the gems.
     * @param gemAmt The amount of gem to withdraw. [`gem` precision].
     */
    function redeem(address usr, uint256 gemAmt) external {
        uint256 gemWad = gemAmt * to18ConversionFactor;

        vat.slip(ilk, msg.sender, -_int256(gemWad));
        require(gem.transferFrom(keg, usr, gemAmt), "LitePsm/gem-transfer-failed");

        emit Redeem(usr, gemAmt);
    }
}
