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

import {DssTest, DssInstance, MCD, GodMode} from "dss-test/DssTest.sol";
import {DssProxyPsm} from "./DssProxyPsm.sol";

interface GemLike {
    function approve(address spender, uint256 value) external;
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract Harness__DssProxyPsm is DssProxyPsm {
    constructor(bytes32 ilk_, address gem_, address daiJoin_, address keg_) DssProxyPsm(ilk_, gem_, daiJoin_, keg_) {}

    function __to18ConversionFactor() external view returns (uint256) {
        return to18ConversionFactor;
    }
}

contract DssProxyPsmTest is DssTest {
    bytes32 constant ilk = "PROXY_PSM_USDC_A";
    address immutable chainlog = vm.envAddress("CHAINLOG");

    DssInstance dss;
    GemLike usdc;
    address keg = address(0x1337);
    Harness__DssProxyPsm proxyPsm;

    function setUp() public {
        vm.createSelectFork("mainnet");
        dss = MCD.loadFromChainlog(chainlog);

        MCD.giveAdminAccess(dss);

        MCD.initIlk(dss, ilk);
        uint256 dline = 1_000_000_000 * RAD;
        dss.vat.file("Line", dss.vat.Line() + dline);
        dss.vat.file(ilk, "line", dline);

        usdc = GemLike(dss.chainlog.getAddress("USDC"));
        proxyPsm = new Harness__DssProxyPsm(ilk, address(usdc), address(dss.daiJoin), keg);

        // Authorizes the new ProxyPsm on the Vat
        GodMode.setWard(dss.vat, address(proxyPsm), 1);

        // Mints 100_000_000 USDC into the test contract.
        GodMode.setBalance(address(usdc), address(this), 100_000_000 * (10 ** usdc.decimals()));
        usdc.approve(address(proxyPsm), type(uint256).max);

        // Mints 100_000_000 Dai into the test contract.
        GodMode.setBalance(dss.dai, address(this), 100_000_000 * (10 ** dss.dai.decimals()));
        dss.dai.approve(address(proxyPsm), type(uint256).max);

        // keg to give unlimited USDC approval to the proxyPsm.
        vm.prank(keg);
        usdc.approve(address(proxyPsm), type(uint256).max);

        // Setup the vow for proxyPsm
        proxyPsm.file("vow", address(dss.vow));

        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(usdc), "USDC");
    }

    function testTo18ConversionFactor() public {
        assertEq(proxyPsm.__to18ConversionFactor(), 10 ** (18 - usdc.decimals()));
    }

    function testAuth() public {
        checkAuth(address(proxyPsm), "ProxyPsm");
    }

    function testFile() public {
        /*//////////////////////////////
                 tin & tout
        //////////////////////////////*/
        assertEq(proxyPsm.wards(address(this)), 1, "Invalid ward setting");

        vm.expectRevert("ProxyPsm/out-of-range");
        proxyPsm.file("tin", 2 * WAD);

        vm.expectRevert("ProxyPsm/out-of-range");
        proxyPsm.file("tout", 2 * WAD);

        checkFileUint(address(proxyPsm), "ProxyPsm", ["tin", "tout"]);

        /*//////////////////////////////
                    vow
        //////////////////////////////*/

        checkFileAddress(address(proxyPsm), "ProxyPsm", ["vow"]);
    }

