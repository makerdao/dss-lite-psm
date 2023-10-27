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

import "dss-test/DssTest.sol";
import {DssValue} from "./DssValue.sol";

contract DssValueTest is DssTest {
    DssValue value;

    function setUp() public {
        value = new DssValue();
    }

    function testAuth() public {
        checkAuth(address(value), "DssValue");
    }

    function testAuthMethods() public {
        // Revoke ward role for this contract
        GodMode.setWard(address(value), address(this), 0);
        checkModifier(address(value), "DssValue/not-authorized", [DssValue.poke.selector, DssValue.void.selector]);
    }

    function testPoke() public {
        value.poke(bytes32(uint256(1)));

        (bytes32 wut, bool haz) = value.peek();
        assertEq(wut, bytes32(uint256(1)), "Value not set");
        assertEq(haz, true, "Value set but not valid");

        assertEq(value.read(), bytes32(uint256(1)), "Value cannot be read");
    }

    function testVoid() public {
        value.poke(bytes32(uint256(1)));

        value.void();

        (, bool haz) = value.peek();
        assertEq(haz, false, "Value still set");
    }
}
