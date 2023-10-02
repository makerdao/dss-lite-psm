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

import {console2} from "forge-std/console2.sol";
import {DssTest, DssInstance, MCD, GodMode} from "dss-test/DssTest.sol";
import {DssKeg} from "./DssKeg.sol";
import {DssLitePsm} from "./DssLitePsm.sol";

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract Harness__DssLitePsm is DssLitePsm {
    constructor(bytes32 ilk_, address gem_, address daiJoin_, address keg_) DssLitePsm(ilk_, gem_, daiJoin_, keg_) {}

    function __to18ConversionFactor() external view returns (uint256) {
        return to18ConversionFactor;
    }
}

abstract contract DssLitePsmBaseTest is DssTest {
    function _ilk() internal virtual view returns(bytes32);
    function _setUpGem() internal virtual returns(address);

    address immutable chainlog = vm.envAddress("CHANGELOG");

    bytes32 ilk;
    DssInstance dss;
    GemLike gem;
    DssKeg keg;
    Harness__DssLitePsm litePsm;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(chainlog);
        MCD.giveAdminAccess(dss);

        // From concrete test implementations
        ilk = _ilk();
        gem = GemLike(_setUpGem());

        MCD.initIlk(dss, ilk);
        uint256 dline = 1_000_000_000 * RAD;
        dss.vat.file("Line", dss.vat.Line() + dline);
        dss.vat.file(ilk, "line", dline);

        // There is a circular dependency between `LitePsm` and `Keg`, so we need to pre-compute
        // their addresses to be able to provide all constructor parameters.
        uint256 nonce = vm.getNonce(address(this));
        address kegAddr = computeCreateAddress(address(this), nonce);
        address litePsmAddr = computeCreateAddress(address(this), nonce + 1);

        keg = new DssKeg(litePsmAddr, address(gem));
        litePsm = new Harness__DssLitePsm(ilk, address(gem), address(dss.daiJoin), kegAddr);

        // Authorizes the new LitePsm on the Vat
        GodMode.setWard(dss.vat, address(litePsm), 1);

        gem.approve(address(litePsm), type(uint256).max);

        // Mints 100_000_000 Dai into the test contract.
        GodMode.setBalance(dss.dai, address(this), 100_000_000 * WAD);
        dss.dai.approve(address(litePsm), type(uint256).max);

        // keg to give unlimited gem approval to the litePsm.
        vm.prank(address(keg));
        gem.approve(address(litePsm), type(uint256).max);

        // Setup the vow for litePsm
        litePsm.file("vow", address(dss.vow));

        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(gem), "Gem");
    }

    /*//////////////////////////////////
               Sanity Checks
    //////////////////////////////////*/

    function testTo18ConversionFactor() public {
        assertEq(litePsm.__to18ConversionFactor(), 10 ** (18 - gem.decimals()));
    }

    function testSetUpContractDependencies() public {
        assertEq(address(keg.gem()), address(litePsm.gem()), "sanity check: mismatching gem");
        assertEq(keg.mgr(), address(litePsm), "sanity check: bad keg.mgr()");
        assertEq(litePsm.keg(), address(keg), "sanity check: bad lightPsm.keg()");
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    function testAuth() public {
        checkAuth(address(litePsm), "LitePsm");
    }

    function testAuthMethods() public {
        // Revoke ward role for this contract
        GodMode.setWard(address(litePsm), address(this), 0);
        checkModifier(address(litePsm), "LitePsm/not-authorized", [DssLitePsm.kiss.selector, DssLitePsm.diss.selector]);
    }

    function testOnlyBudMethods() public {
        checkModifier(
            address(litePsm), "LitePsm/not-bud", [DssLitePsm.buyGemNoFee.selector, DssLitePsm.sellGemNoFee.selector]
        );
    }

    function testFile() public {
        /*//////////////////////////////////
                     tin & tout
        //////////////////////////////////*/
        assertEq(litePsm.wards(address(this)), 1, "Invalid ward setting");

        vm.expectRevert("LitePsm/out-of-range");
        litePsm.file("tin", 2 * WAD);

        vm.expectRevert("LitePsm/out-of-range");
        litePsm.file("tout", 2 * WAD);

        checkFileUint(address(litePsm), "LitePsm", ["tin", "tout"]);

        /*//////////////////////////////////
                        vow
        //////////////////////////////////*/

        checkFileAddress(address(litePsm), "LitePsm", ["vow"]);
    }

    /*//////////////////////////////////
          Permissionless Swapping
    //////////////////////////////////*/

    function testSellGem_EnoughDaiLiquidity() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        uint256 daiTotalSupply = dss.dai.totalSupply();
        // Dai total supply should not be affected.
        assertEq(daiTotalSupply, pdaiTotalSupply, "sellGem: Dai total supply changed unexpectedly");

        // Available Dai liquidity should reduce by the same amount being swapped.
        // Automation must kick in to rebalance the PSM.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm - daiOutWad, "sellGem: invalid PSM Dai change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testSellGem_Fuzz_EnoughDaiLiquidity(uint256 igemAmt, uint256 gemAmt) public {
        // Since we are selling gem twice, we can only sell part of it in the setup.
        igemAmt = bound(igemAmt, 0, (gem.balanceOf(address(this)) / 2) - 1);
        // Next we sell up to the existing liquidity to force a rebalance.
        gemAmt = bound(gemAmt, 0, igemAmt);
        // Test the flow when there is enough Dai liquidity in the PSM
        litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        uint256 daiTotalSupply = dss.dai.totalSupply();
        // Dai total supply should not be affected.
        assertEq(daiTotalSupply, pdaiTotalSupply, "sellGem: Dai total supply changed unexpectedly");

        // Available Dai liquidity should reduce by the same amount being swapped.
        // Automation must kick in to rebalance the PSM.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm - daiOutWad, "sellGem: invalid PSM Dai balance change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testSellGem_NotEnoughDaiLiquidity_EnoughRoomInDebtCeiling() public {
        uint256 igemAmt = _wadToAmt(50_000 * WAD);
        uint256 gemAmt = _wadToAmt(100_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        // Mint 2x the required amount to keep the PSM perfectly balanced after the swap.
        uint256 daiTotalSupply = dss.dai.totalSupply();
        assertEq(daiTotalSupply, pdaiTotalSupply + 2 * daiOutWad, "sellGem: invalid Dai supply change");

        // Dai liquidity should increase by the same amount being swapped.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm + daiOutWad, "sellGem: invalid PSM Dai balance change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testSellGem_Fuzz_NotEnoughDaiLiquidity_EnoughRoomInDebtCeiling(uint256 igemAmt, uint256 gemAmt) public {
        // Since we are selling gem twice, we can only sell part of it in the setup.
        igemAmt = bound(igemAmt, 0, (gem.balanceOf(address(this)) / 2) - 1);
        // Next we sell more than the existing liquidity to force a rebalance.
        gemAmt = bound(gemAmt, igemAmt + 1, gem.balanceOf(address(this)) - igemAmt);
        litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        // Mint 2x the required amount to keep the PSM perfectly balanced after the swap.
        uint256 daiTotalSupply = dss.dai.totalSupply();
        assertEq(daiTotalSupply, pdaiTotalSupply + 2 * daiOutWad, "sellGem: invalid Dai supply change");

        // Dai liquidity should increase by the same amount being swapped.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm + daiOutWad, "sellGem: invalid PSM Dai balance change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testSellGem_NotEnoughDaiLiquidity_NotEnoughRoomInDebtCeiling() public {
        uint256 igemAmt = _wadToAmt(50_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);

        uint256 maxDebtCeiling = 200_000 * RAD;
        _setIlkLine(ilk, maxDebtCeiling, true);

        uint256 gemAmt = _wadToAmt(100_000 * WAD);
        // The first `sellGem` minted 2x the required amount of Dai.
        uint256 maxMintable = maxDebtCeiling / RAY - 2 * idaiOutWad;

        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        // Mint Dai up to the debt ceiling
        uint256 daiTotalSupply = dss.dai.totalSupply();
        assertEq(daiTotalSupply, pdaiTotalSupply + maxMintable, "sellGem: did not mint the max mintable amount");

        // Dai liquidity should increase by the same amount being swapped
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm + maxMintable - daiOutWad, "sellGem: invalid PSM Dai balance change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) gem balance change");
    }

    function testBuyGem() public {
        uint256 igemAmt = _wadToAmt(100_000_000 * WAD);
        uint256 gemAmt = _wadToAmt(175_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        address usr = address(0xd34d);
        uint256 pgemBalanceUsr = gem.balanceOf(usr);
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

        vm.expectEmit(true, false, false, true);
        emit BuyGem(usr, gemAmt, 0);
        uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

        uint256 gemBalanceUsr = gem.balanceOf(usr);
        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceUsr, pgemBalanceUsr + gemAmt, "buyGem: invalid usr gem balance after buyGem");
        assertEq(gemBalanceKeg, pgemBalanceKeg - gemAmt, "buyGem: invalid keg gem balance after buyGem");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
        assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid PSM Dai balance after buyGem");
    }

    function testBuyGem_Fuzz(uint256 igemAmt, uint256 gemAmt) public {
        igemAmt = bound(igemAmt, 1, gem.balanceOf(address(this)));
        gemAmt = bound(gemAmt, 1, igemAmt);
        litePsm.sellGem(address(0x1337), igemAmt);

        address usr = address(0xd34d);
        uint256 pgemBalanceUsr = gem.balanceOf(usr);
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

        vm.expectEmit(true, false, false, true);
        emit BuyGem(usr, gemAmt, 0);
        uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

        uint256 gemBalanceUsr = gem.balanceOf(usr);
        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceUsr, pgemBalanceUsr + gemAmt, "buyGem: invalid usr gem balance after buyGem");
        assertEq(gemBalanceKeg, pgemBalanceKeg - gemAmt, "buyGem: invalid keg gem balance after buyGem");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
        assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid PSM Dai balance after buyGem");
    }

    /*//////////////////////////////////
                Bookkeeping
    //////////////////////////////////*/

    function testFill() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);
        // Sell less than the available liquidity.
        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        uint256 daiOutWad = litePsm.sellGem(address(0x1337), gemAmt);

        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(pgemBalanceKeg, igemAmt + gemAmt, "fill: invalid initial Keg gem balance");

        // Since there was enough liquidity, Dai balance should decrease.
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, idaiOutWad - daiOutWad, "fill: invalid initial PSM Dai balance");

        uint256 rush = litePsm.rush();
        vm.expectEmit(true, false, false, true);
        emit Fill(rush);

        uint256 filled = litePsm.fill();
        assertEq(filled, 2 * daiOutWad, "fill: invalid filled amount");

        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, pdaiBalancePsm + filled, "fill: invalid PSM Dai balance after fill");
    }

    function testFill_ShouldNotExceedDebtCeiling() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);

        // Sell less than the available liquidity.
        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        uint256 daiOutWad = litePsm.sellGem(address(0x1337), gemAmt);

        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(pgemBalanceKeg, igemAmt + gemAmt, "fill: invalid initial Keg gem balance");

        // Since there was enough liquidity, Dai balance should decrease.
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, idaiOutWad - daiOutWad, "fill: invalid initial PSM Dai balance");

        // After selling 100k and then 50k gem, the debt should still be 2 * 100k = 200k
        uint256 maxDebtCeiling = 210_000 * RAD;
        _setIlkLine(ilk, maxDebtCeiling, true);

        uint256 rush = litePsm.rush();
        vm.expectEmit(true, false, false, true);
        emit Fill(rush);

        uint256 filled = litePsm.fill();
        assertEq(filled, (maxDebtCeiling / RAY) - (2 * idaiOutWad), "fill: invalid filled amount");

        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        // The remaining balance should be the debt ceiling minus the sum of the swapped amounts
        assertEq(
            daiBalancePsm, (maxDebtCeiling / RAY) - (idaiOutWad + daiOutWad), "fill: invalid PSM Dai balance after fill"
        );
    }

    function testFill_Revert_WhenDebtCeilingIsMaxedOut() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);

        // Sell less than the available liquidity.
        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        uint256 daiOutWad = litePsm.sellGem(address(0x1337), gemAmt);

        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(pgemBalanceKeg, igemAmt + gemAmt, "fill: invalid initial Keg gem balance");

        // Since there was enough liquidity, Dai balance should decrease.
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, idaiOutWad - daiOutWad, "fill: invalid initial PSM Dai balance");

        // After selling 100k + 50k gem, the debt would be 300k.
        // We need to set the debt ceiling lower than that.
        uint256 maxDebtCeiling = 150_000 * RAD;
        _setIlkLine(ilk, maxDebtCeiling, true);

        vm.expectRevert("LitePsm/fill-line-exceeded");
        litePsm.fill();
    }

    function testFill_Revert_WhenBalanced() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        // Initial sellGem should have left the pool perfectly balanced.
        assertEq(daiBalancePsm, _amtToWad(gemBalanceKeg), "fill: pool should be balanced after initial sellGem");

        vm.expectRevert("LitePsm/fill-unavailable");
        litePsm.fill();
    }

    function testTrim() public {
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);
        uint256 idebtWad = _totalDebt(ilk) / RAY;
        assertEq(idebtWad, 2 * idaiOutWad, "trim: invalid initial debt");

        // Buy some gem to reduce gem liquidity.
        uint256 gemAmt = _wadToAmt(50_000 * WAD);
        uint256 daiInWad = litePsm.buyGem(address(0x1337), gemAmt);

        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(pgemBalanceKeg, igemAmt - gemAmt, "trim: invalid initial Keg gem balance");

        // The amount of Dai in the PSM should have increased.
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, idaiOutWad + daiInWad, "trim: invalid initial PSM Dai balance");

        uint256 pdebtWad = _totalDebt(ilk) / RAY;
        assertEq(pdebtWad, idebtWad, "trim: unexpected debt change after buyGem");

        uint256 gush = litePsm.gush();
        vm.expectEmit(true, false, false, true);
        emit Trim(gush);
        litePsm.trim();

        // The amount of Dai in the PSM should be reduced by the amount increased before.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, idaiOutWad - daiInWad, "trim: invalid PSM Dai balance after trim");
    }

    function testTrim_ShouldUnwindRegardingDebtCeilingAndLiquidity() public {
        uint256 igemAmt = _wadToAmt(500_000 * WAD);
        uint256 idaiOutWad = litePsm.sellGem(address(0x1337), igemAmt);
        uint256 idebtWad = _totalDebt(ilk) / RAY;
        assertEq(idebtWad, 2 * idaiOutWad, "trim: invalid initial debt");

        // Buy some gem to reduce gem liquidity.
        uint256 gemAmt = _wadToAmt(200_000 * WAD);
        uint256 daiInWad = litePsm.buyGem(address(0x1337), gemAmt);

        // The amount of Dai in the PSM should have increased.
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(pdaiBalancePsm, idaiOutWad + daiInWad, "trim: invalid initial PSM Dai balance");

        uint256 pdebtWad = _totalDebt(ilk) / RAY;
        assertEq(pdebtWad, idebtWad, "trim: unexpected debt change after 1st buyGem");

        // There is 100k Dai remaining in Dai liquidity.
        // We need to set the debt ceiling lower than that.
        uint256 maxDebtCeiling = 75_000 * RAD;
        _setIlkLine(ilk, maxDebtCeiling, true);

        uint256 trimmedWad = litePsm.trim();

        // The amount of Dai in the PSM should not be larger than the debt ceiling.
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, maxDebtCeiling / RAY, "trim: invalid PSM Dai balance after 1st trim");

        uint256 debtWad = _totalDebt(ilk) / RAY;
        assertEq(debtWad, pdebtWad - trimmedWad, "trim: invalid debt after 1st trim");

        ////////////////////////////////////////////////////////////////////////////////

        // Trim is still not possible
        vm.expectRevert("LitePsm/trim-unavailable");
        litePsm.trim();

        ////////////////////////////////////////////////////////////////////////////////

        // Buy some gem to reduce gem liquidity again.
        // This will increase the amount of Dai available, requiring another trim.
        gemAmt = _wadToAmt(200_000 * WAD);
        daiInWad = litePsm.buyGem(address(0x1337), gemAmt);
        pdebtWad = debtWad;

        trimmedWad = litePsm.trim();

        // The amount of Dai in the PSM should not be larger than the debt ceiling once again.
        daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, maxDebtCeiling / RAY, "trim: invalid PSM Dai balance after 2nd trim");

        debtWad = _totalDebt(ilk) / RAY;
        assertEq(debtWad, pdebtWad - trimmedWad, "trim: invalid debt after 2nd trim");

        ////////////////////////////////////////////////////////////////////////////////

        // Buy the remaining gem to reduce gem liquidity to zero
        // This will increase the amount of Dai available, requiring yet another trim.
        gemAmt = _wadToAmt(100_000 * WAD);
        daiInWad = litePsm.buyGem(address(0x1337), gemAmt);
        pdebtWad = debtWad;

        trimmedWad = litePsm.trim();

        // The amount of Dai in the PSM should now be zero
        daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalancePsm, 0, "trim: invalid PSM Dai balance after 3rd trim");

        debtWad = _totalDebt(ilk) / RAY;
        assertEq(debtWad, 0, "trim: invalid debt after 3rd trim");

        ////////////////////////////////////////////////////////////////////////////////

        // Trim not possible anymore
        vm.expectRevert("LitePsm/trim-unavailable");
        litePsm.trim();
    }

    /*//////////////////////////////////
                    Fees
    //////////////////////////////////*/

    function testSellGem_NotEnoughDaiLiquidityWhenAccountingFees() public {
        // Set fees to 1%
        (uint256 tin,) = _setupFees(0.01 ether, 0.01 ether);
        uint256 igemAmt = _wadToAmt(100_000 * WAD);
        uint256 idaiWadOut = litePsm.sellGem(address(0x1337), igemAmt);

        uint256 pcut = litePsm.cut();
        uint256 pdaiTotalSupply = dss.dai.totalSupply();
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));

        assertEq(pcut, _fee(tin, igemAmt), "sellGem: invalid fees after initial swap");
        // The Dai balance of the PSM after the first sell should be the same as the swapped amount.
        assertEq(pdaiBalancePsm, idaiWadOut + pcut, "sellGem: invalid PSM Dai balance after initial swap");

        uint256 gemAmt = _wadToAmt(101_000 * WAD);
        uint256 addedFees = _fee(tin, gemAmt);

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, _fee(tin, gemAmt));
        uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

        {
            uint256 cut = litePsm.cut();
            assertEq(cut, pcut + addedFees, "sellGem: invalid cut change");
            uint256 daiTotalSupply = dss.dai.totalSupply();
            // Dai total supply should increase by (2x the swapped Dai) (plus fees)
            assertEq(
                daiTotalSupply,
                pdaiTotalSupply + 2 * daiOutWad + addedFees,
                "sellGem: Dai total supply changed unexpectedly"
            );
        }

        {
            // Since there was not enough liquidity, Dai was minted to leave the PSM perfectly balanced
            uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
            assertEq(daiBalancePsm, pdaiBalancePsm + daiOutWad + addedFees, "sellGem: invalid PSM Dai balance change");
            uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
            assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");
        }

        {
            uint256 gemBalanceKeg = gem.balanceOf(address(keg));
            assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "sellGem: invalid keg gem balance change");
            uint256 gemBalanceThis = gem.balanceOf(address(this));
            assertEq(gemBalanceThis, pgemBalanceThis - gemAmt, "sellGem: invalid address(this) USDC balance change");
        }
    }

    function testAccumulatedFees_Fuzz(uint256 gemAmt, uint256 tin_, uint256 tout_) public {
        gemAmt = bound(gemAmt, _wadToAmt(1 * WAD), gem.balanceOf(address(this)) / 2);
        uint256 gemWad = _amtToWad(gemAmt);
        uint256 accFees = 0;
        (uint256 tin, uint256 tout) = _setupFees(tin_, tout_);

        uint256 expectedSellFee = gemWad * tin / WAD;
        uint256 daiWadOut = litePsm.sellGem(address(this), gemAmt);
        assertEq(gemWad - daiWadOut, expectedSellFee, "cut: invalid fee on sellGem");
        accFees += gemWad - daiWadOut;

        uint256 expectedBuyFee = gemWad * tout / WAD;
        uint256 daiWadIn = litePsm.buyGem(address(this), gemAmt);
        assertEq(daiWadIn - gemWad, expectedBuyFee, "cut: invalid fee on buyGem");
        accFees += daiWadIn - gemWad;

        assertEq(litePsm.cut(), accFees, "cut: invalid accumulated cut");
    }

    function testChug_Fuzz(uint256 gemAmt, uint256 tin_, uint256 tout_) public {
        gemAmt = bound(gemAmt, _wadToAmt(1 * WAD), gem.balanceOf(address(this)) / 2);
        _setupFees(tin_, tout_);

        litePsm.sellGem(address(this), gemAmt);
        litePsm.buyGem(address(this), gemAmt);

        uint256 pvowDai = dss.vat.dai(address(dss.vow));
        uint256 pdaiBalance = dss.dai.balanceOf(address(litePsm));
        uint256 pcut = litePsm.cut();

        vm.expectEmit(false, false, false, true);
        emit Chug(pcut);
        litePsm.chug();

        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 cut = litePsm.cut();

        assertEq(vowDai, pvowDai + (pcut * RAY), "chug: invalid vat.dai(vow) change after chug");
        assertEq(daiBalancePsm, pdaiBalance - pcut, "chug: invalid dai.balanceOf(litePsm) change after chug");
        assertEq(cut, 0, "chug: invalid cut after chug");
    }

    function testChug_Revert_WhenZeroAccumulatedFees() public {
        vm.expectRevert("LitePsm/chug-unavailable");
        litePsm.chug();
    }

    function testChug_Revert_WhenVowIsAddressZero() public {
        _setupFees(0.001 ether, 0.001 ether);
        // Simulate vow being set to `address(0)`
        litePsm.file("vow", address(0));

        // Accumulate some fees
        uint256 gemWad = 50_000 * WAD;
        uint256 gemAmt = _wadToAmt(gemWad);
        litePsm.sellGem(address(this), gemAmt);
        litePsm.buyGem(address(this), gemAmt);

        vm.expectRevert("LitePsm/chug-missing-vow");
        litePsm.chug();
    }

    /*//////////////////////////////////
        Permissioned No Fee Swapping
    //////////////////////////////////*/

    function testPermissionedSwapsNoFee() public {
        uint256 igemAmt = _wadToAmt(500_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);
        _setupFees(0.001 ether, 0.001 ether);
        _setupFeeExemption(address(this));

        uint256 gemWad = 100_000 * WAD;
        uint256 gemAmt = _wadToAmt(gemWad);

        // Sell gems

        uint256 pcut = litePsm.cut();
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pgemBalanceThis = gem.balanceOf(address(this));
        uint256 pgemBalanceKeg = gem.balanceOf(address(keg));

        uint256 daiWadOut = litePsm.sellGemNoFee(address(this), gemAmt);
        assertEq(daiWadOut, gemWad, "no fees: unexpected fee on sellGemNoFee");

        uint256 cut = litePsm.cut();
        assertEq(cut, pcut, "no fees: unexpected accumulated cut on sellGemNoFee");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis + daiWadOut, "no fees: invalid address(this) Dai balance after sellGemNoFee"
        );

        uint256 gemBalanceThis = gem.balanceOf(address(this));
        assertEq(
            gemBalanceThis, pgemBalanceThis - gemAmt, "no fees: invalid address(this) gem balance after sellGemNoFee"
        );
        uint256 gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg + gemAmt, "no fees: invalid keg gem balance after sellGemNoFee");

        // Buy gems

        pcut = litePsm.cut();
        pdaiBalanceThis = dss.dai.balanceOf(address(this));
        pgemBalanceKeg = gem.balanceOf(address(keg));
        pgemBalanceThis = gem.balanceOf(address(this));

        uint256 daiWadIn = litePsm.buyGemNoFee(address(this), gemAmt);
        assertEq(daiWadIn, gemWad, "no fees: unexpected fee on buyGem");

        cut = litePsm.cut();
        assertEq(cut, pcut, "no fees: unexpected accumulated cut on buyGemNoFee");

        daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis - daiWadIn, "no fees: invalid address(this) Dai balance after buyGemNoFee"
        );

        gemBalanceThis = gem.balanceOf(address(this));
        assertEq(
            gemBalanceThis, pgemBalanceThis + gemAmt, "no fees: invalid address(this) gem balance after buyGemNoFee"
        );
        gemBalanceKeg = gem.balanceOf(address(keg));
        assertEq(gemBalanceKeg, pgemBalanceKeg - gemAmt, "no fees: invalid keg gem balance after buyGemNoFee");
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    function testExit() public {
        address usr = address(0x1234);
        uint256 gemWad = 50 * WAD;
        uint256 gemAmt = _wadToAmt(gemWad);
        litePsm.sellGem(address(0x1337), gem.balanceOf(address(this)));
        // Simulate emergency shutdown by slipping some `gem` into this contract.
        dss.vat.slip(ilk, address(this), int256(gemWad));

        vm.expectEmit(true, false, false, true);
        emit Exit(usr, gemAmt);
        litePsm.exit(usr, gemAmt);

        assertEq(dss.vat.gem(ilk, address(this)), 0, "exit: invalid vat.gem after exit");
        assertEq(gem.balanceOf(usr), gemAmt, "exit: invalid gem balance before exit");
    }

    function testExit_Revert_WhenSenderHasNoGem() public {
        uint256 gemWad = 50 * WAD;
        uint256 gemAmt = _wadToAmt(gemWad);

        litePsm.sellGem(address(0x1337), gem.balanceOf(address(this)));

        // Should revert because of underflow on vat.frob(), where there is no revert message
        vm.expectRevert();
        litePsm.exit(address(0x1234), gemAmt);
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

    function _setupFeeExemption(address who) internal {
        litePsm.kiss(who);
    }

    function _totalDebt(bytes32 ilk_) internal view returns (uint256) {
        (uint256 Art, uint256 rate,,,) = dss.vat.ilks(ilk_);
        return Art * rate;
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

    event Fill(uint256 wad);
    event Trim(uint256 wad);
    event Chug(uint256 wad);
    event Exit(address indexed usr, uint256 amt);
    event SellGem(address indexed owner, uint256 amt, uint256 fee);
    event BuyGem(address indexed owner, uint256 amt, uint256 fee);
}

/*//////////////////////////////////////////////////////////////////////////////
                                      USDC
//////////////////////////////////////////////////////////////////////////////*/

contract DssLitePsmUsdcTest is DssLitePsmBaseTest {
    function _ilk() internal pure override returns(bytes32) {
        return "LITE_PSM_USDC_A";
    }

    function _setUpGem() internal override returns(address) {
        address _gem = dss.chainlog.getAddress("USDC");
        // Mints 100_000_000 gem into the test contract.
        GodMode.setBalance(_gem, address(this), 100_000_000 * (10 ** GemLike(_gem).decimals()));

        return _gem;
    }

    function testBuyGem_Revert_WhenKegHasNoGem() public {
        assertEq(gem.balanceOf(address(keg)), 0, "buyGem: initial keg gem balance not zero");

        // Error from the USDC implementation on Mainnet
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        litePsm.buyGem(address(this), 1);
    }
}

/*//////////////////////////////////////////////////////////////////////////////
                                      USDP
//////////////////////////////////////////////////////////////////////////////*/

contract DssLitePsmUsdpTest is DssLitePsmBaseTest {
    function _ilk() internal pure override returns(bytes32) {
        return "LITE_PSM_PAXUSD_A";
    }

    function _setUpGem() internal override returns(address) {
        address _gem = dss.chainlog.getAddress("PAXUSD");
        // Mints 100_000_000 gem into the test contract.
        GodMode.setBalance(_gem, address(this), 100_000_000 * (10 ** GemLike(_gem).decimals()));

        return _gem;
    }


    function testBuyGem_Revert_WhenKegHasNoGem() public {
        assertEq(gem.balanceOf(address(keg)), 0, "buyGem: initial keg gem balance not zero");

        // Error from the USDP implementation on Mainnet
        vm.expectRevert("insufficient funds");
        litePsm.buyGem(address(this), 1);
    }
}

/*//////////////////////////////////////////////////////////////////////////////
                                      GUSD
//////////////////////////////////////////////////////////////////////////////*/

interface ERC20Proxy {
    function erc20Impl() external returns (address);

    function totalSupply() external returns (uint256);
}

interface ERC20Impl {
    function erc20Store() external returns (address);
}

interface ERC20Store {
    function setTotalSupply(uint256 _newTotalSupply) external;

    function setBalance(address _owner, uint256 _newBalance) external;
}

contract DssLitePsmGusdTest is DssLitePsmBaseTest {
    function _ilk() internal pure override returns(bytes32) {
        return "LITE_PSM_GUSD_A";
    }

    function _setUpGem() internal override returns(address) {
        address _gem = dss.chainlog.getAddress("GUSD");
        // Add GUSD blance
        address impl = ERC20Proxy(address(_gem)).erc20Impl();
        ERC20Store store = ERC20Store(ERC20Impl(impl).erc20Store());

        vm.startPrank(impl);

        store.setBalance(address(this), 100_000_000 * (10 ** GemLike(_gem).decimals()));
        store.setTotalSupply(ERC20Proxy(_gem).totalSupply() + 100_000_000 * (10 ** GemLike(_gem).decimals()));

        vm.stopPrank();

        return _gem;
    }


    function testBuyGem_Revert_WhenKegHasNoGem() public {
        assertEq(gem.balanceOf(address(keg)), 0, "buyGem: initial keg gem balance not zero");

        // No error from the GUS implementation on Mainnet
        vm.expectRevert();
        litePsm.buyGem(address(this), 1);
    }
}
