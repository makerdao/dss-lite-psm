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

interface GemLike {
    function approve(address, uint256) external;
}

/**
 * @title A container for gems.
 * @notice Holds `gem` on behalf of other addresses.
 * @dev Can grant or revoke infinite `gem` approvals.
 */
contract DssPocket {
    /// @notice The token to be held in this contract.
    GemLike public immutable gem;

    /// @notice Addresses with admin access on this contract. `wards[usr]`.
    mapping(address => uint256) public wards;

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
     * @notice `usr` was granted permission to spend gems.
     * @param usr The user address.
     */
    event Hope(address indexed usr);
    /**
     * @notice `usr`'s permission to spend gems was revoked.
     * @param usr The user address.
     */
    event Nope(address indexed usr);


    modifier auth() {
        require(wards[msg.sender] == 1, "DssPocket/not-authorized");
        _;
    }

    /**
     * @param gem_ The token to be held in this contract.
     */
    constructor(address gem_) {
        gem = GemLike(gem_);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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
     * @notice Grants `usr` permission to spend `gem` on behalf of this contract.
     * @param usr The user address.
     */
    function hope(address usr) external auth {
        gem.approve(usr, type(uint256).max);
        emit Hope(usr);
    }

    /**
     * @notice Revokes `usr` permission to spend `gem` on behalf of this contract.
     * @param usr The user address.
     */
    function nope(address usr) external auth {
        gem.approve(usr, 0);
        emit Nope(usr);
    }
}
