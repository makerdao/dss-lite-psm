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

interface GemLike {
    function approve(address spender, uint256 value) external;
}

/**
 * @title An airtight container for gems
 * @notice Holds `gem` on behalf of `mgr`.
 * @dev Gives infinite `gem` approval to `mgr`.
 */
contract DssKeg {
    /// @notice The allowed `gem` spender.
    address public immutable mgr;

    /// @notice The token to be held in this contract.
    GemLike public immutable gem;

    /**
     * @param mgr_ The allowed `gem` spender.
     * @param gem_ The token to be held in this contract.
     */
    constructor(address mgr_, address gem_) {
        mgr = mgr_;
        gem = GemLike(gem_);

        gem.approve(mgr_, type(uint256).max);
    }
}
