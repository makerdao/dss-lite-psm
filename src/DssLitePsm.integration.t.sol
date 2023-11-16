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

import "dss-test/DssTest.sol";
import {DssPocket} from "src/DssPocket.sol";
import {DssLitePsm} from "src/DssLitePsm.sol";

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transfer(address to, uint256 value) external;
    function balanceOf(address owner) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface AutoLineLike {
    function exec(bytes32 _ilk) external returns (uint256);
    function setIlk(bytes32 ilk, uint256 line, uint256 gap, uint256 ttl) external;
}

abstract contract DssLitePsmBaseTest is DssTest {
    function _ilk() internal view virtual returns (bytes32);
    function _setUpGem() internal virtual returns (address);

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 ilk;
    DssInstance dss;
    AutoLineLike autoLine;
    GemLike gem;
    DssPocket pocket;
    DssLitePsm litePsm;
    uint256 buf;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(CHAINLOG);
        MCD.giveAdminAccess(dss);

        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        GodMode.setWard(address(autoLine), address(this), 1);

        // From concrete test implementations
        ilk = _ilk();
        gem = GemLike(_setUpGem());

        pocket = new DssPocket(address(gem));
        litePsm = new DssLitePsm(ilk, address(gem), address(dss.daiJoin), address(pocket));
        // Allow litePsm to spend `gem` on behalf of `pocket`.
        pocket.hope(address(litePsm));

        MCD.initIlk(dss, ilk);
        uint256 dline = 100_000_000 * RAD;
        dss.vat.file("Line", dss.vat.Line() + dline);
        dss.vat.file(ilk, "line", dline);

        // Grants 1T virtual gem collateral
        dss.vat.slip(ilk, address(litePsm), _int256(1_000_000_000_000 * WAD));
        dss.vat.grab(ilk, address(litePsm), address(litePsm), address(0), _int256(1_000_000_000_000 * WAD), 0);

        // Mints 100_000_000 gem into the test contract.
        GodMode.setBalance(address(gem), address(this), _wadToAmt(100_000_000 * WAD));
        gem.approve(address(litePsm), type(uint256).max);

        // Mints 100_000_000 Dai into the test contract.
        GodMode.setBalance(dss.dai, address(this), 100_000_000 * WAD);
        dss.dai.approve(address(litePsm), type(uint256).max);

        // pocket to give unlimited gem approval to the litePsm.
        vm.prank(address(pocket));
        gem.approve(address(litePsm), type(uint256).max);

        // Setup the vow for litePsm
        litePsm.file("vow", address(dss.vow));

        buf = 10_000_000 * WAD;
        litePsm.file("buf", buf);

        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.vow), "Vow");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
    }

    /*//////////////////////////////////
               Sanity Checks
    //////////////////////////////////*/

    function testTo18ConversionFactor() public {
        assertEq(
            litePsm.to18ConversionFactor(),
            10 ** (18 - gem.decimals()),
            "to18ConversionFactor: invalid conversion factor"
        );
    }

    function testSetUpContractDependencies() public {
        assertEq(address(pocket.gem()), address(litePsm.gem()), "sanity check: mismatching gem");
        assertEq(litePsm.pocket(), address(pocket), "sanity check: bad lightPsm.pocket()");
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    function testAuth() public {
        checkAuth(address(litePsm), "DssLitePsm");
    }

    function testAuthMethods() public {
        // Revoke ward role for this contract
        GodMode.setWard(address(litePsm), address(this), 0);
        checkModifier(
            address(litePsm), "DssLitePsm/not-authorized", [DssLitePsm.kiss.selector, DssLitePsm.diss.selector]
        );
    }

    function testTollMethods() public {
        checkModifier(
            address(litePsm),
            "DssLitePsm/not-whitelisted",
            [DssLitePsm.buyGemNoFee.selector, DssLitePsm.sellGemNoFee.selector]
        );
    }

    function testFile() public {
        /*//////////////////////////////////
                  tin, tout & buf
        //////////////////////////////////*/
        assertEq(litePsm.wards(address(this)), 1, "Invalid ward setting");

        vm.expectRevert("DssLitePsm/tin-out-of-range");
        litePsm.file("tin", 2 * WAD);

        vm.expectRevert("DssLitePsm/tout-out-of-range");
        litePsm.file("tout", 2 * WAD);

        checkFileUint(address(litePsm), "DssLitePsm", ["tin", "tout", "buf"]);

        /*//////////////////////////////////
                        vow
        //////////////////////////////////*/

        checkFileAddress(address(litePsm), "DssLitePsm", ["vow"]);
    }

    /*//////////////////////////////////
          Permissionless Swapping
    //////////////////////////////////*/

    function testSellGem() public {
        litePsm.fill();

        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, 10_000_000 * WAD, "sellGem: invalid cash after fill");

        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        uint256 daiTotalSupply = dss.dai.totalSupply();
        // Dai total supply should not be affected.
        assertEq(daiTotalSupply, pdaiTotalSupply, "sellGem: Dai total supply changed unexpectedly");

        // Available Dai liquidity should reduce by the same amount being swapped.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm - daiOutWad, "sellGem: invalid PSM Dai change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalancePocket, pgemBalancePocket + gemAmt, "sellGem: invalid pocket gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testSellGem_Fuzz_Bounded(uint256 igemAmt, uint256 gemAmt) public {
        litePsm.fill();

        // Since we are selling gem twice, we can only sell part of it in the setup.
        igemAmt = bound(igemAmt, _wadToAmt(1 * WAD), _wadToAmt(litePsm.buf() / 2 - 1));
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        gemAmt = bound(gemAmt, _wadToAmt(1 * WAD), igemAmt);
        vm.expectEmit(true, true, true, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        uint256 daiTotalSupply = dss.dai.totalSupply();
        // Dai total supply should not be affected.
        assertEq(daiTotalSupply, pdaiTotalSupply, "sellGem: Dai total supply changed unexpectedly");

        // Available Dai liquidity should reduce by the same amount being swapped.
        // Automation must kick in to rebalance the PSM.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm - daiOutWad, "sellGem: invalid cash change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalancePocket, pgemBalancePocket + gemAmt, "sellGem: invalid pocket gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");

        vm.expectEmit(true, true, true, true);
        // The unbalancing amounts to the sum of swaps.
        emit Fill(idaiOutWad + daiOutWad);
        litePsm.fill();
    }

    function testSellGem_Revert_WhenTinIsSpecialValueHalted() public {
        litePsm.file("tin", litePsm.HALTED());
        vm.expectRevert("DssLitePsm/sell-gem-halted");
        litePsm.sellGem(address(this), 1);
    }

    function testBuyGem() public {
        litePsm.fill();

        uint256 igemAmt = _wadToAmt(10_000_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        address usr = address(0xd34d);
        uint256 pgemBalanceUsr = gem.balanceOf(usr);
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

        uint256 gemAmt = _wadToAmt(3_000_000 * WAD);
        vm.expectEmit(true, true, true, true);
        emit BuyGem(usr, gemAmt, 0);
        uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

        uint256 gemBalanceUsr = gem.balanceOf(usr);
        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalanceUsr, pgemBalanceUsr + gemAmt, "buyGem: invalid usr gem balance after buyGem");
        assertEq(gemBalancePocket, pgemBalancePocket - gemAmt, "buyGem: invalid pocket gem balance after buyGem");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
        assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid cash after buyGem");
    }

    function testBuyGem_Fuzz_Bounded(uint256 igemAmt, uint256 gemAmt) public {
        litePsm.fill();

        igemAmt = bound(igemAmt, _wadToAmt(2 * WAD), _wadToAmt(litePsm.buf()));
        litePsm.sellGem(address(0x1337), igemAmt);

        address usr = address(0xd34d);
        uint256 pgemBalanceUsr = gem.balanceOf(usr);
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

        gemAmt = bound(gemAmt, _wadToAmt(1 * WAD), _wadToAmt(1 * WAD) + igemAmt / 2);
        vm.expectEmit(true, true, true, true);
        emit BuyGem(usr, gemAmt, 0);
        uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

        uint256 gemBalanceUsr = gem.balanceOf(usr);
        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalanceUsr, pgemBalanceUsr + gemAmt, "buyGem: invalid usr gem balance after buyGem");
        assertEq(gemBalancePocket, pgemBalancePocket - gemAmt, "buyGem: invalid pocket gem balance after buyGem");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
        assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid cash after buyGem");
    }

    function testBuyGem_Revert_WhenToutIsSpecialValueHalted() public {
        litePsm.file("tout", litePsm.HALTED());
        vm.expectRevert("DssLitePsm/buy-gem-halted");
        litePsm.buyGem(address(this), 1);
    }

    // /*//////////////////////////////////
    //             Bookkeeping
    // //////////////////////////////////*/

    function testFill() public {
        // 1st fill
        {
            assertEq(dss.dai.balanceOf(address(litePsm)), 0, "fill: invalid initial cash");
            assertEq(_debt(), 0);

            vm.expectEmit(true, true, true, true);
            emit Fill(10_000_000 * WAD);
            assertEq(litePsm.fill(), 10_000_000 * WAD, "fill: invalid filled amount on 1st fill");
        }

        // Cannot fill because buf == pre-minted unused Dai
        {
            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();
        }

        // Cannot fill because buf < pre-minted unused Dai
        {
            uint256 beforeFile = vm.snapshot();
            litePsm.file("buf", 8_000_000 * WAD);

            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();

            vm.revertTo(beforeFile);
        }

        // Sell additional gem to max out the debt ceiling
        {
            assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD, "fill: invalid cash before 1st sellGem");
            assertEq(_debt(), 10_000_000 * RAD, "fill: invalid debt before 1st sellGem");

            litePsm.sellGem(address(0x1337), _wadToAmt(10_000_000 * WAD));

            assertEq(dss.dai.balanceOf(address(litePsm)), 0, "fill: invalid cash after 1st sellGem");
            assertEq(_debt(), 10_000_000 * RAD, "fill: invalid debt after 1st sellGem");
        }

        // 2nd fill
        {
            vm.expectEmit(true, true, true, true);
            emit Fill(10_000_000 * WAD);
            assertEq(litePsm.fill(), 10_000_000 * WAD, "fill: invalid filled amount on 2nd fill");

            assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD, "fill: invalid cash after 2nd fill");
            assertEq(_debt(), 20_000_000 * RAD, "fill: invalid debt after 2nd fill");
        }

        // Next fill will be limited by line
        {
            dss.vat.file(ilk, "line", 25_000_000 * RAD);

            litePsm.sellGem(address(0x1337), _wadToAmt(10_000_000 * WAD));

            assertEq(dss.dai.balanceOf(address(litePsm)), 0, "fill: invalid cash after 2nd sellGem");
            assertEq(_debt(), 20_000_000 * RAD, "fill: invalid debt after 2nd sellGem");

            vm.expectEmit(true, true, true, true);
            emit Fill(5_000_000 * WAD);
            assertEq(litePsm.fill(), 5_000_000 * WAD, "fill: invalid filled amount on 3rd fill");

            assertEq(dss.dai.balanceOf(address(litePsm)), 5_000_000 * WAD, "fill: invalid cash after 3rd fill");
            assertEq(_debt(), 25_000_000 * RAD, "fill: invalid debt after 3rd fill");
        }

        // Cannot fill because line == debt
        {
            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();
        }

        // Cannot fill because line < debt
        {
            dss.vat.file(ilk, "line", 20_000_000 * RAD);

            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();
        }

        // Moving line higher so we are not constrained by it anymore
        {
            dss.vat.file(ilk, "line", 50_000_000 * RAD);

            vm.expectEmit(true, true, true, true);
            emit Fill(5_000_000 * WAD);
            assertEq(litePsm.fill(), 5_000_000 * WAD, "fill: invalid filled amount on 4th fill");

            assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD, "fill: invalid cash after 4th fill");
            assertEq(_debt(), 30_000_000 * RAD, "fill: invalid debt after 4th fill");
        }
    }

    function testFill_Revert_WhenRateIsInvalid() public {
        dss.vat.fold(ilk, address(111), 1);

        vm.expectRevert("DssLitePsm/rate-not-RAY");
        litePsm.fill();
    }

    function testTrim() public {
        litePsm.fill();
        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));

        litePsm.fill();
        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD, "trim: invalid cash after 2nd fill");
        assertEq(_debt(), 20_000_000 * RAD, "trim: invalid debt after 2nd fill");

        // buf == pre-minted unused Dai
        {
            vm.expectRevert("DssLitePsm/nothing-to-trim");
            litePsm.trim();
        }

        // buf > pre-minted unused Dai
        {
            uint256 beforeFile = vm.snapshot();
            litePsm.file("buf", 12_000_000 * WAD);

            vm.expectRevert("DssLitePsm/nothing-to-trim");
            litePsm.trim();

            vm.revertTo(beforeFile);
        }

        // 1st trimm will be triggered for excess of pre-minted Dai
        {
            litePsm.buyGem(address(0x1337), _wadToAmt(5_000_000 * WAD));
            assertEq(dss.dai.balanceOf(address(litePsm)), 15_000_000 * WAD, "trim: invalid cash before 1st trim");
            assertEq(_debt(), 20_000_000 * RAD, "trim: invalid debt before 1st trim");

            vm.expectEmit(true, true, true, true);
            emit Trim(5_000_000 * WAD);
            assertEq(litePsm.trim(), 5_000_000 * WAD, "trim: invalid trimmed amount on 1st trim");

            assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD, "trim: invalid cash after 1st trim");
            assertEq(_debt(), 15_000_000 * RAD, "trim: invalid debt after 1st trim");
        }

        // 2nd trim will be triggered for exceeding line
        {
            dss.vat.file(ilk, "line", 12_000_000 * RAD);

            vm.expectEmit(true, true, true, true);
            emit Trim(3_000_000 * WAD);
            assertEq(litePsm.trim(), 3_000_000 * WAD, "trim: invalid trimmed amount on 2nd trim");

            assertEq(dss.dai.balanceOf(address(litePsm)), 7_000_000 * WAD, "trim: invalid cash after 2nd trim");
            assertEq(_debt(), 12_000_000 * RAD, "trim: invalid debt after 2nd trim");
        }

        // 3rd trim will be triggered for exceeding line; amount will be limited by balance
        {
            dss.vat.file(ilk, "line", 4_000_000 * RAD);

            vm.expectEmit(true, true, true, true);
            emit Trim(7_000_000 * WAD);
            assertEq(litePsm.trim(), 7_000_000 * WAD, "trim: invalid trimmed amount on 3rd trim");

            assertEq(dss.dai.balanceOf(address(litePsm)), 0, "trim: invalid cash after 3rd trim");
            assertEq(_debt(), 5_000_000 * RAD);
        }
    }

    function testTrim_Revert_WhenRateIsInvalid() public {
        dss.vat.fold(ilk, address(111), 1);

        vm.expectRevert("DssLitePsm/rate-not-RAY");
        litePsm.fill();
    }

    /*//////////////////////////////////
                    Fees
    //////////////////////////////////*/

    function testSellAndBuyGemAccountingFees() public {
        litePsm.fill();

        // Set fees to 1%
        (uint256 tin, uint256 tout) = _setupFees(0.01 ether, 0.01 ether);
        uint256 gemAmt = _wadToAmt(100_000 * WAD);
        vm.expectEmit(true, true, true, true);
        emit SellGem(address(0x1337), gemAmt, _fee(tin, gemAmt));
        uint256 daiWadOut = litePsm.sellGem(address(0x1337), gemAmt);

        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        uint256 pcut = litePsm.cut();
        assertEq(pcut, _fee(tin, gemAmt), "sellGem: invalid fees after initial swap");
        // The Dai balance of the PSM after the first sell should be the same as the swapped amount.
        assertEq(pdaiBalancePsm, 10_000_000 * WAD - daiWadOut, "sellGem: invalid cash after initial swap");

        vm.expectEmit(true, true, true, true);
        emit BuyGem(address(this), gemAmt / 2, _fee(tout, gemAmt / 2));
        uint256 daiInWad = litePsm.buyGem(address(this), gemAmt / 2);

        assertEq(litePsm.cut(), pcut + _fee(tout, gemAmt / 2), "sellGem: invalid cut change");

        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, 10_000_000 * WAD - daiWadOut + daiInWad, "sellGem: invalid cash change");

        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalancePocket, pgemBalancePocket - gemAmt / 2, "sellGem: invalid pocket gem balance change");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis + gemAmt / 2, "sellGem: invalid address(this) gem balance change");
    }

    function testChug_Fuzz_Bounded(uint256 gemAmt, uint256 tin_, uint256 tout_) public {
        litePsm.fill();

        gemAmt = bound(gemAmt, _wadToAmt(1 * WAD), _wadToAmt(10_000_000 * WAD));
        _setupFees(tin_, tout_);

        litePsm.sellGem(address(this), gemAmt);
        litePsm.buyGem(address(this), gemAmt);

        uint256 pvowDai = dss.vat.dai(address(dss.vow));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 cut = litePsm.cut();

        vm.expectEmit(false, false, false, true);
        emit Chug(cut);
        litePsm.chug();

        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));

        assertEq(vowDai, pvowDai + cut * RAY, "chug: invalid vat.dai(vow) change after chug");
        assertEq(daiBalancePsm, pdaiBalancePsm - cut, "chug: invalid dai.balanceOf(litePsm) change after chug");
        assertEq(litePsm.cut(), 0, "chug: invalid cut after chug");
    }

    function testChug_Revert_WhenVowIsAddressZero() public {
        litePsm.fill();

        _setupFees(0.001 ether, 0.001 ether);
        // Simulate vow being set to `address(0)`
        litePsm.file("vow", address(0));

        // Accumulate some fees
        litePsm.sellGem(address(this), _wadToAmt(50_000 * WAD));
        litePsm.buyGem(address(this), _wadToAmt(50_000 * WAD));

        vm.expectRevert("DssLitePsm/chug-missing-vow");
        litePsm.chug();
    }

    function testChug_Revert_WhenZeroAccumulatedFees() public {
        vm.expectRevert("DssLitePsm/nothing-to-chug");
        litePsm.chug();
    }

    function testChug_PartialDaiBalance() public {
        _setupFees(0.01 ether, 0.01 ether);
        litePsm.fill();

        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));
        assertEq(litePsm.cut(), 100_000 * WAD, "chug: invalid cut after 1st sellGem");

        litePsm.file("tin", 0);
        // Leave the PSM without enough balance to redeem the whole amount of fees
        litePsm.sellGem(address(this), _wadToAmt(40_000 * WAD));

        // Still the cut didn't change, however now is partially in gem
        assertEq(litePsm.cut(), 60_000 * WAD, "chug: invalid cut after 2nd sellGem");
        assertEq(_fullCut(), 100_000 * WAD, "chug: invalid fullCut after 2nd sellGem");

        assertEq(litePsm.chug(), 60_000 * WAD, "chug: invalid chugged amount on 1st chug");
        assertEq(litePsm.cut(), 0, "chug: invalid cut after 2nd sellGem");
        assertEq(_fullCut(), 40_000 * WAD, "chug: invalid fullCut after 1st chug");
    }

    function testChug_Revert_WhenNoDaiBalance() public {
        _setupFees(0.01 ether, 0.01 ether);
        litePsm.fill();

        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));
        assertEq(litePsm.cut(), 100_000 * WAD, "chug: invalid cut after 1st sellGem");
        assertEq(_fullCut(), 100_000 * WAD, "chug: invalid fullCut after 1st sellGem");

        litePsm.file("tin", 0);
        // Leave the PSM without any Dai balance
        litePsm.sellGem(address(this), _wadToAmt(100_000 * WAD));

        // Still the cut didn't change, however now is pure gem
        assertEq(litePsm.cut(), 0, "chug: invalid cut after 2nd sellGem");
        assertEq(_fullCut(), 100_000 * WAD, "chug: invalid fullCut after 2nd sellGem");

        // Then chug will revert
        vm.expectRevert("DssLitePsm/nothing-to-chug");
        litePsm.chug();
    }

    /*//////////////////////////////////
        Permissioned No Fee Swapping
    //////////////////////////////////*/

    function testPermissionedSwapsNoFee() public {
        litePsm.fill();

        _setupFees(0.001 ether, 0.001 ether);

        uint256 gemAmtWad = 500_000 * WAD;
        uint256 gemAmt = _wadToAmt(gemAmtWad);

        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));
        uint256 pgemBalancePocket = gem.balanceOf(address(pocket));

        // Sell gems

        litePsm.kiss(address(this));
        uint256 daiWadOut = litePsm.sellGemNoFee(address(this), gemAmt);
        assertEq(daiWadOut, gemAmtWad, "no fees: unexpected fee on sellGemNoFee");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis + daiWadOut, "no fees: invalid address(this) Dai balance after sellGemNoFee"
        );

        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(
            gemBalanceThis, pgemBalanceThis - gemAmt, "no fees: invalid address(this) gem balance after sellGemNoFee"
        );
        uint256 gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalancePocket, pgemBalancePocket + gemAmt, "no fees: invalid pocket gem balance after sellGemNoFee");

        // Buy gems

        pdaiBalanceThis = dss.dai.balanceOf(address(this));
        pgemBalancePocket = gem.balanceOf(address(pocket));
        pgemBalanceThis = gem.balanceOf(address(this));

        uint256 daiWadIn = litePsm.buyGemNoFee(address(this), gemAmt);
        assertEq(daiWadIn, gemAmtWad, "no fees: unexpected fee on buyGem");

        daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis - daiWadIn, "no fees: invalid address(this) Dai balance after buyGemNoFee"
        );

        gemBalanceThis = gem.balanceOf(address(this));
        assertEq(
            gemBalanceThis, pgemBalanceThis + gemAmt, "no fees: invalid address(this) gem balance after buyGemNoFee"
        );
        gemBalancePocket = gem.balanceOf(address(pocket));
        assertEq(gemBalancePocket, pgemBalancePocket - gemAmt, "no fees: invalid pocket gem balance after buyGemNoFee");
    }

    /*//////////////////////////////////
            External Influences
    //////////////////////////////////*/

    function testFillVsAutoLine_Reproduce() public {
        uint256 maxLine = 50_000_000 * RAD;
        uint256 gap = 1_000_000 * RAD;
        uint256 ttl = 1 hours;

        autoLine.setIlk(ilk, maxLine, gap, ttl);
        autoLine.exec(ilk);

        // Make buf == 10% of gap
        litePsm.file("buf", 100_000 * WAD);

        // Cannot prevent swapping up to acting debt ceiling
        {
            uint256 beforeSwaps = vm.snapshot();
            uint256 iters = _divup((gap / RAY), litePsm.buf());
            for (uint256 i = 0; i < iters; i++) {
                litePsm.fill();
                litePsm.sellGem(address(0x1337), _wadToAmt(dss.dai.balanceOf(address(litePsm))));
            }

            vm.revertTo(beforeSwaps);
        }

        // After reaching the debt ceiling, `AutoLine.exec()` can happen 2x without any gem inflow,
        // however fill can only be done 1x.
        {
            // Make buf == gap to be able to make less calls, but the end result would be the same
            litePsm.file("buf", 1_000_000 * WAD);
            litePsm.fill();
            litePsm.sellGem(address(this), _wadToAmt(1_000_000 * WAD));
            assertEq(_debt(), 1_000_000 * RAD, "auto-line: invalid debt before 2nd exec");
            assertEq(_debtCeiling(), 1_000_000 * RAD, "auto-line: invalid line before 2nd exec");

            // Fill is not available because of the debt ceiling
            {
                vm.expectRevert("DssLitePsm/nothing-to-fill");
                litePsm.fill();
            }

            // 2nd exec
            {
                _skipAndRoll(ttl + 1);
                autoLine.exec(ilk);
                assertEq(_debt(), 1_000_000 * RAD, "auto-line: invalid debt after 2nd exec");
                assertEq(_debtCeiling(), 2_000_000 * RAD, "auto-line: invalid line after 2nd exec");
            }

            // 2nd fill
            {
                litePsm.fill();
                assertEq(_debt(), 2_000_000 * RAD, "auto-line: invalid debt after 2nd fill");
                assertEq(_debtCeiling(), 2_000_000 * RAD, "auto-line: invalid line after 2nd fill");
            }

            // 3rd exec
            {
                _skipAndRoll(ttl + 1);
                autoLine.exec(ilk);
                assertEq(_debt(), 2_000_000 * RAD, "auto-line: invalid debt after 3rd exec");
                assertEq(_debtCeiling(), 3_000_000 * RAD, "auto-line: invalid line after 3rd exec");
            }

            // Fill is not available because of gem balance
            {
                vm.expectRevert("DssLitePsm/nothing-to-fill");
                litePsm.fill();
            }
        }
    }

    function testGemDonation_Reproduce() public {
        _setupFees(0.01 ether, 0.01 ether);
        litePsm.file("buf", 100_000 * WAD);
        litePsm.fill();
        assertEq(dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "gem donation: invalid cash after 1st fill");

        // Donated amount > buf will force splitting the chug in parts.
        // However, no swap is required to be able to do so.
        {
            uint256 beforeDonation = vm.snapshot();
            gem.transfer(address(pocket), _wadToAmt(150_000 * WAD));

            // Will chug up to the existing Dai balance
            assertEq(litePsm.chug(), 100_000 * WAD, "gem donation: invalid chugged amount on 1st chug");
            assertEq(dss.dai.balanceOf(address(litePsm)), 0, "gem donation: invalid cash after 1st chug");

            // We are now allowed to fill again
            litePsm.fill();
            assertEq(dss.dai.balanceOf(address(litePsm)), 150_000 * WAD, "gem donation: invalid cash after 2nd fill");

            // Now we can chug the rest of the donation
            assertEq(litePsm.chug(), 50_000 * WAD, "gem donation: invalid chugged amount on 2nd chug");
            assertEq(dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "gem donation: invalid cash after 2nd chug");

            vm.revertTo(beforeDonation);
        }

        // Can chug the full amount right after swapping gem for Dai
        {
            uint256 beforeDonation = vm.snapshot();
            gem.transfer(address(pocket), _wadToAmt(150_000 * WAD));

            litePsm.buyGem(address(this), _wadToAmt(150_000 * WAD));
            // Chug should account for swapping fees
            assertEq(litePsm.chug(), 151_500 * WAD, "gem donation: invalid chugged amount on 2nd chug");

            vm.revertTo(beforeDonation);
        }
    }

    function testDaiDonation_Reproduce() public {
        litePsm.file("buf", 100_000 * WAD);
        litePsm.fill();

        // Can chug excess Dai immediately
        {
            uint256 beforeDonation = vm.snapshot();
            dss.dai.transfer(address(litePsm), 150_000 * WAD);

            assertEq(litePsm.chug(), 150_000 * WAD, "dai donation: invalid chugged amount on 1st chug");

            vm.revertTo(beforeDonation);
        }

        // We guarantee that a previously filled amount cannot be trimmed as the result of a donation
        {
            uint256 beforeDonation = vm.snapshot();
            // Donate exactly the amount of buf
            dss.dai.transfer(address(litePsm), 100_000 * WAD);
            assertEq(dss.dai.balanceOf(address(litePsm)), 200_000 * WAD, "dai donation: invalid cash before 1st trim");

            // Now we are not able to trim, as there is no exceeding debt
            vm.expectRevert("DssLitePsm/nothing-to-trim");
            litePsm.trim();

            // Cannot fill either
            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();

            assertEq(litePsm.chug(), 100_000 * WAD, "dai donation: invalid chugged amount on 2nd chug");
            assertEq(dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "dai donation: invalid cash after 2nd chug");

            // Still cannot fill
            vm.expectRevert("DssLitePsm/nothing-to-fill");
            litePsm.fill();

            litePsm.sellGem(address(this), _wadToAmt(1000 * WAD));
            assertEq(dss.dai.balanceOf(address(litePsm)), 99_000 * WAD, "dai donation: invalid cash after 1st sellGem");

            vm.revertTo(beforeDonation);
        }
    }

    /*//////////////////////////////////
             Known Limitations
    //////////////////////////////////*/

    function testSellGem_Limitation_TrimGriefingAttack() public {
        // Hypothesis: a user tries to sell more gem than the amount of buf
        // Attack: a tx calling trim front-runs the user
        // Cost: gas costs

        litePsm.file("buf", 100_000 * WAD);
        litePsm.fill();

        litePsm.sellGem(address(this), _wadToAmt(100_000 * WAD));
        assertEq(dss.dai.balanceOf(address(litePsm)), 0, "sellGem/trim grief: invalid cash after 1st sellGem");

        litePsm.fill();
        assertEq(dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "sellGem/trim grief: invalid cash after 1st fill");

        litePsm.buyGem(address(this), _wadToAmt(50_000 * WAD));
        assertEq(
            dss.dai.balanceOf(address(litePsm)), 150_000 * WAD, "sellGem/trim grief: invalid cash after 1st buyGem"
        );

        // Imagine the block below is a transaction front-running the swap following it
        {
            assertEq(litePsm.trim(), 50_000 * WAD, "sellGem/trim grief: invalid trimmed amount on 1st trim");
            assertEq(
                dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "sellGem/trim grief: invalid cash after 1st trim"
            );
        }

        uint256 gemAmt = _wadToAmt(150_000 * WAD);
        vm.expectRevert("Dai/insufficient-balance");
        litePsm.sellGem(address(this), gemAmt);
    }

    function testSellGem_Limitation_FrontRunningGriefingAttack() public {
        // Hypothesis: a user tries to sell the exact amount of Dai available
        // Attack: a tx selling any amount of gem front-runs the user
        // Cost: gas costs

        litePsm.file("buf", 100_000 * WAD);
        litePsm.fill();
        assertEq(
            dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "sellGem/front-run grief: invalid cash after 1st fill"
        );

        // Imagine the block below is a transaction front-running the swap following it
        {
            litePsm.sellGem(address(this), _wadToAmt(1 * WAD));
            assertEq(
                dss.dai.balanceOf(address(litePsm)),
                99_999 * WAD,
                "sellGem/front-run grief: invalid cash after 1st sellGem"
            );
        }

        uint256 gemAmt = _wadToAmt(100_000 * WAD);
        vm.expectRevert("Dai/insufficient-balance");
        litePsm.sellGem(address(this), gemAmt);
    }

    function testBuyGem_Limitation_FrontRunningGriefingAttack() public {
        // Hypothesis: a user tries to buy the exact amount of gem available
        // Attack: a tx buying any amount of gem front-runs the user
        // Cost: gas costs

        litePsm.file("buf", 100_000 * WAD);
        litePsm.fill();
        assertEq(
            dss.dai.balanceOf(address(litePsm)), 100_000 * WAD, "buyGem/front-run grief: invalid cash after 1st fill"
        );
        litePsm.sellGem(address(this), _wadToAmt(100_000 * WAD));

        // Imagine the block below is a transaction front-running the swap following it
        {
            litePsm.buyGem(address(this), _wadToAmt(1 * WAD));
            assertEq(
                dss.dai.balanceOf(address(litePsm)), 1 * WAD, "buyGem/front-run grief: invalid cash after 1st buyGem"
            );
        }

        // Will fail on gem.transferFrom() due to lack of balance
        uint256 gemAmt = _wadToAmt(100_000 * WAD);
        vm.expectRevert();
        litePsm.buyGem(address(this), gemAmt);
    }

    /*//////////////////////////////////
                  Helpers
    //////////////////////////////////*/

    function _setupFees(uint256 tin_, uint256 tout_) internal returns (uint256 tin, uint256 tout) {
        tin = bound(tin_, 0.00001 ether, 1 * WAD); // Between 0.001% and 100%
        tout = bound(tout_, 0.00001 ether, 1 * WAD); // Between 0.001% and 100%

        litePsm.file("tin", tin);
        litePsm.file("tout", tout);
    }

    function _fee(uint256 t, uint256 gemAmt) internal view returns (uint256) {
        return t * _amtToWad(gemAmt) / WAD;
    }

    function _fullCut() internal view returns (uint256) {
        (, uint256 art) = dss.vat.urns(ilk, address(litePsm));
        uint256 daiBalance = dss.dai.balanceOf(address(litePsm));
        uint256 gemBalanceWad = gem.balanceOf(litePsm.pocket()) * litePsm.to18ConversionFactor();
        return daiBalance + gemBalanceWad - art;
    }

    function _debt() internal view returns (uint256) {
        (uint256 Art, uint256 rate,,,) = dss.vat.ilks(ilk);
        return Art * rate;
    }

    function _debtCeiling() internal view returns (uint256) {
        (,,, uint256 line,) = dss.vat.ilks(ilk);
        return line;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x < y ? x : y;
    }

    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x > y ? x : y;
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function _subcap(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x > y ? x - y : 0;
        }
    }

    function _changeIlkLine(bytes32 ilk_, uint256 dline, bool global) internal returns (uint256) {
        return _changeIlkLine(ilk_, _int256(dline), global);
    }

    function _changeIlkLine(bytes32 ilk_, int256 dline, bool global) internal returns (uint256) {
        (,,, uint256 line,) = dss.vat.ilks(ilk_);
        uint256 lineNew = dline > 0 ? line + uint256(dline) : line - uint256(-dline);
        _setIlkLine(ilk_, lineNew, global);

        return lineNew;
    }

    function _setIlkLine(bytes32 ilk_, uint256 lineNew, bool global) internal {
        (,,, uint256 line,) = dss.vat.ilks(ilk_);
        dss.vat.file(ilk_, "line", lineNew);
        int256 dline = _int256(lineNew) - _int256(line);

        if (global) {
            uint256 Line = dss.vat.Line();
            uint256 LineNew = dline > 0 ? Line + uint256(dline) : Line - uint256(-dline);
            dss.vat.file("Line", LineNew);
        }
    }

    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, "Unsafe cast to int256");
    }

    function _amtToWad(uint256 amt) internal view returns (uint256 wad) {
        wad = amt * 10 ** (18 - gem.decimals());
    }

    function _wadToAmt(uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (18 - gem.decimals());
    }

    uint256 blk = block.number;

    /**
     * @notice Advances time and block number.
     * @dev Forge's `skip()` does not advance blocks.
     */
    function _skipAndRoll(uint256 t) internal {
        skip(t);
        // Consider 12.5 seconds per block
        blk += t * 125 / 100;
        vm.roll(blk);
    }

    event Fill(uint256 wad);
    event Trim(uint256 wad);
    event Chug(uint256 wad);
    event Exit(address indexed usr, uint256 wad, uint256 gemAmt);
    event SellGem(address indexed owner, uint256 value, uint256 fee);
    event BuyGem(address indexed owner, uint256 value, uint256 fee);
}

