// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Unit_Concrete_OriginARM_SwapLiquidityFromMarket_Test_ is Unit_Shared_Test {
    function test_SwapExactTokensForTokens_WithMarketShortfall_WithdrawsExactShortfall()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountIn = DEFAULT_AMOUNT / 2;
        uint256 expectedAmountOut = amountIn * _buyPrice() / 1e36;
        vm.prank(operator);
        originARM.setPrices(address(oeth), 992 * 1e33, 1001 * 1e33, expectedAmountOut, type(uint128).max);

        deal(address(oeth), swapper, amountIn);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), amountIn);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, amountIn, expectedAmountOut, swapper);

        vm.stopPrank();

        assertEq(amounts[0], amountIn, "input amount");
        assertEq(amounts[1], expectedAmountOut, "output amount");
        assertEq(weth.balanceOf(address(originARM)), 0, "no extra WETH should stay in ARM");
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - expectedAmountOut, "market shortfall only");
        assertEq(_buyLiquidityRemaining(), 0, "buy cap not consumed");
    }

    function test_SwapTokensForExactTokens_WithMarketShortfall_WithdrawsExactShortfall()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        vm.prank(operator);
        originARM.setPrices(address(oeth), 992 * 1e33, 1001 * 1e33, amountOut, type(uint128).max);

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        uint256[] memory amounts = originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();

        assertEq(amounts[1], amountOut, "exact output");
        assertEq(weth.balanceOf(address(originARM)), 0, "no extra WETH should stay in ARM");
        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore - amountOut, "market shortfall only");
        assertEq(_buyLiquidityRemaining(), 0, "buy cap not consumed");
    }

    function test_SwapWithdrawFromMarket_PreservesQueuedRedeemLiquidity()
        public
        deposit(alice, 4 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        uint256 sharesToRedeem = originARM.balanceOf(alice) / 4;
        vm.prank(alice);
        (, uint256 queuedAssets) = originARM.requestRedeem(sharesToRedeem);

        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        deal(address(oeth), swapper, DEFAULT_AMOUNT);

        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);
        vm.stopPrank();

        assertEq(originARM.reservedWithdrawLiquidity(), queuedAssets, "reserved amount tracked");
        assertEq(weth.balanceOf(address(originARM)), queuedAssets, "queued redeem liquidity remains in ARM");
    }

    function test_RevertWhen_SwapNeedsMarketLiquidity_ButNoActiveMarket() public {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT;

        deal(address(oeth), swapper, DEFAULT_AMOUNT * 2);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();
    }

    function test_RevertWhen_SwapNeedsMoreLiquidityThanMarketCanProvide()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.mockCallRevert(
            address(market),
            abi.encodeWithSelector(IERC4626.withdraw.selector, amountOut, address(originARM), address(originARM)),
            bytes("mock market withdraw failure")
        );

        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        vm.expectRevert("ARM: Insufficient liquidity");
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();
    }

    function test_SwapWithEnoughOnHandLiquidity_DoesNotTouchMarket()
        public
        deposit(alice, DEFAULT_AMOUNT)
        setARMBuffer(1 ether)
        addMarket(address(market))
        setActiveMarket(address(market))
    {
        address swapper = makeAddr("local liquidity swapper");
        uint256 amountOut = DEFAULT_AMOUNT / 2;

        deal(address(oeth), swapper, DEFAULT_AMOUNT);
        vm.startPrank(swapper);
        oeth.approve(address(originARM), type(uint256).max);

        uint256 marketBalanceBefore = market.balanceOf(address(originARM));
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, swapper);

        vm.stopPrank();

        assertEq(market.balanceOf(address(originARM)), marketBalanceBefore, "market balance should not change");
    }

    function test_SwapExactTokensForTokens_ConsumesBuyLimitBeforeMarketWithdraw()
        public
        deposit(alice, 2 * DEFAULT_AMOUNT)
    {
        ReentrantSwapMarket reentrantMarket = new ReentrantSwapMarket(weth, originARM, oeth);
        uint256 amountIn = DEFAULT_AMOUNT / 2;
        uint256 amountOut = amountIn * 999e33 / 1e36;

        vm.prank(governor);
        originARM.setARMBuffer(0);

        address[] memory markets = new address[](1);
        markets[0] = address(reentrantMarket);
        vm.prank(governor);
        originARM.addMarkets(markets);

        vm.prank(governor);
        originARM.setActiveMarket(address(reentrantMarket));

        vm.prank(operator);
        originARM.setPrices(address(oeth), 999e33, 1001 * 1e33, amountOut, type(uint128).max);

        deal(address(weth), address(reentrantMarket), amountOut);
        deal(address(oeth), address(reentrantMarket), amountIn);
        reentrantMarket.setReentrantSwap(amountIn);

        address swapper = makeAddr("reentrant market swapper");
        deal(address(oeth), swapper, amountIn);

        vm.startPrank(swapper);
        oeth.approve(address(originARM), amountIn);
        uint256[] memory amounts = originARM.swapExactTokensForTokens(oeth, weth, amountIn, amountOut, swapper);
        vm.stopPrank();

        assertEq(amounts[1], amountOut, "output amount");
        assertTrue(reentrantMarket.reentryFailed(), "reentrant swap should fail");
        assertEq(_buyLiquidityRemaining(), 0, "buy cap not consumed");
    }
}

contract ReentrantSwapMarket {
    IERC20 public immutable liquidityAsset;
    OriginARM public immutable originARM;
    IERC20 public immutable baseAsset;

    uint256 public reentrantAmountIn;
    bool public reentryAttempted;
    bool public reentryFailed;

    constructor(IERC20 _liquidityAsset, OriginARM _originARM, IERC20 _baseAsset) {
        liquidityAsset = _liquidityAsset;
        originARM = _originARM;
        baseAsset = _baseAsset;
    }

    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    function setReentrantSwap(uint256 amountIn) external {
        reentrantAmountIn = amountIn;
        baseAsset.approve(address(originARM), type(uint256).max);
    }

    function withdraw(uint256 assets, address receiver, address) external returns (uint256 shares) {
        _withdraw(assets, receiver);
        return assets;
    }

    function deposit(uint256 assets, address) external returns (uint256 shares) {
        liquidityAsset.transferFrom(msg.sender, address(this), assets);
        return assets;
    }

    function redeem(uint256 shares, address receiver, address) external returns (uint256 assets) {
        _withdraw(shares, receiver);
        return shares;
    }

    function _withdraw(uint256 assets, address receiver) internal {
        if (!reentryAttempted) {
            reentryAttempted = true;
            try originARM.swapExactTokensForTokens(baseAsset, liquidityAsset, reentrantAmountIn, 0, address(this)) {}
            catch {
                reentryFailed = true;
            }
        }

        liquidityAsset.transfer(receiver, assets);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return liquidityAsset.balanceOf(address(this));
    }

    function maxRedeem(address) external view returns (uint256) {
        return liquidityAsset.balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function balanceOf(address) external view returns (uint256) {
        return liquidityAsset.balanceOf(address(this));
    }
}
