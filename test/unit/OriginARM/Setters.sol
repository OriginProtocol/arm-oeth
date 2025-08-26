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
        uint256 FEE_SCALE = originARM.FEE_SCALE();
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
        originARM.setPrices(0, 0);
    }

    function test_RevertWhen_SetPrices_Because_SellPriceTooLow() public asOperator {
        uint256 crossPrice = originARM.crossPrice();
        vm.expectRevert("ARM: sell price too low");
        originARM.setPrices(0, crossPrice - 1);
    }

    function test_RevertWhen_SetPrices_Because_BuyPriceTooHigh() public asOperator {
        uint256 crossPrice = originARM.crossPrice();
        vm.expectRevert("ARM: buy price too high");
        originARM.setPrices(crossPrice, crossPrice);
    }

    function test_RevertWhen_SetCrossPrice_Because_NotGovernor() public asNotGovernor {
        vm.expectRevert("ARM: Only owner can call this function.");
        originARM.setCrossPrice(0);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooLow() public asGovernor {
        // Far bellow the limit
        vm.expectRevert("ARM: cross price too low");
        originARM.setCrossPrice(0);

        // Just below the limit
        uint256 priceScale = originARM.PRICE_SCALE();
        uint256 maxCrossPriceDeviation = originARM.MAX_CROSS_PRICE_DEVIATION();
        vm.expectRevert("ARM: cross price too low");
        originARM.setCrossPrice(priceScale - maxCrossPriceDeviation - 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooHigh() public asGovernor {
        // Far above the limit
        vm.expectRevert("ARM: cross price too high");
        originARM.setCrossPrice(type(uint256).max);

        // Just above the limit
        uint256 priceScale = originARM.PRICE_SCALE();
        vm.expectRevert("ARM: cross price too high");
        originARM.setCrossPrice(priceScale + 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_SellPriceTooLow() public asGovernor {
        // Fecth useful data
        uint256 priceScale = originARM.PRICE_SCALE();
        uint256 maxCrossPriceDeviation = originARM.MAX_CROSS_PRICE_DEVIATION();

        // Reduce the cross price to be able to reduce the sell price after
        originARM.setCrossPrice(priceScale - maxCrossPriceDeviation);

        // Set sellT1 to the minimum value (crossPrice - 1)
        originARM.setPrices(0, originARM.crossPrice());

        // Now we have enough space between PRICE_SCALE and sellT1 to set the cross price to a wrong value
        uint256 sellT1 = priceScale ** 2 / originARM.traderate0();
        vm.expectRevert("ARM: sell price too low");
        originARM.setCrossPrice(sellT1 + 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_BuyPriceTooHigh() public asGovernor {
        // Fecth useful data
        uint256 priceScale = originARM.PRICE_SCALE();
        uint256 maxCrossPriceDeviation = originARM.MAX_CROSS_PRICE_DEVIATION();

        // Reduce the cross price to be able to reduce the buy price after
        originARM.setCrossPrice(priceScale - (maxCrossPriceDeviation) / 2);

        // Set sellT1 to the maximul value (PRICE_SCALE) and buyT1 to the minimum value (crossPrice - 1)
        uint256 crossPrice = originARM.crossPrice();
        originARM.setPrices(crossPrice - 1, priceScale);

        // Now we have enough space between PRICE_SCALE and buyT1 to set the cross price to a wrong value
        vm.expectRevert("ARM: buy price too high");
        originARM.setCrossPrice(priceScale - maxCrossPriceDeviation);
    }

    function test_RevertWhen_SetCrossPrice_Because_TooManyBaseAssets() public asGovernor {
        uint256 crossPrice = originARM.crossPrice();

        // Simlate OETH in the ARM.
        deal(address(oeth), address(originARM), 1e18);
        vm.expectRevert("ARM: too many base assets");
        originARM.setCrossPrice(crossPrice - 1);
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
        uint256 priceScale = originARM.PRICE_SCALE();
        uint256 crossPrice = originARM.crossPrice();
        uint256 newSellPrice = crossPrice;
        uint256 newBuyPrice = crossPrice - 1;
        assertNotEq(originARM.traderate0(), priceScale ** 2 / newSellPrice, "Identical sell price");
        assertNotEq(originARM.traderate1(), newBuyPrice, "Identical buy price");

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.TraderateChanged(priceScale ** 2 / newSellPrice, newBuyPrice);

        originARM.setPrices(newBuyPrice, newSellPrice);

        // Assertions
        assertEq(originARM.traderate0(), priceScale ** 2 / newSellPrice, "Wrong sell price");
        assertEq(originARM.traderate1(), newBuyPrice, "Wrong buy price");
    }

    function test_SetCrossPrice_Below() public asGovernor {
        uint256 crossPrice = originARM.crossPrice();

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CrossPriceUpdated(crossPrice - 1);

        originARM.setCrossPrice(crossPrice - 1);

        assertEq(originARM.crossPrice(), crossPrice - 1, "Wrong cross price");
    }

    function test_SetCrossPrice_Above() public asGovernor {
        uint256 crossPrice = originARM.crossPrice();

        // Reduce the cross price to be able to increase it after
        originARM.setCrossPrice(crossPrice - 1);
        crossPrice = originARM.crossPrice();

        // Expected event
        vm.expectEmit(address(originARM));
        emit AbstractARM.CrossPriceUpdated(crossPrice + 1);

        originARM.setCrossPrice(crossPrice + 1);

        assertEq(originARM.crossPrice(), crossPrice + 1, "Wrong cross price");
    }
}
