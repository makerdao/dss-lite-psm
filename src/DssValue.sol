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

/**
 * @title A permissioned price feed.
 * @dev Adapted from https://github.com/dapphub/ds-value/blob/4049ecd2652a39cbab464bb1c2c627985f720f97/src/value.sol
 */
contract DssValue {
    /// @notice Addresses with admin access on this contract. `wards[usr]`.
    mapping(address => uint256) public wards;
    /// @notice Whether the price feed has a valid value or not.
    bool has;
    /// @notice The current value.
    bytes32 val;

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
     * @notice The value for the feed was set.
     * @param wut The value.
     */
    event Poke(bytes32 wut);
    /**
     * @notice The value for the feed was removed.
     */
    event Void();

    modifier auth() {
        require(wards[msg.sender] == 1, "DssValue/not-authorized");
        _;
    }

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

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
     * @notice Set a value for the price feed.
     * @param wut The value.
     */
    function poke(bytes32 wut) external auth {
        val = wut;
        has = true;

        emit Poke(wut);
    }

    /**
     * @notice Clears the current value for the price feed.
     */
    function void() external auth {
        val = bytes32(0);
        has = false;

        emit Void();
    }

    /**
     * @notice Tries to obtain the current value from the feed.
     * @return wut The value.
     * @return haz Whether the returned value is valid or not.
     */
    function peek() public view returns (bytes32 wut, bool haz) {
        return (val, has);
    }

    /**
     * @notice Obtains the current value from the feed.
     * @dev Reverts if the value is not valid.
     * @return wut The value.
     */
    function read() external view returns (bytes32 wut) {
        bool haz;
        (wut, haz) = peek();
        require(haz, "DssValue/haz-not");
        return wut;
    }
}
