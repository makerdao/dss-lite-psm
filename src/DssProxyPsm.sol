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
    function move(address src, address dst, uint256 rad) external;
    function slip(bytes32 ilk, address usr, int256 wad) external;
    function suck(address u, address v, uint256 rad) external;
    function ilks(bytes32)
        external
        view
        returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
}

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transferFrom(address from, address to, uint256 value) external returns(bool);
    function balanceOf(address owner) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface DaiJoinLike {
    function exit(address usr, uint256 wad) external;
    function join(address usr, uint256 wad) external;
    function dai() external view returns (address);
    function vat() external view returns (address);
}

contract DssProxyPsm {
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

    /// @notice The ultimate holder of the funds.
    /// @dev `keg` **MUST** give infinite approval for `gem` to this contract.
    address public immutable keg;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping (address => uint256) public wards;

    /// @notice Maker Protocol balance sheet.
    address public vow;

    /// @notice The max amount of pre-minted Dai to be held in this contract.
    /// @dev `wad` precision.
    uint256 public hwm;
    /// @dev `wad` precision.
    /// @notice The min amount of pre-minted Dai to be held in this contract.
    uint256 public lwm;

    /// @notice Toll in.
    /// @dev `wad` precision.
    int256 public tin;
    /// @notice Toll out.
    /// @dev `wad` precision.
    int256 public tout;

    /// @dev Signed `wad` precision.
    int256 internal constant SWAD = 10 ** 18;
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
     * @param what The changed parameter name. ["lwm", "hwm"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, uint256 data);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, int256 data);
    /**
     * @notice The contract was refilled with Dai.
     * @param wad The amount of Dai refilled.
     */
    event Refill(uint256 wad);
    /**
     * @notice The contract was drained of excess Dai.
     * @param wad The amount of Dai drained.
     */
    event Drain(uint256 wad);
    /**
     * @notice A user sold `gem` for Dai>
     * @param owner The user address.
     * @param amt The amount of `gem` sold.
     * @param fee The amount of fees paid to/received by the user.
     */
    event SellGem(address indexed owner, uint256 amt, int256 fee);
    /**
     * @notice A user bought `gem` with Dai.
     * @param owner The user address.
     * @param amt The amount of `gem` bought.
     * @param fee The amount of fees paid to/received by the user.
     */
    event BuyGem(address indexed owner, uint256 amt, int256 fee);
    /**
     * @notice A user has gotten `gem` tokens after Emergency Shutdown
     * @param usr The user address.
     * @param amt The amount of `gem` received.
     */
    event Exit(address indexed usr, uint256 amt);

    modifier auth() {
        require(wards[msg.sender] == 1, "ProxyPsm/not-authorized");
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
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    ///@dev Safely converts uint256 to int256. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    /// @dev Divide, but round up.
    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x + y - 1) / y;
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
            revert("ProxyPsm/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. ["lwm", "hwm"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, uint256 data) external auth {
        if (what == "lwm") {
            require(data <= hwm, "ProxyPsm/lwm-too-high");
            lwm = data;
        } else if (what == "hwm") {
            require(data >= lwm, "ProxyPsm/hwm-too-low");
            hwm = data;
        } else {
            revert("ProxyPsm/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, int256 data) external auth {
        require(-SWAD <= data && data <= SWAD, "ProxyPsm/out-of-range");

        if (what == "tin") {
            tin = data;
        } else if (what == "tout") {
            tout = data;
        } else {
            revert("ProxyPsm/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Mints Dai up to the estabilished `hwm` limit.
     * @dev After a call to this function, the following condition must hold:
     *      lwm <= dai.balanceOf(this) <= hwm
     * @return refilled The amount refilled [`wad`].
     */
    function refill() external returns (uint256 refilled) {
        uint256 balance = dai.balanceOf(address(this));
        require(balance < hwm, "ProxyPsm/refill-unavailable");

        unchecked {
            refilled = hwm - balance;
        }

        _doRefill(refilled);
    }

    /**
     * @notice Mints Dai into this contract.
     * @dev The caller of this funciton is meant to check whether the value is within the limits or not.
     * @param refilled The amount to refill [`wad`].
     */
    function _doRefill(uint256 refilled) internal {
        vat.slip(ilk, keg, _int256(refilled));
        vat.frob(ilk, address(this), keg, address(this), _int256(refilled), _int256(refilled));
        daiJoin.exit(address(this), refilled);

        emit Refill(refilled);
    }

    /**
     * @notice Drains any excess of Dai.
     * @dev After a call to this function, the following condition must hold:
     *      dai.balanceOf(this) == hwm
     * @return drained The amount drained [`wad`].
     */
    function drain() external returns (uint256 drained) {
        uint256 balance = dai.balanceOf(address(this));
        require(balance > hwm, "ProxyPsm/drain-unavailable");

        unchecked {
            drained = balance - hwm;
        }

        daiJoin.join(address(this), drained);
        vat.frob(ilk, address(this), keg, address(this), -_int256(drained), -_int256(drained));
        vat.slip(ilk, keg, -_int256(drained));

        emit Drain(drained);
    }

    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        uint256 gemWad = gemAmt * to18ConversionFactor;
        daiInWad = gemWad;

        int256 fee = _int256(gemWad) * tout / SWAD;
        if (fee > 0) {
            // Positive fee: more Dai will be transfered to this contract.
            daiInWad += uint256(fee);
        } else if (fee < 0) {
            // Negative fee: less Dai will be transfered to this contract.
            // Since `tout` is bounded to 100%, this can never overflow.
            unchecked {
                daiInWad -= uint256(-fee);
            }
        }

        require(dai.transferFrom(msg.sender, address(this), daiInWad), "ProxyPsm/dai-transfer-failed");
        require(gem.transferFrom(keg, usr, gemAmt), "ProxyPsm/gem-transfer-failed");

        emit BuyGem(usr, gemAmt, fee);
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad) {
        uint256 gemWad = gemAmt * to18ConversionFactor;
        daiOutWad = gemWad;

        int256 fee = _int256(gemWad) * tin / SWAD;
        if (fee > 0) {
            // Positive fee: less Dai will be transfered from this contract.
            // Since `tin` is bounded to 100%, this can never underflow.
            unchecked {
                daiOutWad -= uint256(fee);
            }
        } else if (fee < 0) {
            // Negative fee: more Dai will be transfered from this contract.
            daiOutWad += uint256(-fee);
        }

        uint256 daiBalance = dai.balanceOf(address(this));
        // Trigger a refill only if there is not enough Dai to cover the gem sell
        // or if the remaining Dai after the sell would be lower than `lwm`.
        if (daiBalance < daiOutWad || (daiBalance - daiOutWad) < lwm) {
            // Make sure the balance of Dai for this contract after the execution is `hwm`.
            _doRefill(hwm + daiOutWad - daiBalance);
        }

        require(gem.transferFrom(msg.sender, keg, gemAmt), "ProxyPsm/gem-transfer-failed");
        require(dai.transfer(usr, daiOutWad), "ProxyPsm/dai-transfer-failed");

        emit SellGem(usr, gemAmt, fee);
    }

    function exit(address usr, uint256 gemAmt) external {
        uint256 gemWad = gemAmt * to18ConversionFactor;

        vat.slip(ilk, msg.sender, -_int256(gemWad));
        require(gem.transferFrom(keg, usr, gemAmt), "ProxyPsm/gem-transfer-failed");

        emit Exit(usr, gemAmt);
    }
}