    function testFill() public {
        /*//////////////////////////////
                  State Before
        //////////////////////////////*/
        uint256 pdaiBalance = dss.dai.balanceOf(address(proxyPsm));
        assertEq(pdaiBalance, 0, "fill: pdaiBalance is not zero");

        (uint256 pArt,,, uint256 pline,) = dss.vat.ilks(ilk);
        assertEq(pArt, 0, "fill: pArt is not zero");

        (uint256 part, uint256 pink) = dss.vat.urns(ilk, address(proxyPsm));
        assertEq(part, 0, "fill: part is not zero");
        assertEq(pink, 0, "fill: pink is not zero");

        uint256 pgem = dss.vat.gem(ilk, address(proxyPsm));
        assertEq(pgem, 0, "fill: pgem is not zero");

        ////////////////////////////////

        vm.expectEmit(false, false, false, true);
        emit Fill(pline / RAY);

        uint256 filled = proxyPsm.fill();

        /*//////////////////////////////
                  State After
        //////////////////////////////*/

        uint256 daiBalance = dss.dai.balanceOf(address(proxyPsm));
        assertEq(daiBalance, pdaiBalance + filled, "fill: daiBalance is invalid");

        (uint256 Art,,, uint256 line,) = dss.vat.ilks(ilk);
        assertEq(Art, pArt + filled, "fill: Art is invalid after fill");
        assertEq(Art * RAY, line, "fill: invalid Art after fill");

        (uint256 ink, uint256 art) = dss.vat.urns(ilk, address(proxyPsm));
        assertEq(ink, pink + filled, "fill: invalid unt.ink after fill");
        assertEq(art, part + filled, "fill: invalid urn.art after fill");

        uint256 gem = dss.vat.gem(ilk, address(proxyPsm));
        // Result of slip + frob should be zero.
        assertEq(gem, 0, "fill: gem is invalid after fill");
    }

    function testRevertFillWhenFull() public {
        proxyPsm.fill();

        vm.expectRevert("ProxyPsm/fill-unavailable");
        proxyPsm.fill();
    }

    function testFuzzFillWhenPartiallyFull(uint256 dline) public {
        proxyPsm.fill();
        (,,, uint256 iline,) = dss.vat.ilks(ilk);
        // Changes lower than RAY will have no effect because of the rounding error.
        dline = bound(dline, RAY, iline);
        _changeIlkLine(ilk, dline, true);

        (uint256 pArt,,, uint256 pline,) = dss.vat.ilks(ilk);
        assertLt(pArt * RAY, pline, "fill: invalid pArt before fill");

        vm.expectEmit(false, false, false, true);
        emit Fill((pline - pArt * RAY) / RAY);

        proxyPsm.fill();

        (uint256 Art,,, uint256 line,) = dss.vat.ilks(ilk);
        assertApproxEqAbs(Art * RAY, line, RAY, "fill: invalid Art after fill");
    }

    function testFuzzTrimWhenAboveLine(uint256 dline) public {
        proxyPsm.fill();
        (,,, uint256 iline,) = dss.vat.ilks(ilk);
        // Changes lower than RAY will have no effect because of the rounding error.
        dline = bound(dline, RAY, iline);
        _changeIlkLine(ilk, -_int256(dline), true);

        (uint256 pArt,,, uint256 pline,) = dss.vat.ilks(ilk);
        assertGt(pArt * RAY, pline, "trim: invalid pArt before trim");

        vm.expectEmit(false, false, false, true);
        emit Trim((pArt * RAY - pline) / RAY);

        proxyPsm.trim();

        (uint256 Art,,, uint256 line,) = dss.vat.ilks(ilk);
        assertApproxEqAbs(Art * RAY, line, RAY, "trim: invalid Art after trim");
    }

    function testFuzzRevertTrimWhenBelowOrAtLine(uint256 dline) public {
        proxyPsm.fill();
        (,,, uint256 iline,) = dss.vat.ilks(ilk);
        dline = bound(dline, 0, iline);
        _changeIlkLine(ilk, dline, true);

        vm.expectRevert("ProxyPsm/trim-unavailable");
        proxyPsm.trim();
    }

    function testSellGem() public {
        uint256 gemWad = 175_000 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());

