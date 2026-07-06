// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20, IERC4626} from "contracts/Interfaces.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @dev Minimal view of the deployed (pre-upgrade, single-asset) ARM. `token0` is the liquidity asset
///      (WETH) and `token1` the base asset (eETH); both trade rates are 1e36-scaled.
interface ILegacyARM {
    function traderate0() external view returns (uint256);
    function traderate1() external view returns (uint256);
}

/// @notice Smoke test for the **deployed** Ether.fi ARM, which keeps its single-asset implementation: the
///         multi-asset / swap-fee upgrade is intentionally NOT applied (see AbstractSmokeTest). It therefore
///         exercises the legacy interface only — no base-asset configs, adapters or per-asset prices — and
///         swaps at the live trade rates rather than setting them.
contract Fork_EtherFiARM_Smoke_Test is AbstractSmokeTest {
    IERC20 weth;
    IERC20 eeth;
    Proxy armProxy;
    EtherFiARM etherFiARM;
    CapManager capManager;
    IERC4626 morphoMarket;
    address operator;

    function setUp() public override {
        super.setUp();
        weth = IERC20(Mainnet.WETH);
        eeth = IERC20(Mainnet.EETH);
        operator = Mainnet.ARM_TALOS_RELAYER;

        vm.label(address(weth), "WETH");
        vm.label(address(eeth), "eETH");
        vm.label(address(operator), "OPERATOR");

        armProxy = Proxy(payable(resolver.resolve("ETHER_FI_ARM")));
        etherFiARM = EtherFiARM(payable(resolver.resolve("ETHER_FI_ARM")));
        capManager = CapManager(resolver.resolve("ETHER_FI_ARM_CAP_MAN"));
        morphoMarket = IERC4626(resolver.resolve("MORPHO_MARKET_ETHERFI"));

        vm.prank(etherFiARM.owner());
        etherFiARM.setOwner(Mainnet.TIMELOCK);
    }

    function test_initialConfig() external view {
        assertEq(etherFiARM.name(), "Ether.fi ARM", "Name");
        assertEq(etherFiARM.symbol(), "ARM-WETH-eETH", "Symbol");
        assertEq(etherFiARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(etherFiARM.operator(), Mainnet.ARM_TALOS_RELAYER, "Operator");
        assertEq(etherFiARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq((100 * uint256(etherFiARM.fee())) / FEE_SCALE, 20, "Performance fee as a percentage");
        assertEq(etherFiARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(etherFiARM.asset(), Mainnet.WETH, "ERC-4626 asset");
        assertEq(etherFiARM.claimDelay(), 10 minutes, "claim delay");

        assertEq(capManager.accountCapEnabled(), true, "account cap enabled");
        assertEq(capManager.totalAssetsCap(), 1000 ether, "total assets cap");
        assertEq(capManager.liquidityProviderCaps(Mainnet.TREASURY_LP), 150 ether, "liquidity provider cap");
        assertEq(capManager.operator(), Mainnet.ARM_RELAYER, "Operator");
        assertEq(capManager.arm(), address(etherFiARM), "arm");
    }

    function test_swap_exact_eeth_for_weth() external {
        // Trader sells eETH and buys WETH (the ARM buys eETH).
        _swapExactTokensForTokens(eeth, weth, 100 ether);
        _swapExactTokensForTokens(eeth, weth, 1e15);
        _swapExactTokensForTokens(eeth, weth, 1 ether);
    }

    function test_swap_exact_weth_for_eeth() external {
        // Trader buys eETH and sells WETH (the ARM sells eETH).
        _swapExactTokensForTokens(weth, eeth, 10 ether);
        _swapExactTokensForTokens(weth, eeth, 100 ether);
    }

    function test_swapTokensForExactTokens() external {
        _swapTokensForExactTokens(eeth, weth, 10 ether);
        _swapTokensForExactTokens(eeth, weth, 100 ether);
        _swapTokensForExactTokens(weth, eeth, 10 ether);
    }

    /// @dev Live 1e36 rate the ARM applies when `inToken` is sold into it.
    function _rate(IERC20 inToken) internal view returns (uint256) {
        return
            inToken == weth
                ? ILegacyARM(address(etherFiARM)).traderate0()
                : ILegacyARM(address(etherFiARM)).traderate1();
    }

    /// @dev Fund the ARM with the output token and the trader (this) with the input token.
    function _fundForSwap(IERC20 outToken) internal {
        if (outToken == weth) {
            deal(address(weth), address(etherFiARM), 1_000_000 ether);
            _dealEETH(address(this), 1000 ether);
        } else {
            _dealEETH(address(etherFiARM), 1000 ether);
            deal(address(weth), address(this), 1_000_000 ether);
        }
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn) internal {
        _fundForSwap(outToken);
        uint256 expectedOut = amountIn * _rate(inToken) / 1e36;

        inToken.approve(address(etherFiARM), amountIn);
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        etherFiARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut) internal {
        _fundForSwap(outToken);
        uint256 expectedIn = amountOut * 1e36 / _rate(inToken);

        inToken.approve(address(etherFiARM), expectedIn + 1e16);
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        etherFiARM.swapTokensForExactTokens(inToken, outToken, amountOut, expectedIn + 1e16, address(this));

        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 2, "Out actual");
        assertApproxEqRel(startIn - inToken.balanceOf(address(this)), expectedIn, 1e14, "In actual");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods (the deployed proxy is not upgraded).
        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.initialize(address(this), address(this), "");

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.upgradeTo(address(this));

        vm.expectRevert("ARM: Only owner can call this function.");
        armProxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted method.
        vm.expectRevert();
        etherFiARM.setOwner(RANDOM_ADDRESS);
    }

    // TODO replace _dealEETH with just deal
    function _dealEETH(address to, uint256 amount) internal {
        vm.prank(0x22162DbBa43fE0477cdC5234E248264eC7C6EA7c);
        eeth.transfer(to, amount + 2);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        etherFiARM.setOperator(address(this));
        assertEq(etherFiARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert();
        vm.prank(operator);
        etherFiARM.setOperator(operator);
    }

    /* Lending Market Allocation Tests */

    function test_allocate_to_lending_market() external {
        // Add and set the active market to the Morpho market
        vm.startPrank(Mainnet.TIMELOCK);
        if (!etherFiARM.supportedMarkets(address(morphoMarket))) {
            address[] memory markets = new address[](1);
            markets[0] = address(morphoMarket);
            etherFiARM.addMarkets(markets);
        }
        etherFiARM.setActiveMarket(address(morphoMarket));
        vm.stopPrank();

        // Deal WETH to the ARM
        deal(address(weth), address(etherFiARM), 100 ether);

        uint256 armWethBefore = weth.balanceOf(address(etherFiARM));
        uint256 marketBalanceBefore = morphoMarket.maxWithdraw(address(etherFiARM));

        // Set buffer to 0% so all liquidity goes to the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        etherFiARM.setARMBuffer(0);

        // Allocate liquidity to the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (, int256 actualDelta) = etherFiARM.allocate();

        uint256 armWethAfter = weth.balanceOf(address(etherFiARM));
        uint256 marketBalanceAfter = morphoMarket.maxWithdraw(address(etherFiARM));

        // Verify liquidity moved to the lending market
        assertGt(actualDelta, 0, "Actual delta should be positive (deposited to market)");
        assertLt(armWethAfter, armWethBefore, "ARM WETH balance should decrease");
        assertGt(marketBalanceAfter, marketBalanceBefore, "Market balance should increase");
    }

    function test_allocate_from_lending_market() external {
        // Add and set the active market to the Morpho market
        vm.startPrank(Mainnet.TIMELOCK);
        if (!etherFiARM.supportedMarkets(address(morphoMarket))) {
            address[] memory markets = new address[](1);
            markets[0] = address(morphoMarket);
            etherFiARM.addMarkets(markets);
        }
        etherFiARM.setActiveMarket(address(morphoMarket));
        vm.stopPrank();

        // Deal WETH to the ARM and allocate to market with buffer at 0%
        deal(address(weth), address(etherFiARM), 100 ether);
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        etherFiARM.setARMBuffer(0);
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        etherFiARM.allocate();

        uint256 armWethBefore = weth.balanceOf(address(etherFiARM));
        uint256 marketBalanceBefore = morphoMarket.maxWithdraw(address(etherFiARM));

        // Set buffer to 100% so liquidity comes back from the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        etherFiARM.setARMBuffer(1e18);

        // Allocate liquidity from the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (, int256 actualDelta) = etherFiARM.allocate();

        uint256 armWethAfter = weth.balanceOf(address(etherFiARM));
        uint256 marketBalanceAfter = morphoMarket.maxWithdraw(address(etherFiARM));

        // Verify liquidity moved from the lending market (as much as available)
        assertLt(actualDelta, 0, "Actual delta should be negative (withdrawn from market)");
        assertGt(armWethAfter, armWethBefore, "ARM WETH balance should increase");
        assertLe(marketBalanceAfter, marketBalanceBefore, "Market balance should decrease or stay same");
    }
}
