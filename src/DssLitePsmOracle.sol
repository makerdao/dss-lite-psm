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

interface VatLike {
    function live() external view returns (uint256);
}

interface PsmLike {
    function vat() external view returns (address);
    function fix() external view returns (uint256);
}

contract DssLitePsmOracle {
    mapping (address => uint256) public wards;
    
    PsmLike public immutable psm;
    VatLike public immutable vat;

    uint256 internal constant WAD = 10 ** 18;

    constructor(address psm_) {
        psm = PsmLike(psm_);
        vat = VatLike(psm.vat());
    }

    function peek() public view returns (uint256 val, bool ok) {
        val = WAD;
        ok = vat.live() == 1 || psm.fix() > 0;
    }

    function read() external view returns (uint256 val) {
        bool ok;
        (val, ok) = peek();
        require(ok, "DssLitePsmOracle/psm-not-caged-after-shutdown"); // In order to stop end.cage(ilk) until the PSM is caged
    }
}
