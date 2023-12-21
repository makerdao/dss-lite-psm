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

interface DssLitePsmLike {
    function file(bytes32, uint256) external;
    function HALTED() external view returns (uint256);
}

interface AuthorityLike {
    function canCall(address, address, bytes4) external view returns (bool);
}

/**
 * @title A mom for `DssLitePsm` instances.
 * @notice Bypass governance delay to halt selling or buying gems in a `DssLitePsm` instance.
 */
contract DssLitePsmMom {
    enum Flow {
        SELL, // Only `sellGem`
        BUY, // Only `buyGem`
        BOTH // Both at the same time
    }

    /// @notice The owner of this contract.
    address public owner;
    /// @notice The authority to delegate authentication to.
    address public authority;

    /**
     * @notice The owner of this contract was set.
     * @param _owner The new owner.
     */
    event SetOwner(address indexed _owner);
    /**
     * @notice The authority of this contract was set.
     * @param _authority The new authority.
     */
    event SetAuthority(address indexed _authority);
    /**
     * @notice A PSM inflow or outflow was halted.
     * @param psm The PSM address.
     * @param what The halted flow. ["tin", "tout"].
     */
    event Halt(address indexed psm, Flow indexed what);

    modifier onlyOwner() {
        require(msg.sender == owner, "DssLitePsmMom/not-owner");
        _;
    }

    modifier auth() {
        require(isAuthorized(msg.sender, msg.sig), "DssLitePsmMom/not-authorized");
        _;
    }

    /**
     * @notice Returns whether or not the function identified by `sig` can be called by `src`.
     * @param src The caller address.
     * @param sig The selector of the function being called.
     */
    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == address(0)) {
            return false;
        } else {
            return AuthorityLike(authority).canCall(src, address(this), sig);
        }
    }

    constructor() {
        owner = msg.sender;
        emit SetOwner(msg.sender);
    }

    /*//////////////////////////////////
       Governance actions with delay
    //////////////////////////////////*/

    /**
     * @notice Sets a new owner for this contract;
     * @param owner_ The new owner address.
     */
    function setOwner(address owner_) external onlyOwner {
        owner = owner_;
        emit SetOwner(owner_);
    }

    /**
     * @notice Sets a new authority for this contract;
     * @param authority_ The new authority address.
     */
    function setAuthority(address authority_) external onlyOwner {
        authority = authority_;
        emit SetAuthority(authority_);
    }

    /*//////////////////////////////////
      Governance actions without delay
    //////////////////////////////////*/

    /**
     * @notice Halts either inflow or outflow of gems from the PSM.
     * @param psm The PSM address.
     * @param what The halted flow. [0 = `sellGem`, 1 = `buyGem`, 2 = `both`]
     */
    function halt(address psm, Flow what) external auth {
        uint256 halted = DssLitePsmLike(psm).HALTED();

        if (what == Flow.SELL || what == Flow.BOTH) {
            DssLitePsmLike(psm).file("tin", halted);
        }

        if (what == Flow.BUY || what == Flow.BOTH) {
            DssLitePsmLike(psm).file("tout", halted);
        }

        emit Halt(psm, what);
    }
}
