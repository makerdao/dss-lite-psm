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
import {DssKeg} from "src/DssKeg.sol";
import {DssLitePsm} from "src/DssLitePsm.sol";
import {DssLitePsmOracle} from "src/DssLitePsmOracle.sol";

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

contract DssLitePsmTest is DssTest {
    using stdStorage for StdStorage;

    bytes32 constant ilk = "LITE_PSM_USDC_A";
    address immutable chainlog = vm.envAddress("CHANGELOG");

    DssInstance dss;
    GemLike usdc;
    DssKeg keg;
    Harness__DssLitePsm litePsm;
    DssLitePsmOracle oracle;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(chainlog);

        MCD.giveAdminAccess(dss);

        usdc = GemLike(dss.chainlog.getAddress("USDC"));

        // There is a circular dependency between `LitePsm` and `Keg`, so we need to pre-compute
        // their addresses to be able to provide all constructor parameters.
        uint256 nonce = vm.getNonce(address(this));
        address kegAddr = computeCreateAddress(address(this), nonce);
        address litePsmAddr = computeCreateAddress(address(this), nonce + 1);

        keg = new DssKeg(litePsmAddr, address(usdc));
        litePsm = new Harness__DssLitePsm(ilk, address(usdc), address(dss.daiJoin), kegAddr);
        oracle = new DssLitePsmOracle(address(litePsm));

        MCD.initIlk(dss, ilk, address(0), address(oracle));
        uint256 dline = 100_000_000 * RAD;
        dss.vat.file("Line", dss.vat.Line() + dline);
        dss.vat.file(ilk, "line", dline);

        // Authorizes the new LitePsm on the Vat
        GodMode.setWard(dss.vat, address(litePsm), 1);

        // Mints 100_000_000 USDC into the test contract.
        GodMode.setBalance(address(usdc), address(this), _wadToAmt(100_000_000 * WAD));
        usdc.approve(address(litePsm), type(uint256).max);

        // Mints 100_000_000 Dai into the test contract.
        GodMode.setBalance(dss.dai, address(this), 100_000_000 * WAD);
        dss.dai.approve(address(litePsm), type(uint256).max);

        // keg to give unlimited USDC approval to the litePsm.
        vm.prank(address(keg)); usdc.approve(address(litePsm), type(uint256).max);

        // Setup the vow for litePsm
        litePsm.file("vow", address(dss.vow));

        litePsm.file("buf", 10_000_000 * WAD);

        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(usdc), "USDC");
    }

    /*//////////////////////////////////
               Sanity Checks
    //////////////////////////////////*/

    function testTo18ConversionFactor() public {
        assertEq(litePsm.__to18ConversionFactor(), 10 ** (18 - usdc.decimals()));
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
        checkAuth(address(litePsm), "DssLitePsm");
    }

    function testAuthMethods() public {
        // Revoke ward role for this contract
        GodMode.setWard(address(litePsm), address(this), 0);
        checkModifier(address(litePsm), "DssLitePsm/not-authorized", [DssLitePsm.kiss.selector, DssLitePsm.diss.selector]);
    }

    function testOnlyBudMethods() public {
        checkModifier(
            address(litePsm), "DssLitePsm/not-bud", [DssLitePsm.buyGemNoFee.selector, DssLitePsm.sellGemNoFee.selector]
        );
    }

    function testFile() public {
        /*//////////////////////////////////
                     tin, tout & buf
        //////////////////////////////////*/
        assertEq(litePsm.wards(address(this)), 1, "Invalid ward setting");

        vm.expectRevert("DssLitePsm/out-of-range");
        litePsm.file("tin", 2 * WAD);

        vm.expectRevert("DssLitePsm/out-of-range");
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
        assertEq(pdaiBalancePsm, 10_000_000 * WAD);
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));
        uint256 pusdcBalanceThis = usdc.balanceOf(address(this));

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

        uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
        assertEq(usdcBalanceKeg, pusdcBalanceKeg + gemAmt, "sellGem: invalid keg USDC balance change");
        uint256 usdcBalanceThis = usdc.balanceOf(address(this));
        assertEq(usdcBalanceThis, pusdcBalanceThis - gemAmt, "sellGem: invalid address(this) USDC balance change");
    }

    // function testSellGemFuzz(uint256 igemAmt, uint256 gemAmt) public {
    //     litePsm.fill();

    //     // Since we are selling gem twice, we can only sell part of it in the setup.
    //     igemAmt = bound(igemAmt, 0, (usdc.balanceOf(address(this)) / 2) - 1);
    //     // Next we sell up to the existing liquidity to force a rebalance.
    //     gemAmt = bound(gemAmt, 0, igemAmt);
    //     // Test the flow when there is enough Dai liquidity in the PSM
    //     litePsm.sellGem(address(0x1337), igemAmt);

    //     uint256 pdaiTotalSupply = dss.dai.totalSupply();
    //     uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
    //     uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
    //     uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));
    //     uint256 pusdcBalanceThis = usdc.balanceOf(address(this));

    //     vm.expectEmit(true, true, true, true);
    //     emit SellGem(address(this), gemAmt, 0);
    //     uint256 daiOutWad = litePsm.sellGem(address(this), gemAmt);

    //     uint256 daiTotalSupply = dss.dai.totalSupply();
    //     // Dai total supply should not be affected.
    //     assertEq(daiTotalSupply, pdaiTotalSupply, "sellGem: Dai total supply changed unexpectedly");

    //     // Available Dai liquidity should reduce by the same amount being swapped.
    //     // Automation must kick in to rebalance the PSM.
    //     uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
    //     assertEq(daiBalancePsm, pdaiBalancePsm - daiOutWad, "sellGem: invalid PSM Dai balance change");
    //     uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
    //     assertEq(daiBalanceThis, pdaiBalanceThis + daiOutWad, "sellGem: invalid address(this) Dai balance change");

    //     uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
    //     assertEq(usdcBalanceKeg, pusdcBalanceKeg + gemAmt, "sellGem: invalid keg USDC balance change");
    //     uint256 usdcBalanceThis = usdc.balanceOf(address(this));
    //     assertEq(usdcBalanceThis, pusdcBalanceThis - gemAmt, "sellGem: invalid address(this) USDC balance change");
    // }

    function testBuyGem() public {
        litePsm.fill();

        uint256 igemAmt = _wadToAmt(10_000_000 * WAD);
        uint256 gemAmt = _wadToAmt(175_000 * WAD);
        litePsm.sellGem(address(0x1337), igemAmt);

        address usr = address(0xd34d);
        uint256 pusdcBalanceUsr = usdc.balanceOf(usr);
        uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));
        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

        vm.expectEmit(true, false, false, true);
        emit BuyGem(usr, gemAmt, 0);
        uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

        uint256 usdcBalanceUsr = usdc.balanceOf(usr);
        uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
        assertEq(usdcBalanceUsr, pusdcBalanceUsr + gemAmt, "buyGem: invalid usr USDC balance after buyGem");
        assertEq(usdcBalanceKeg, pusdcBalanceKeg - gemAmt, "buyGem: invalid keg USDC balance after buyGem");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
        assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid PSM Dai balance after buyGem");
    }

    // function testBuyGemFuzz(uint256 igemAmt, uint256 gemAmt) public {
    //     litePsm.fill();
    //     igemAmt = bound(igemAmt, 1, usdc.balanceOf(address(this)));
    //     gemAmt = bound(gemAmt, 1, igemAmt);
    //     litePsm.sellGem(address(0x1337), igemAmt);

    //     address usr = address(0xd34d);
    //     uint256 pusdcBalanceUsr = usdc.balanceOf(usr);
    //     uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));
    //     uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
    //     uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));

    //     vm.expectEmit(true, false, false, true);
    //     emit BuyGem(usr, gemAmt, 0);
    //     uint256 daiInWad = litePsm.buyGem(usr, gemAmt);

    //     uint256 usdcBalanceUsr = usdc.balanceOf(usr);
    //     uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
    //     assertEq(usdcBalanceUsr, pusdcBalanceUsr + gemAmt, "buyGem: invalid usr USDC balance after buyGem");
    //     assertEq(usdcBalanceKeg, pusdcBalanceKeg - gemAmt, "buyGem: invalid keg USDC balance after buyGem");

    //     uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
    //     uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
    //     assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "buyGem: invalid address(this) Dai balance after buyGem");
    //     assertEq(daiBalancePsm, pdaiBalancePsm + daiInWad, "buyGem: invalid PSM Dai balance after buyGem");
    // }

    function testBuyGemRevertWhenKegHasNoGem() public {
        assertEq(usdc.balanceOf(address(keg)), 0, "buyGem: initial keg USDC balance not zero");

        // Error from the USDC implementation on Mainnet
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        litePsm.buyGem(address(this), 1);
    }

    // /*//////////////////////////////////
    //             Bookkeeping
    // //////////////////////////////////*/

    function testFill() public {
        dss.vat.fold(ilk, address(111), 1);
        vm.expectRevert("DssLitePsm/rate-not-RAY");
        litePsm.fill();

        dss.vat.fold(ilk, address(111), -1);

        assertEq(dss.dai.balanceOf(address(litePsm)), 0);
        assertEq(_totalDebt(ilk), 0);

        vm.expectEmit(true, true, true, true);
        emit Fill(10_000_000 * WAD);
        assertEq(litePsm.fill(), 10_000_000 * WAD);

        vm.expectRevert("DssLitePsm/nothing-to-fill"); // buf == pre-minted unused DAI
        litePsm.fill();

        litePsm.file("buf", 8_000_000 * WAD);

        vm.expectRevert("DssLitePsm/nothing-to-fill"); // buf < pre-minted unused DAI
        litePsm.fill();

        litePsm.file("buf", 10_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(_totalDebt(ilk), 10_000_000 * RAD);

        litePsm.sellGem(address(0x1337), _wadToAmt(10_000_000 * WAD));

        assertEq(dss.dai.balanceOf(address(litePsm)), 0);
        assertEq(_totalDebt(ilk), 10_000_000 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Fill(10_000_000 * WAD);
        assertEq(litePsm.fill(), 10_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(_totalDebt(ilk), 20_000_000 * RAD);

        dss.vat.file(ilk, "line", 25_000_000 * RAD); // Next fill will limit by line

        litePsm.sellGem(address(0x1337), _wadToAmt(10_000_000 * WAD));

        assertEq(dss.dai.balanceOf(address(litePsm)), 0);
        assertEq(_totalDebt(ilk), 20_000_000 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Fill(5_000_000 * WAD);
        assertEq(litePsm.fill(), 5_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 5_000_000 * WAD);
        assertEq(_totalDebt(ilk), 25_000_000 * RAD);

        vm.expectRevert("DssLitePsm/nothing-to-fill"); // line == debt
        litePsm.fill();

        dss.vat.file(ilk, "line", 20_000_000 * RAD);

        vm.expectRevert("DssLitePsm/nothing-to-fill"); // line <= debt
        litePsm.fill();

        dss.vat.file(ilk, "line", 50_000_000 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Fill(5_000_000 * WAD);
        assertEq(litePsm.fill(), 5_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(_totalDebt(ilk), 30_000_000 * RAD);
    }

    function testTrim() public {
        dss.vat.fold(ilk, address(111), 1);
        vm.expectRevert("DssLitePsm/rate-not-RAY");
        litePsm.trim();

        dss.vat.fold(ilk, address(111), -1);

        litePsm.fill();
        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));
        litePsm.fill();

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(_totalDebt(ilk), 20_000_000 * RAD);

        vm.expectRevert("DssLitePsm/nothing-to-trim"); // buf == pre-minted unused DAI
        litePsm.trim();

        litePsm.file("buf", 12_000_000 * WAD);

        vm.expectRevert("DssLitePsm/nothing-to-trim"); // buf > pre-minted unused DAI
        litePsm.trim();

        litePsm.file("buf", 10_000_000 * WAD);

        litePsm.buyGem(address(0x1337), _wadToAmt(5_000_000 * WAD));

        assertEq(dss.dai.balanceOf(address(litePsm)), 15_000_000 * WAD);
        assertEq(_totalDebt(ilk), 20_000_000 * RAD);

        vm.expectEmit(true, true, true, true);
        emit Trim(5_000_000 * WAD);
        assertEq(litePsm.trim(), 5_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(_totalDebt(ilk), 15_000_000 * RAD);

        dss.vat.file(ilk, "line", 12_000_000 * RAD); // Next trim will trigger by line

        vm.expectEmit(true, true, true, true);
        emit Trim(3_000_000 * WAD);
        assertEq(litePsm.trim(), 3_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 7_000_000 * WAD);
        assertEq(_totalDebt(ilk), 12_000_000 * RAD);

        dss.vat.file(ilk, "line", 4_000_000 * RAD); // Next trim will trigger by line but limited by balance

        vm.expectEmit(true, true, true, true);
        emit Trim(7_000_000 * WAD);
        assertEq(litePsm.trim(), 7_000_000 * WAD);

        assertEq(dss.dai.balanceOf(address(litePsm)), 0);
        assertEq(_totalDebt(ilk), 5_000_000 * RAD);
    }

    // /*//////////////////////////////////
    //                 Fees
    // //////////////////////////////////*/

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
        uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));
        uint256 pusdcBalanceThis = usdc.balanceOf(address(this));

        uint256 pcut = _cut();
        assertEq(pcut, _fee(tin, gemAmt), "sellGem: invalid fees after initial swap");
        // The Dai balance of the PSM after the first sell should be the same as the swapped amount.
        assertEq(pdaiBalancePsm, 10_000_000 * WAD - daiWadOut, "sellGem: invalid PSM Dai balance after initial swap");

        vm.expectEmit(true, true, true, true);
        emit BuyGem(address(this), gemAmt / 2, _fee(tout, gemAmt / 2));
        uint256 daiInWad = litePsm.buyGem(address(this), gemAmt / 2);

        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
        assertEq(_cut(), pcut + _fee(tout, gemAmt / 2), "sellGem: invalid cut change");
        assertEq(daiBalancePsm, 10_000_000 * WAD - daiWadOut + daiInWad, "sellGem: invalid PSM Dai balance change");
        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(daiBalanceThis, pdaiBalanceThis - daiInWad, "sellGem: invalid address(this) Dai balance change");
        assertEq(usdcBalanceKeg, pusdcBalanceKeg - gemAmt / 2, "sellGem: invalid keg USDC balance change");
        uint256 usdcBalanceThis = usdc.balanceOf(address(this));
        assertEq(usdcBalanceThis, pusdcBalanceThis + gemAmt / 2, "sellGem: invalid address(this) USDC balance change");
    }

    // function testAccumulatedFeesFuzz(uint256 gemAmt, uint256 tin_, uint256 tout_) public {
    //     gemAmt = bound(gemAmt, 1, usdc.balanceOf(address(this)) / 2);
    //     uint256 gemWad = _amtToWad(gemAmt);
    //     uint256 accFees = 0;
    //     (uint256 tin, uint256 tout) = _setupFees(tin_, tout_);

    //     uint256 expectedSellFee = gemWad * tin / WAD;
    //     uint256 daiWadOut = litePsm.sellGem(address(this), gemAmt);
    //     assertEq(gemWad - daiWadOut, expectedSellFee, "cut: invalid fee on sellGem");
    //     accFees += gemWad - daiWadOut;

    //     uint256 expectedBuyFee = gemWad * tout / WAD;
    //     uint256 daiWadIn = litePsm.buyGem(address(this), gemAmt);
    //     assertEq(daiWadIn - gemWad, expectedBuyFee, "cut: invalid fee on buyGem");
    //     accFees += daiWadIn - gemWad;

    //     assertEq(litePsm.cut(), accFees, "cut: invalid accumulated cut");
    // }

    function testChugFuzz(uint256 gemAmt, uint256 tin_, uint256 tout_) public {
        litePsm.fill();

        gemAmt = bound(gemAmt, 1, _wadToAmt(10_000_000 * WAD));
        _setupFees(tin_, tout_);

        litePsm.sellGem(address(this), gemAmt);
        litePsm.buyGem(address(this), gemAmt);

        uint256 pvowDai = dss.vat.dai(address(dss.vow));
        uint256 pdaiBalancePsm = dss.dai.balanceOf(address(litePsm));
        uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
        uint256 cut = _cut();

        vm.expectEmit(false, false, false, true);
        emit Chug(cut);
        litePsm.chug();

        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 daiBalancePsm = dss.dai.balanceOf(address(litePsm));

        assertEq(vowDai, pvowDai + cut * RAY, "chug: invalid vat.dai(vow) change after chug");
        assertEq(daiBalancePsm, pdaiBalancePsm - cut, "chug: invalid dai.balanceOf(litePsm) change after chug");
        assertEq(daiBalancePsm + usdcBalanceKeg * litePsm.__to18ConversionFactor() - 10_000_000 * WAD, 0, "chug: invalid cut after chug");
    }

    function testChugRevertWhenVowIsAddressZero() public {
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

    function testChugRevertWhenZeroAccumulatedFees() public {
        vm.expectRevert("DssLitePsm/nothing-to-chug");
        litePsm.chug();
    }

    function testChugPartialDaiBalance() public {
        litePsm.fill();

        litePsm.file("tin", WAD / 100);
        litePsm.file("tout", WAD / 100);

        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));

        assertEq(_cut(), 100_000 * WAD);

        litePsm.file("tin", 0);
        litePsm.sellGem(address(this), _wadToAmt(40_000 * WAD)); // Leave the PSM without enough balance to redeem the whole amount of fees

        assertEq(_cut(), 100_000 * WAD); // Still the fee didn't change, however now is partially in USDC

        assertEq(litePsm.chug(), 60_000 * WAD);

        assertEq(_cut(), 40_000 * WAD);
    }

    function testChugRevertNoDaiBalance() public {
        litePsm.fill();

        litePsm.file("tin", WAD / 100);
        litePsm.file("tout", WAD / 100);

        litePsm.sellGem(address(this), _wadToAmt(10_000_000 * WAD));

        assertEq(_cut(), 100_000 * WAD);

        litePsm.file("tin", 0);
        litePsm.sellGem(address(this), _wadToAmt(100_000 * WAD)); // Leave the PSM without any DAI balance

        assertEq(_cut(), 100_000 * WAD); // Still the fee didn't change, however now is pure USDC

        // Then chug will revert
        vm.expectRevert("DssLitePsm/nothing-to-chug");
        litePsm.chug();
    }

    // /*//////////////////////////////////
    //     Permissioned No Fee Swapping
    // //////////////////////////////////*/

    function testPermissionedSwapsNoFee() public {
        litePsm.fill();

        _setupFees(0.001 ether, 0.001 ether);

        uint256 gemAmtWad = 500_000 * WAD;
        uint256 gemAmt = _wadToAmt(gemAmtWad);

        uint256 pdaiBalanceThis = dss.dai.balanceOf(address(this));
        uint256 pusdcBalanceThis = usdc.balanceOf(address(this));
        uint256 pusdcBalanceKeg = usdc.balanceOf(address(keg));

        litePsm.kiss(address(this));
        uint256 daiWadOut = litePsm.sellGemNoFee(address(this), gemAmt);
        assertEq(daiWadOut, gemAmtWad, "no fees: unexpected fee on sellGemNoFee");

        uint256 daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis + daiWadOut, "no fees: invalid address(this) Dai balance after sellGemNoFee"
        );

        uint256 usdcBalanceThis = usdc.balanceOf(address(this));
        assertEq(
            usdcBalanceThis, pusdcBalanceThis - gemAmt, "no fees: invalid address(this) USDC balance after sellGemNoFee"
        );
        uint256 usdcBalanceKeg = usdc.balanceOf(address(keg));
        assertEq(usdcBalanceKeg, pusdcBalanceKeg + gemAmt, "no fees: invalid keg USDC balance after sellGemNoFee");

        // Buy gems

        pdaiBalanceThis = dss.dai.balanceOf(address(this));
        pusdcBalanceKeg = usdc.balanceOf(address(keg));
        pusdcBalanceThis = usdc.balanceOf(address(this));

        uint256 daiWadIn = litePsm.buyGemNoFee(address(this), gemAmt);
        assertEq(daiWadIn, gemAmtWad, "no fees: unexpected fee on buyGem");

        daiBalanceThis = dss.dai.balanceOf(address(this));
        assertEq(
            daiBalanceThis, pdaiBalanceThis - daiWadIn, "no fees: invalid address(this) Dai balance after buyGemNoFee"
        );

        usdcBalanceThis = usdc.balanceOf(address(this));
        assertEq(
            usdcBalanceThis, pusdcBalanceThis + gemAmt, "no fees: invalid address(this) USDC balance after buyGemNoFee"
        );
        usdcBalanceKeg = usdc.balanceOf(address(keg));
        assertEq(usdcBalanceKeg, pusdcBalanceKeg - gemAmt, "no fees: invalid keg USDC balance after buyGemNoFee");
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    function testExit() public {
        litePsm.fill();
        litePsm.sellGem(address(0x1337), _wadToAmt(10_000_000 * WAD));
        litePsm.fill();

        assertEq(dss.dai.balanceOf(address(litePsm)), 10_000_000 * WAD);
        assertEq(usdc.balanceOf(address(litePsm)), 0);
        assertEq(usdc.balanceOf(address(keg)), _wadToAmt(10_000_000 * WAD));
        assertEq(_ink(ilk, address(litePsm)), 20_000_000 * WAD);

        vm.expectRevert("DssLitePsm/vat-still-live");
        litePsm.cage();

        dss.end.cage();

        vm.expectRevert("DssLitePsmOracle/ilk-not-caged-in-shutdown");
        dss.end.cage(ilk);

        uint256 prevVatDaiVow = dss.vat.dai(address(dss.vow));

        litePsm.cage();

        assertEq(dss.vat.dai(address(dss.vow)), prevVatDaiVow + 10_000_000 * RAD);
        assertEq(dss.dai.balanceOf(address(litePsm)), 0);
        assertEq(usdc.balanceOf(address(litePsm)), _wadToAmt(10_000_000 * WAD));
        assertEq(usdc.balanceOf(address(keg)), 0);
        assertEq(_ink(ilk, address(litePsm)), 20_000_000 * WAD);
        assertEq(litePsm.fix(), WAD / (2 * 10**(18-6)));

        dss.end.cage(ilk);
        assertEq(dss.end.Art(ilk), 20_000_000 * WAD);

        dss.end.skim(ilk, address(litePsm));

        assertEq(_ink(ilk, address(litePsm)), 0);
        assertEq(dss.vat.gem(ilk, address(dss.end)), 20_000_000 * WAD);

        // Half cleaning the right way, half hacking to get surplus == 0
        dss.vow.heal(_min(dss.vat.dai(address(dss.vow)), dss.vat.sin(address(dss.vow))));
        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(dss.vow)).depth(0).checked_write(uint256(0));

        // Hacking to have exactly 5B total DAI supply
        stdstore.target(address(dss.vat)).sig("debt()").depth(0).checked_write(uint256(5_000_000_000 * RAD));

        vm.warp(block.timestamp + dss.end.wait());

        dss.end.thaw();

        dss.end.flow(ilk);
        assertEq(dss.end.fix(ilk), 20_000_000 * RAY / 5_000_000_000);

        // Hacking to give address(this)
        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(this)).depth(0).checked_write(uint256(1_000_000 * RAD));

        dss.vat.hope(address(dss.end));
        dss.end.pack(1_000_000 * WAD);
        assertEq(dss.end.bag(address(this)), 1_000_000 * WAD);

        dss.end.cash(ilk, 1_000_000 * WAD);

        assertEq(dss.vat.gem(ilk, address(this)), 4_000 * WAD); // 1_000_000 * WAD * 20_000_000 / 5_000_000_000;

        uint256 prevUsdcBalance = usdc.balanceOf(address(this));
        litePsm.exit(address(this), 4_000 * WAD);
        assertEq(usdc.balanceOf(address(this)), prevUsdcBalance + _wadToAmt(2_000 * WAD));
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

    function _totalDebt(bytes32 ilk_) internal view returns (uint256) {
        (uint256 Art, uint256 rate,,,) = dss.vat.ilks(ilk_);
        return Art * rate;
    }

    function _ink(bytes32 ilk_, address urn_) internal view returns (uint256) {
        (uint256 ink,) = dss.vat.urns(ilk_, urn_);
        return ink;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x < y ? x : y;
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
        wad = amt * 10 ** (18 - usdc.decimals());
    }

    function _wadToAmt(uint256 wad) internal view returns (uint256 amt) {
        amt = wad / 10 ** (18 - usdc.decimals());
    }

    function _cut() internal view returns (uint256 amt) {
        (, uint256 art) = dss.vat.urns(ilk, address(litePsm));
        amt = dss.dai.balanceOf(address(litePsm)) + usdc.balanceOf(address(keg)) * litePsm.__to18ConversionFactor() - art;
    }

    event Fill(uint256 wad);
    event Trim(uint256 wad);
    event Chug(uint256 wad);
    event Exit(address indexed usr, uint256 wad, uint256 gemAmt);
    event SellGem(address indexed owner, uint256 value, uint256 fee);
    event BuyGem(address indexed owner, uint256 value, uint256 fee);
}
