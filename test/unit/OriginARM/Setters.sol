// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Unit_Concrete_OriginARM_Setters_Test_ is Unit_Shared_Test {
    ////////////////////////////////////////////////////
    /// --- REVERT
    ////////////////////////////////////////////////////
    function test_RevertWhen_SetFeeCollector_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_SetFeeCollector_Because_FeeCollectorIsZero() public asGovernor {
        vm.expectRevert("ARM: invalid fee collector");
        originARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_SetFee_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setFee(0);
    }

    function test_RevertWhen_SetFee_Because_FeeIsTooHigh() public asGovernor {
        vm.expectRevert("ARM: fee too high");
        originARM.setFee(FEE_SCALE / 2 + 1);
    }

    function test_RevertWhen_SetCapManager_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setCapManager(address(0));
    }

    function test_RevertWhen_SetARMBuffer_Because_NotGovernorNorOperator() public asRandomCaller {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        originARM.setARMBuffer(0);
    }

    function test_RevertWhen_SetARMBuffer_Because_Above1e18() public asGovernor {
        vm.expectRevert("ARM: invalid arm buffer");
        originARM.setARMBuffer(1e18 + 1);
    }

    function test_RevertWhen_SetPrices_Because_NotOperator() public asNotOperatorNorGovernor {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        originARM.setPrices(address(oeth), 0, 0, 0, 0);
    }

    function test_RevertWhen_SetPrices_Because_SellPriceTooLow() public asOperator {
        uint256 crossPrice = _crossPrice();
        vm.expectRevert("ARM: sell price too low");
        originARM.setPrices(address(oeth), 0, crossPrice - 1, 0, 0);
    }

    function test_RevertWhen_SetPrices_Because_BuyPriceTooHigh() public asOperator {
        uint256 crossPrice = _crossPrice();
        vm.expectRevert("ARM: invalid buy price");
        originARM.setPrices(address(oeth), crossPrice, crossPrice, 0, 0);
    }

    function test_RevertWhen_SetPrices_Because_BuyPriceTooLow() public asOperator {
        uint256 crossPrice = _crossPrice();
        vm.expectRevert("ARM: invalid buy price");
        originARM.setPrices(address(oeth), MAX_CROSS_PRICE_DEVIATION - 1, crossPrice, 0, 0);
    }

    function test_SetPrices_WithMinimumBuyPrice() public asOperator {
        uint256 crossPrice = _crossPrice();
        vm.expectEmit(address(originARM));
        emit AbstractARM.TraderateChanged(address(oeth), MAX_CROSS_PRICE_DEVIATION, crossPrice, 0, 0);

        originARM.setPrices(address(oeth), MAX_CROSS_PRICE_DEVIATION, crossPrice, 0, 0);
        assertEq(_buyPrice(), MAX_CROSS_PRICE_DEVIATION, "Wrong buy price");
    }

    function test_RevertWhen_SetCrossPrice_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setCrossPrice(address(oeth), 0);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooLow() public asGovernor {
        // Far bellow the limit
        vm.expectRevert("ARM: cross price too low");
        originARM.setCrossPrice(address(oeth), 0);

        // Just below the limit
        uint256 priceScale = PRICE_SCALE;
        uint256 maxCrossPriceDeviation = MAX_CROSS_PRICE_DEVIATION;
        vm.expectRevert("ARM: cross price too low");
        originARM.setCrossPrice(address(oeth), priceScale - maxCrossPriceDeviation - 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooHigh() public asGovernor {
        // Far above the limit
        vm.expectRevert("ARM: cross price too high");
        originARM.setCrossPrice(address(oeth), type(uint256).max);

        // Just above the limit
        uint256 priceScale = PRICE_SCALE;
        vm.expectRevert("ARM: cross price too high");
        originARM.setCrossPrice(address(oeth), priceScale + 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_SellPriceTooLow() public asGovernor {
        // Fecth useful data
        uint256 priceScale = PRICE_SCALE;
        uint256 maxCrossPriceDeviation = MAX_CROSS_PRICE_DEVIATION;

        // Reduce the cross price to be able to reduce the sell price after
        originARM.setCrossPrice(address(oeth), priceScale - maxCrossPriceDeviation);

        // Set sellT1 to the minimum value (crossPrice - 1)
        originARM.setPrices(address(oeth), PRICE_SCALE / 2, _crossPrice(), type(uint128).max, type(uint128).max);

        // Now we have enough space between PRICE_SCALE and sellT1 to set the cross price to a wrong value
        uint256 sellT1 = _sellPrice();
        vm.expectRevert("ARM: sell price too low");
        originARM.setCrossPrice(address(oeth), sellT1 + 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_BuyPriceTooHigh() public asGovernor {
        // Fecth useful data
        uint256 priceScale = PRICE_SCALE;
        uint256 maxCrossPriceDeviation = MAX_CROSS_PRICE_DEVIATION;

        // Reduce the cross price to be able to reduce the buy price after
        originARM.setCrossPrice(address(oeth), priceScale - (maxCrossPriceDeviation) / 2);

        // Set sellT1 to the maximul value (PRICE_SCALE) and buyT1 to the minimum value (crossPrice - 1)
        uint256 crossPrice = _crossPrice();
        originARM.setPrices(address(oeth), crossPrice - 1, priceScale, type(uint128).max, type(uint128).max);

        // Now we have enough space between PRICE_SCALE and buyT1 to set the cross price to a wrong value
        vm.expectRevert("ARM: invalid buy price");
        originARM.setCrossPrice(address(oeth), priceScale - maxCrossPriceDeviation);
    }

    function test_RevertWhen_SetCrossPrice_Because_TooManyBaseAssets() public asGovernor {
        uint256 crossPrice = _crossPrice();

        // Simlate OETH in the ARM.
        deal(address(oeth), address(originARM), 1e18);
        vm.expectRevert("ARM: too many base assets");
        originARM.setCrossPrice(address(oeth), crossPrice - 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_TooManyQueuedBaseAssets() public asGovernor {
        uint256 crossPrice = _crossPrice();

        // Queue OETH for protocol withdrawal so it is no longer held directly by the ARM.
        deal(address(oeth), address(originARM), 1e18);
        originARM.requestBaseAssetRedeem(address(oeth), 1e18);
        assertEq(oeth.balanceOf(address(originARM)), 0, "ARM OETH balance");

        vm.expectRevert("ARM: too many base assets");
        originARM.setCrossPrice(address(oeth), crossPrice - 1);
    }

    ////////////////////////////////////////////////////
    /// --- TESTS
    ////////////////////////////////////////////////////
    function test_SetFeeCollector() public asGovernor {
        address newCollector = vm.randomAddress();
        assertNotEq(originARM.feeCollector(), newCollector, "Wrong fee collector");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollectorUpdated(newCollector);

        originARM.setFeeCollector(newCollector);
        assertEq(originARM.feeCollector(), newCollector, "Wrong fee collector");
    }

    function test_SetFee_When_NothingToClaim() public asGovernor {
        // In this situation there is nothing to claim as we are right after deployment
        // and no swap has been done yet, so no fee has to be collected.
        uint256 newFee = originARM.fee() + 1;
        assertNotEq(originARM.fee(), newFee, "Wrong fee");
        uint256 feeCollectorBalanceBefore = weth.balanceOf(originARM.feeCollector());

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeUpdated(newFee);

        originARM.setFee(newFee);
        assertEq(originARM.fee(), newFee, "Wrong fee");
        assertEq(
            _swapFeeMultiplier(_buyPrice(), _crossPrice(), originARM.fee()),
            _expectedSwapFeeMultiplier(_buyPrice(), _crossPrice(), newFee),
            "Wrong swap fee multiplier"
        );
        assertEq(weth.balanceOf(originARM.feeCollector()), feeCollectorBalanceBefore, "Wrong fee collector balance");
    }

    function test_SetFee_When_SomethingToClaim() public swapAllWETHForOETH swapAllOETHForWETH asGovernor {
        // Swap one way and then the other way to have some fees to claim and liquidity to claim it.
        uint256 newFee = originARM.fee() + 1;
        assertNotEq(originARM.fee(), newFee, "Wrong fee");
        uint256 feeToCollect = originARM.feesAccrued();
        address feeCollector = originARM.feeCollector();
        uint256 feeCollectorBalanceBefore = weth.balanceOf(feeCollector);

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeCollected(feeCollector, feeToCollect);
        vm.expectEmit(address(originARM));
        emit AbstractARM.FeeUpdated(newFee);

        originARM.setFee(newFee);
        assertEq(originARM.fee(), newFee, "Wrong fee");
        assertEq(
            _swapFeeMultiplier(_buyPrice(), _crossPrice(), originARM.fee()),
            _expectedSwapFeeMultiplier(_buyPrice(), _crossPrice(), newFee),
            "Wrong swap fee multiplier"
        );
        assertEq(weth.balanceOf(feeCollector), feeCollectorBalanceBefore + feeToCollect, "Wrong fee collector balance");
    }

    function test_SetCapManager_ToNotZero() public asGovernor {
        address newCapManager = vm.randomAddress();
        assertNotEq(originARM.capManager(), newCapManager, "Wrong cap manager");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CapManagerUpdated(newCapManager);

        originARM.setCapManager(newCapManager);
        assertEq(originARM.capManager(), newCapManager, "Wrong cap manager");
    }

    function test_SetCapManager_ToZero() public asGovernor {
        address newCapManager = address(0);

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CapManagerUpdated(newCapManager);

        originARM.setCapManager(newCapManager);
        assertEq(originARM.capManager(), newCapManager, "Wrong cap manager");
    }

    function test_SetARMBuffer() public asGovernor {
        uint256 newBuffer = originARM.armBuffer() + 1;
        assertNotEq(originARM.armBuffer(), newBuffer, "Wrong buffer");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.ARMBufferUpdated(newBuffer);

        originARM.setARMBuffer(newBuffer);
        assertEq(originARM.armBuffer(), newBuffer, "Wrong buffer");
    }

    function test_SetPrices() public asOperator {
        uint256 crossPrice = _crossPrice();
        uint256 newSellPrice = crossPrice;
        uint256 newBuyPrice = crossPrice - 1;
        uint256 newBuyLiquidity = 5 ether;
        uint256 newSellLiquidity = 7 ether;
        assertNotEq(_sellPrice(), newSellPrice, "Identical sell price");
        assertNotEq(_buyPrice(), newBuyPrice, "Identical buy price");
        assertNotEq(_buyLiquidityRemaining(), newBuyLiquidity, "Identical buy liquidity");
        assertNotEq(_sellLiquidityRemaining(), newSellLiquidity, "Identical sell liquidity");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.TraderateChanged(address(oeth), newBuyPrice, newSellPrice, newBuyLiquidity, newSellLiquidity);

        originARM.setPrices(address(oeth), newBuyPrice, newSellPrice, newBuyLiquidity, newSellLiquidity);

        // Assertions
        assertEq(_sellPrice(), newSellPrice, "Wrong sell price");
        assertEq(_buyPrice(), newBuyPrice, "Wrong buy price");
        assertEq(_buyLiquidityRemaining(), newBuyLiquidity, "Wrong buy liquidity");
        assertEq(_sellLiquidityRemaining(), newSellLiquidity, "Wrong sell liquidity");
        assertEq(
            _swapFeeMultiplier(_buyPrice(), _crossPrice(), originARM.fee()),
            _expectedSwapFeeMultiplier(newBuyPrice, _crossPrice(), originARM.fee()),
            "Wrong swap fee multiplier"
        );
    }

    function test_SetPrices_ResetsRemainingLiquidity() public asOperator {
        uint256 crossPrice = _crossPrice();

        originARM.setPrices(address(oeth), crossPrice - 1, crossPrice, 3 ether, 4 ether);

        deal(address(weth), address(originARM), 10 ether);
        deal(address(oeth), alice, 2 ether);
        vm.startPrank(alice);
        oeth.approve(address(originARM), type(uint256).max);
        originARM.swapTokensForExactTokens(oeth, weth, 1 ether, type(uint256).max, alice);
        vm.stopPrank();

        assertEq(_buyLiquidityRemaining(), 2 ether, "Buy liquidity not consumed");

        vm.prank(operator);
        originARM.setPrices(address(oeth), crossPrice - 2, crossPrice, 8 ether, 9 ether);

        assertEq(_buyLiquidityRemaining(), 8 ether, "Buy liquidity not reset");
        assertEq(_sellLiquidityRemaining(), 9 ether, "Sell liquidity not reset");
    }

    function test_SetCrossPrice_Below() public asGovernor {
        uint256 crossPrice = _crossPrice();

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CrossPriceUpdated(address(oeth), crossPrice - 1);

        originARM.setCrossPrice(address(oeth), crossPrice - 1);

        assertEq(_crossPrice(), crossPrice - 1, "Wrong cross price");
    }

    function test_SetCrossPrice_Above() public asGovernor {
        uint256 crossPrice = _crossPrice();

        // Reduce the cross price to be able to increase it after
        originARM.setCrossPrice(address(oeth), crossPrice - 1);
        crossPrice = _crossPrice();

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CrossPriceUpdated(address(oeth), crossPrice + 1);

        originARM.setCrossPrice(address(oeth), crossPrice + 1);

        assertEq(_crossPrice(), crossPrice + 1, "Wrong cross price");
    }

    function _expectedSwapFeeMultiplier(uint256 buyT1, uint256 crossPrice, uint256 fee)
        internal
        view
        returns (uint256)
    {
        uint256 priceScale = PRICE_SCALE;
        if (buyT1 == 0 || fee == 0) return 0;
        return (crossPrice - buyT1) * fee * priceScale / (buyT1 * FEE_SCALE);
    }
}