        proxyPsm.fill();
        uint256 pdaiBalance = dss.dai.balanceOf(address(this));
        uint256 pusdcBalance = usdc.balanceOf(keg);

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);

        uint256 daiOutWad = proxyPsm.sellGem(address(this), gemAmt);

        uint256 daiBalance = dss.dai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(keg);

        assertEq(daiBalance, pdaiBalance + daiOutWad, "sellGem: invalid Dai balance change");
        assertEq(usdcBalance, pusdcBalance + gemAmt, "sellGem: invalid USDC balance change");
    }

    function testFuzzSellGem(uint256 gemAmt) public {
        gemAmt = bound(gemAmt, 1, usdc.balanceOf(address(this)));
        proxyPsm.fill();

        uint256 pdaiBalance = dss.dai.balanceOf(address(this));
        uint256 pusdcBalance = usdc.balanceOf(keg);

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), gemAmt, 0);

        uint256 daiOutWad = proxyPsm.sellGem(address(this), gemAmt);

        uint256 daiBalance = dss.dai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(keg);

        assertEq(daiBalance, pdaiBalance + daiOutWad, "sellGem: invalid Dai balance change");
        assertEq(usdcBalance, pusdcBalance + gemAmt, "sellGem: invalid USDC balance change");
    }

    function testSellGemShouldFillWhenPsmHasNoDai() public {
        (uint256 pArt,,, uint256 pline,) = dss.vat.ilks(ilk);
        assertEq(pArt, 0, "sellGem: invalid pArt before sellGem");

        vm.expectEmit(false, false, false, true);
        emit Fill(pline / RAY);

        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), 1, 0);

        proxyPsm.sellGem(address(this), 1);

        (uint256 Art,,, uint256 line,) = dss.vat.ilks(ilk);
        assertEq(Art * RAY, line, "sellGem: invalid Art Art sellGem");
    }

    function testBuyGem() public {
        uint256 gemWad = 175_000 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());

        proxyPsm.fill();
        assertEq(usdc.balanceOf(keg), 0, "buyGem: initial keg USDC balance not zero");
        proxyPsm.sellGem(address(this), gemAmt);
        assertEq(usdc.balanceOf(keg), gemAmt, "buyGem: invalid keg USDC balance");

        address usr = address(0xd34d);
        uint256 pusdcBalance = usdc.balanceOf(usr);
        assertEq(pusdcBalance, 0, "buyGem: invalid usr USDC balance before buyGem");

        vm.expectEmit(true, false, false, true);
        emit BuyGem(usr, gemAmt, 0);

        proxyPsm.buyGem(usr, gemAmt);

        uint256 usdcBalance = usdc.balanceOf(usr);

        assertEq(usdcBalance, pusdcBalance + gemAmt, "buyGem: invalid usr USDC balance after buyGem");
    }

    function testFuzzBuyGem(uint256 gemAmt) public {
        gemAmt = bound(gemAmt, 1, usdc.balanceOf(address(this)));

        proxyPsm.fill();
        assertEq(usdc.balanceOf(keg), 0, "buyGem: initial keg USDC balance not zero");
        proxyPsm.sellGem(address(this), gemAmt);
        assertEq(usdc.balanceOf(keg), gemAmt, "buyGem: invalid keg USDC balance");

        address usr = address(0xd34d);
        uint256 pusdcBalance = usdc.balanceOf(usr);
        assertEq(pusdcBalance, 0, "buyGem: invalid usr USDC balance before buyGem");

        vm.expectEmit(true, false, false, true);
        emit BuyGem(usr, gemAmt, 0);

        proxyPsm.buyGem(usr, gemAmt);

        uint256 usdcBalance = usdc.balanceOf(usr);

        assertEq(usdcBalance, pusdcBalance + gemAmt, "buyGem: invalid usr USDC balance after buyGem");
    }

    function testRevertBuyGemWhenKegHasNoGem() public {
        proxyPsm.fill();
        assertEq(usdc.balanceOf(keg), 0, "buyGem: initial keg USDC balance not zero");

        // Error from the USDC implementation
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        proxyPsm.buyGem(address(this), 1);
    }

    function testExit() public {
        address usr = address(0x1234);
        uint256 gemWad = 50 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());

        proxyPsm.sellGem(address(this), usdc.balanceOf(address(this)));
        // Mimick the state after Emergency Shutdown: users will having gems.
        dss.vat.slip(ilk, address(this), int256(gemWad));

        assertEq(dss.vat.gem(ilk, address(this)), gemWad, "exit: invalid vat.gem before exit");
        assertEq(usdc.balanceOf(usr), 0, "exit: invalid usdc balance before exit");

        proxyPsm.exit(usr, gemAmt);

        assertEq(dss.vat.gem(ilk, address(this)), 0, "exit: invalid vat.gem after exit");
        assertEq(usdc.balanceOf(usr), gemAmt, "exit: invalid usdc balance before exit");
    }

    function testFuzzAccumulatedFees(uint256 tin_, uint256 tout_) public {
        (uint256 tin, uint256 tout) = _setupFees(tin_, tout_);
        proxyPsm.fill();
        uint256 accFees;

        assertEq(proxyPsm.fees(), 0, "fees: invalid fees before swaps");

        uint256 gemWad = 50_000 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());

        uint256 expectedSellFee = gemWad * tin / WAD;
        uint256 daiWadOut = proxyPsm.sellGem(address(this), gemAmt);
        assertEq(gemWad - daiWadOut, expectedSellFee, "fees: invalid fee on sellGem");
        accFees += gemWad - daiWadOut;

        uint256 expectedBuyFee = gemWad * tout / WAD;
        uint256 daiWadIn = proxyPsm.buyGem(address(this), gemAmt);
        assertEq(daiWadIn - gemWad, expectedBuyFee, "fees: invalid fee on buyGem");
        accFees += daiWadIn - gemWad;

        assertEq(proxyPsm.fees(), accFees, "fees: invalid accumulated fees");
    }

    function testFuzzGulpAccumulatedFees(uint256 tin_, uint256 tout_) public {
        _setupFees(tin_, tout_);
        proxyPsm.fill();

        assertEq(proxyPsm.fees(), 0, "gulp: invalid fees before swaps");

        uint256 gemWad = 50_000 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());
        proxyPsm.sellGem(address(this), gemAmt);
        proxyPsm.buyGem(address(this), gemAmt);

        uint256 pvowDai = dss.vat.dai(address(dss.vow));
        uint256 pdaiBalance = dss.dai.balanceOf(address(proxyPsm));
        uint256 pfees = proxyPsm.fees();

        proxyPsm.gulp();

        uint256 vowDai = dss.vat.dai(address(dss.vow));
        uint256 daiBalance = dss.dai.balanceOf(address(proxyPsm));
        uint256 fees = proxyPsm.fees();

        assertEq(vowDai, pvowDai + (pfees * RAY), "gulp: invalid vat.dai(vow) change after gulp");
        assertEq(daiBalance, pdaiBalance - pfees, "gulp: invalid dai.balanceOf(proxyPsm) change after gulp");
        assertEq(fees, 0, "gulp: invalid fees after gulp");
    }

    function testRevertGulpWhenZeroAccumulatedFees() public {
        vm.expectRevert("ProxyPsm/gulp-unavailable");
        proxyPsm.gulp();
    }

    function testRevertGulpWhenVowIsAddressZero() public {
        _setupFees(0.001 ether, 0.001 ether);
        proxyPsm.fill();
        // Simulate vow being set to `address(0)`
        proxyPsm.file("vow", address(0));

        uint256 gemWad = 50_000 * WAD;
        uint256 gemAmt = gemWad / 10 ** (18 - usdc.decimals());
        proxyPsm.sellGem(address(this), gemAmt);
        proxyPsm.buyGem(address(this), gemAmt);

        vm.expectRevert("ProxyPsm/gulp-without-vow");
        proxyPsm.gulp();
    }

    function _setupFees(uint256 tin_, uint256 tout_) internal returns (uint256 tin, uint256 tout) {
        tin = bound(tin_, 0.00001 ether, 1 * WAD); // Between 0.001% and 100%
        tout = bound(tout_, 0.00001 ether, 1 * WAD); // Between 0.001% and 100%

        proxyPsm.file("tin", tin);
        proxyPsm.file("tout", tout);
    }

    function _changeIlkLine(bytes32 ilk_, uint256 dline, bool global) internal returns (uint256) {
        return _changeIlkLine(ilk_, _int256(dline), global);
    }

    function _changeIlkLine(bytes32 ilk_, int256 dline, bool global) internal returns (uint256) {
        (,,, uint256 line,) = dss.vat.ilks(ilk_);
        uint256 lineNew = dline > 0 ? line + uint256(dline) : line - uint256(-dline);
        dss.vat.file(ilk_, "line", lineNew);

        if (global) {
            uint256 Line = dss.vat.Line();
            uint256 LineNew = dline > 0 ? Line + uint256(dline) : Line - uint256(-dline);
            dss.vat.file("Line", LineNew);
        }

        return lineNew;
    }

    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, "Unsafe cast to int256");
    }

    event Fill(uint256 wad);
    event Trim(uint256 wad);
    event SellGem(address indexed owner, uint256 amt, uint256 fee);
    event BuyGem(address indexed owner, uint256 amt, uint256 fee);
}