/*//////////////////////////////////////////////////////////////////////////////
                                      USDC
//////////////////////////////////////////////////////////////////////////////*/

contract DssLitePsmUsdcTest is DssLitePsmBaseTest {
    function _ilk() internal pure override returns (bytes32) {
        return "LITE_PSM_USDC_A";
    }

    function _setUpGem() internal override returns (address) {
        address _gem = dss.chainlog.getAddress("USDC");
        // Mints 100_000_000 gem into the test contract.
        GodMode.setBalance(_gem, address(this), 100_000_000 * (10 ** GemLike(_gem).decimals()));
        vm.label(_gem, "USDC");

        return _gem;
    }

    function testBuyGem_Revert_WhenPocketHasNoGem() public {
        assertEq(gem.balanceOf(address(pocket)), 0, "buyGem: initial pocket gem balance not zero");

        // Error from the USDC implementation on Mainnet
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        litePsm.buyGem(address(this), 1);
    }
}

/*//////////////////////////////////////////////////////////////////////////////
                                      USDP
//////////////////////////////////////////////////////////////////////////////*/

// USDP is not supported because it is an upgradeable contract.

/*//////////////////////////////////////////////////////////////////////////////
                                      GUSD
//////////////////////////////////////////////////////////////////////////////*/

// GUSD is not supported because it is an upgradeable contract.
