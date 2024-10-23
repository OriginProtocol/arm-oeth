// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_LidoARM_SetCrossPrice_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SetCrossPrice_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setCrossPrice(0.9998e36);
    }

    function test_RevertWhen_SetCrossPrice_Because_Operator() public asOperator {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setCrossPrice(0.9998e36);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooLow() public {
        vm.expectRevert("ARM: cross price too low");
        lidoARM.setCrossPrice(0);
    }

    function test_RevertWhen_SetCrossPrice_Because_CrossPriceTooHigh() public {
        uint256 priceScale = 10 ** 36;
        vm.expectRevert("ARM: cross price too high");
        lidoARM.setCrossPrice(priceScale + 1);
    }

    function test_RevertWhen_SetCrossPrice_Because_BuyPriceTooHigh() public {
        lidoARM.setPrices(1e36 - 20e32 + 1, 1000 * 1e33 + 1);
        vm.expectRevert("ARM: buy price too high");
        lidoARM.setCrossPrice(1e36 - 20e32);
    }

    function test_RevertWhen_SetCrossPrice_Because_SellPriceTooLow() public {
        // To make it revert we need to try to make cross price above the sell1.
        // But we need to keep cross price below 1e36!
        // So first we reduce buy and sell price to minimum values
        lidoARM.setPrices(1e36 - 20e32, 1000 * 1e33 + 1);
        // This allow us to set a cross price below 1e36
        lidoARM.setCrossPrice(1e36 - 20e32 + 1);
        // Then we make both buy and sell price below the 1e36
        lidoARM.setPrices(1e36 - 20e32, 1e36 - 20e32 + 1);

        // Then we try to set cross price above the sell price
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setCrossPrice(1e36 - 20e32 + 2);
    }

    function test_RevertWhen_SetCrossPrice_Because_TooManyBaseAssets() public {
        deal(address(steth), address(lidoARM), MIN_TOTAL_SUPPLY + STETH_ERROR_ROUNDING);
        vm.expectRevert("ARM: too many base assets");
        lidoARM.setCrossPrice(1e36 - 1);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SetCrossPrice_No_StETH_Owner() public {
        deal(address(steth), address(lidoARM), MIN_TOTAL_SUPPLY - 1);

        // at 1.0
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.CrossPriceUpdated(1e36);
        lidoARM.setCrossPrice(1e36);

        // 20 basis points lower than 1.0
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.CrossPriceUpdated(0.998e36);
        lidoARM.setCrossPrice(0.998e36);
    }

    function test_SetCrossPrice_With_StETH_PriceUp_Owner() public {
        // 2 basis points lower than 1.0
        lidoARM.setCrossPrice(0.9998e36);

        deal(address(steth), address(lidoARM), MIN_TOTAL_SUPPLY + 1);

        // 1 basis points lower than 1.0
        lidoARM.setCrossPrice(0.9999e36);
    }
}
