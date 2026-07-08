// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AbstractSmokeTest} from "./AbstractSmokeTest.sol";

import {IERC20, IERC4626} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {Proxy} from "contracts/Proxy.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

/// @dev Minimal view of the deployed (pre-upgrade, single-asset) ARM. `token0` is the liquidity asset
///      (WETH) and `token1` the base asset (stETH); both trade rates are 1e36-scaled. The deployed
///      implementation tracks the withdrawal queue with `withdrawsQueued`/`withdrawsClaimed` rather than
///      exposing `reservedWithdrawLiquidity()`.
interface ILegacyARM {
    function traderate0() external view returns (uint256);
    function traderate1() external view returns (uint256);
    function withdrawsQueued() external view returns (uint256);
    function withdrawsClaimed() external view returns (uint256);
}

/// @notice Smoke test for the **deployed** Lido ARM, which keeps its single-asset implementation: the
///         multi-asset / swap-fee upgrade is intentionally NOT applied (see AbstractSmokeTest). It therefore
///         exercises the legacy interface only — no base-asset configs, adapters or per-asset prices — and
///         swaps at the live trade rates rather than setting them.
contract Fork_LidoARM_Smoke_Test is AbstractSmokeTest {
    IERC20 weth;
    IERC20 steth;
    Proxy proxy;
    LidoARM lidoARM;
    CapManager capManager;
    IERC4626 morphoMarket;
    address operator;

    function setUp() public override {
        super.setUp();
        weth = IERC20(Mainnet.WETH);
        steth = IERC20(Mainnet.STETH);
        operator = Mainnet.ARM_TALOS_RELAYER;

        vm.label(address(weth), "WETH");
        vm.label(address(steth), "stETH");
        vm.label(address(operator), "OPERATOR");

        proxy = Proxy(payable(resolver.resolve("LIDO_ARM")));
        lidoARM = LidoARM(payable(resolver.resolve("LIDO_ARM")));
        capManager = CapManager(resolver.resolve("LIDO_ARM_CAP_MAN"));
        morphoMarket = IERC4626(resolver.resolve("MORPHO_MARKET_LIDO"));
    }

    function test_initialConfig() external view {
        assertEq(lidoARM.name(), "Lido ARM", "Name");
        assertEq(lidoARM.symbol(), "ARM-WETH-stETH", "Symbol");
        assertEq(lidoARM.owner(), Mainnet.TIMELOCK, "Owner");
        assertEq(lidoARM.operator(), Mainnet.ARM_TALOS_RELAYER, "Operator");
        assertEq(lidoARM.feeCollector(), Mainnet.BUYBACK_OPERATOR, "Fee collector");
        assertEq((100 * uint256(lidoARM.fee())) / FEE_SCALE, 20, "Performance fee as a percentage");
        assertEq(lidoARM.liquidityAsset(), Mainnet.WETH, "liquidity asset");
        assertEq(lidoARM.asset(), Mainnet.WETH, "ERC-4626 asset");
        assertEq(lidoARM.claimDelay(), 10 minutes, "claim delay");

        assertEq(capManager.accountCapEnabled(), false, "account cap enabled");
        assertEq(capManager.arm(), address(lidoARM), "arm");
    }

    function test_swap_exact_steth_for_weth() external {
        // Trader sells stETH and buys WETH (the ARM buys stETH).
        _swapExactTokensForTokens(steth, weth, 100 ether);
        _swapExactTokensForTokens(steth, weth, 1e15);
        _swapExactTokensForTokens(steth, weth, 1 ether);
    }

    function test_swap_exact_weth_for_steth() external {
        // Trader buys stETH and sells WETH (the ARM sells stETH).
        _swapExactTokensForTokens(weth, steth, 10 ether);
        _swapExactTokensForTokens(weth, steth, 100 ether);
    }

    function test_swapTokensForExactTokens() external {
        _swapTokensForExactTokens(steth, weth, 10 ether);
        _swapTokensForExactTokens(steth, weth, 100 ether);
        _swapTokensForExactTokens(weth, steth, 10 ether);
    }

    /// @dev Live 1e36 rate the ARM applies when `inToken` is sold into it.
    function _rate(IERC20 inToken) internal view returns (uint256) {
        return inToken == weth ? ILegacyARM(address(lidoARM)).traderate0() : ILegacyARM(address(lidoARM)).traderate1();
    }

    /// @dev WETH reserved for outstanding LP withdrawals (the deployed impl has no reservedWithdrawLiquidity()).
    function _outstandingWithdrawals() internal view returns (uint256) {
        return ILegacyARM(address(lidoARM)).withdrawsQueued() - ILegacyARM(address(lidoARM)).withdrawsClaimed();
    }

    /// @dev Fund the ARM with the output token and the trader (this) with the input token.
    function _fundForSwap(IERC20 outToken) internal {
        if (outToken == weth) {
            deal(address(weth), address(lidoARM), 1_000_000 ether);
            _dealStETH(address(this), 1000 ether);
        } else {
            _dealStETH(address(lidoARM), 1000 ether);
            deal(address(weth), address(this), 1_000_000 ether);
        }
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn) internal {
        _fundForSwap(outToken);
        uint256 expectedOut = amountIn * _rate(inToken) / 1e36;

        inToken.approve(address(lidoARM), amountIn);
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        lidoARM.swapExactTokensForTokens(inToken, outToken, amountIn, 0, address(this));

        assertApproxEqAbs(inToken.balanceOf(address(this)), startIn - amountIn, 2, "In actual");
        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + expectedOut, 2, "Out actual");
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut) internal {
        _fundForSwap(outToken);
        uint256 expectedIn = amountOut * 1e36 / _rate(inToken);

        inToken.approve(address(lidoARM), expectedIn + 1e16);
        uint256 startIn = inToken.balanceOf(address(this));
        uint256 startOut = outToken.balanceOf(address(this));

        lidoARM.swapTokensForExactTokens(inToken, outToken, amountOut, expectedIn + 1e16, address(this));

        assertApproxEqAbs(outToken.balanceOf(address(this)), startOut + amountOut, 2, "Out actual");
        assertApproxEqRel(startIn - inToken.balanceOf(address(this)), expectedIn, 1e14, "In actual");
    }

    function test_proxy_unauthorizedAccess() external {
        address RANDOM_ADDRESS = 0xfEEDBeef00000000000000000000000000000000;
        vm.startPrank(RANDOM_ADDRESS);

        // Proxy's restricted methods (the deployed proxy is not upgraded).
        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.setOwner(RANDOM_ADDRESS);

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.initialize(address(this), address(this), "");

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeTo(address(this));

        vm.expectRevert("OSwap: Only owner can call this function.");
        proxy.upgradeToAndCall(address(this), "");

        // Implementation's restricted method.
        vm.expectRevert();
        lidoARM.setOwner(RANDOM_ADDRESS);
    }

    // TODO replace _dealStETH with just deal
    function _dealStETH(address to, uint256 amount) internal {
        vm.prank(0xEB9c1CE881F0bDB25EAc4D74FccbAcF4Dd81020a);
        steth.transfer(to, amount + 2);
    }

    /* Operator Tests */

    function test_setOperator() external {
        vm.prank(Mainnet.TIMELOCK);
        lidoARM.setOperator(address(this));
        assertEq(lidoARM.operator(), address(this));
    }

    function test_nonOwnerCannotSetOperator() external {
        vm.expectRevert();
        vm.prank(operator);
        lidoARM.setOperator(operator);
    }

    /* Lending Market Allocation Tests */

    function test_allocate_to_lending_market() external {
        // Add and set the active market to the Morpho market
        vm.startPrank(Mainnet.TIMELOCK);
        if (!lidoARM.supportedMarkets(address(morphoMarket))) {
            address[] memory markets = new address[](1);
            markets[0] = address(morphoMarket);
            lidoARM.addMarkets(markets);
        }
        lidoARM.setActiveMarket(address(morphoMarket));
        vm.stopPrank();

        // Deal enough WETH to cover the outstanding withdrawal queue plus extra to deposit
        uint256 outstandingWithdrawals = _outstandingWithdrawals();
        deal(address(weth), address(lidoARM), outstandingWithdrawals + 100 ether);

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 marketBalanceBefore = morphoMarket.maxWithdraw(address(lidoARM));

        // Set buffer to 0% so all liquidity goes to the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        lidoARM.setARMBuffer(0);

        // Allocate liquidity to the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (, int256 actualDelta) = lidoARM.allocate();

        uint256 armWethAfter = weth.balanceOf(address(lidoARM));
        uint256 marketBalanceAfter = morphoMarket.maxWithdraw(address(lidoARM));

        // Verify liquidity moved to the lending market
        assertGt(actualDelta, 0, "Actual delta should be positive (deposited to market)");
        assertLt(armWethAfter, armWethBefore, "ARM WETH balance should decrease");
        assertGt(marketBalanceAfter, marketBalanceBefore, "Market balance should increase");
    }

    function test_allocate_from_lending_market() external {
        // Add and set the active market to the Morpho market
        vm.startPrank(Mainnet.TIMELOCK);
        if (!lidoARM.supportedMarkets(address(morphoMarket))) {
            address[] memory markets = new address[](1);
            markets[0] = address(morphoMarket);
            lidoARM.addMarkets(markets);
        }
        lidoARM.setActiveMarket(address(morphoMarket));
        vm.stopPrank();

        // Deal enough WETH to cover the outstanding withdrawal queue plus extra to deposit
        uint256 outstandingWithdrawals = _outstandingWithdrawals();
        deal(address(weth), address(lidoARM), outstandingWithdrawals + 100 ether);
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        lidoARM.setARMBuffer(0);
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        lidoARM.allocate();

        uint256 armWethBefore = weth.balanceOf(address(lidoARM));
        uint256 marketBalanceBefore = morphoMarket.maxWithdraw(address(lidoARM));

        // Set buffer to 100% so liquidity comes back from the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        lidoARM.setARMBuffer(1e18);

        // Allocate liquidity from the lending market
        vm.prank(Mainnet.ARM_TALOS_RELAYER);
        (, int256 actualDelta) = lidoARM.allocate();

        uint256 armWethAfter = weth.balanceOf(address(lidoARM));
        uint256 marketBalanceAfter = morphoMarket.maxWithdraw(address(lidoARM));

        // Verify liquidity moved from the lending market (as much as available)
        assertLt(actualDelta, 0, "Actual delta should be negative (withdrawn from market)");
        assertGt(armWethAfter, armWethBefore, "ARM WETH balance should increase");
        assertLe(marketBalanceAfter, marketBalanceBefore, "Market balance should decrease or stay same");
    }
}
