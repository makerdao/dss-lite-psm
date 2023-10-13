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
import {DssPocket} from "./DssPocket.sol";

interface ChainlogLike {
    function getAddress(bytes32 key) external view returns (address);
}

interface GemLike {
    function allowance(address owner, address spender) external view returns (uint256);
}

contract DssPocketTest is DssTest {
    ChainlogLike immutable chainlog = ChainlogLike(vm.envAddress("CHANGELOG"));

    address mgr = address(0x1337);
    DssPocket pocket;
    GemLike usdc;

    function setUp() public {
        vm.createSelectFork("mainnet");
        usdc = GemLike(chainlog.getAddress("USDC"));
        pocket = new DssPocket(address(usdc));
    }

    function testAuth() public {
        checkAuth(address(pocket), "DssPocket");
    }

    function testAuthMethods() public {
        // Revoke ward role for this contract
        GodMode.setWard(address(pocket), address(this), 0);
        checkModifier(address(pocket), "DssPocket/not-authorized", [DssPocket.hope.selector, DssPocket.nope.selector]);
    }

    function testApprovalForGemOnHopeNope() public {
        pocket.hope(mgr);
        assertEq(usdc.allowance(address(pocket), mgr), type(uint256).max, "Infinite approval was not given");

        pocket.nope(mgr);
        assertEq(usdc.allowance(address(pocket), mgr), 0, "Approval was not revoked");
    }
}
