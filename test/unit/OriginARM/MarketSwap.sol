// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {MockMarketSwapTarget} from "test/unit/mocks/MockMarketSwapTarget.sol";

contract Unit_Concrete_OriginARM_MarketSwap_Test_ is Unit_Shared_Test {
    MockMarketSwapTarget internal target;

    function setUp() public override {
        super.setUp();
        target = new MockMarketSwapTarget();
    }

    function test_RevertWhen_MarketSwap_Because_NotOperator() public asGovernor {
        vm.expectRevert("ARM: Only operator can call this function.");
        originARM.marketSwap(oeth, weth, 1 ether, address(target), "");
    }

    function test_RevertWhen_MarketSwap_Because_InvalidTarget() public asOperator {
        vm.expectRevert("ARM: invalid target");
        originARM.marketSwap(oeth, weth, 1 ether, address(0), "");
    }

    function test_RevertWhen_MarketSwap_Because_InvalidTokenPair() public asOperator {
        vm.expectRevert("ARM: invalid token pair");
        originARM.marketSwap(badToken, weth, 1 ether, address(target), "");
    }

    function test_RevertWhen_MarketSwap_Because_CallbackFailed() public asOperator {
        deal(address(weth), address(originARM), 1 ether);
        bytes memory data = abi.encodeWithSelector(MockMarketSwapTarget.revertSwap.selector);

        vm.expectRevert("ARM: market swap failed");
        originARM.marketSwap(oeth, weth, 1 ether, address(target), data);
    }

    function test_RevertWhen_MarketSwap_Because_InsufficientReturnedAmount() public asOperator {
        uint256 amountOut = 100 ether;
        uint256 amountIn = amountOut - 1;
        bytes memory data = _fundTargetAndEncode(oeth, amountIn);
        deal(address(weth), address(originARM), amountOut);

        vm.expectRevert("ARM: market swap return low");
        originARM.marketSwap(oeth, weth, amountOut, address(target), data);
    }

    function test_RevertWhen_MarketSwap_Because_InsufficientLiquidityDueToRedeemRequest() public {
        uint256 depositAmount = 10 ether;
        deal(address(weth), alice, depositAmount);
        vm.startPrank(alice);
        weth.approve(address(originARM), depositAmount);
        originARM.deposit(depositAmount);
        uint256 shares = originARM.balanceOf(alice);
        originARM.requestRedeem(shares);
        vm.stopPrank();

        uint256 amountOut = MIN_TOTAL_SUPPLY + 1;
        bytes memory data = _fundTargetAndEncode(oeth, amountOut);

        vm.expectRevert("ARM: Insufficient liquidity");
        vm.prank(operator);
        originARM.marketSwap(oeth, weth, amountOut, address(target), data);
    }

    function test_MarketSwap_WethOut_OethIn() public asOperator {
        uint256 amountOut = 1 ether;
        deal(address(weth), address(originARM), weth.balanceOf(address(originARM)) + amountOut);
        bytes memory data = _fundTargetAndEncode(oeth, amountOut);

        uint256 armWethBefore = weth.balanceOf(address(originARM));
        uint256 armOethBefore = oeth.balanceOf(address(originARM));

        vm.expectEmit(address(originARM));
        emit AbstractARM.MarketSwap(address(target), address(oeth), address(weth), amountOut, amountOut);

        uint256 amountIn = originARM.marketSwap(oeth, weth, amountOut, address(target), data);

        assertEq(amountIn, amountOut, "wrong amount in");
        assertEq(weth.balanceOf(address(originARM)), armWethBefore - amountOut, "wrong ARM WETH balance");
        assertEq(oeth.balanceOf(address(originARM)), armOethBefore + amountOut, "wrong ARM OETH balance");
        assertEq(weth.balanceOf(address(target)), amountOut, "wrong target WETH balance");
    }

    function test_MarketSwap_OethOut_WethIn() public asOperator {
        uint256 amountOut = 1 ether;
        deal(address(oeth), address(originARM), amountOut);
        bytes memory data = _fundTargetAndEncode(weth, amountOut);

        uint256 armWethBefore = weth.balanceOf(address(originARM));
        uint256 armOethBefore = oeth.balanceOf(address(originARM));

        uint256 amountIn = originARM.marketSwap(weth, oeth, amountOut, address(target), data);

        assertEq(amountIn, amountOut, "wrong amount in");
        assertEq(weth.balanceOf(address(originARM)), armWethBefore + amountOut, "wrong ARM WETH balance");
        assertEq(oeth.balanceOf(address(originARM)), armOethBefore - amountOut, "wrong ARM OETH balance");
        assertEq(oeth.balanceOf(address(target)), amountOut, "wrong target OETH balance");
    }

    function test_MarketSwap_PassesAtExactThreshold_25() public {
        _assertSwapAtExactThreshold(25, true);
    }

    function test_MarketSwap_PassesAtExactThreshold_250() public {
        _assertSwapAtExactThreshold(250, true);
    }

    function test_MarketSwap_PassesAtExactThreshold_1000() public {
        _assertSwapAtExactThreshold(1000, true);
    }

    function test_MarketSwap_PassesAtExactThreshold_When_LiquidityIn() public {
        _assertSwapAtExactThreshold(250, false);
    }

    function test_RevertWhen_SetAllowedMarketSwapDeviation_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setAllowedMarketSwapDeviation(1);
    }

    function test_RevertWhen_SetAllowedMarketSwapDeviation_Because_TooHigh() public asGovernor {
        uint256 tooHigh = originARM.MAX_ALLOWED_MARKET_SWAP_DEVIATION() + 1;
        vm.expectRevert("ARM: swap dev too high");
        originARM.setAllowedMarketSwapDeviation(tooHigh);
    }

    function test_SetAllowedMarketSwapDeviation() public asGovernor {
        uint256 newDeviation = 250;

        vm.expectEmit(address(originARM));
        emit AbstractARM.AllowedMarketSwapDeviationUpdated(newDeviation);

        originARM.setAllowedMarketSwapDeviation(newDeviation);

        assertEq(originARM.allowedMarketSwapDeviation(), newDeviation, "wrong market swap deviation");
    }

    function _assertSwapAtExactThreshold(uint256 deviation, bool isBuyBase) internal {
        uint256 amountOut = 100 ether;
        uint256 expectedAmountIn = amountOut;
        uint256 minAmountIn = isBuyBase
            ? expectedAmountIn * (originARM.MARKET_SWAP_DEVIATION_SCALE() + deviation)
                / originARM.MARKET_SWAP_DEVIATION_SCALE()
            : expectedAmountIn * (originARM.MARKET_SWAP_DEVIATION_SCALE() - deviation)
                / originARM.MARKET_SWAP_DEVIATION_SCALE();

        vm.startPrank(governor);
        originARM.setAllowedMarketSwapDeviation(deviation);
        vm.stopPrank();

        IERC20 tokenIn = isBuyBase ? oeth : weth;
        IERC20 tokenOut = isBuyBase ? weth : oeth;

        deal(address(tokenOut), address(originARM), amountOut);
        bytes memory data = _fundTargetAndEncode(tokenIn, minAmountIn);

        vm.prank(operator);
        uint256 amountIn = originARM.marketSwap(tokenIn, tokenOut, amountOut, address(target), data);

        assertEq(amountIn, minAmountIn, "wrong threshold amount in");
    }

    function _fundTargetAndEncode(IERC20 tokenIn, uint256 amountIn) internal returns (bytes memory data) {
        deal(address(tokenIn), address(target), amountIn);
        data = abi.encodeWithSelector(MockMarketSwapTarget.executeSwap.selector, address(tokenIn), address(originARM), amountIn);
    }
}
