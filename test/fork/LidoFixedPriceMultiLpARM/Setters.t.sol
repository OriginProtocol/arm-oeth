// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_lidoFixedPriceMulltiLpARM_Setters_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_PerformanceFee_SetFee_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setFee(0);
    }

    function test_RevertWhen_PerformanceFee_SetFee_Because_FeeIsTooHigh() public asLidoARMOwner {
        uint256 max = lidoARM.FEE_SCALE();
        vm.expectRevert("ARM: fee too high");
        lidoARM.setFee(max + 1);
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_FeeCollectorIsZero() public asLidoARMOwner {
        vm.expectRevert("ARM: invalid fee collector");
        lidoARM.setFeeCollector(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - PASSING TEST
    //////////////////////////////////////////////////////
    function test_PerformanceFee_SetFee_() public asLidoARMOwner {
        uint256 feeBefore = lidoARM.fee();

        uint256 newFee = _bound(vm.randomUint(), 0, lidoARM.FEE_SCALE());

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeUpdated(newFee);
        lidoARM.setFee(newFee);

        assertEq(lidoARM.fee(), newFee);
        assertNotEq(feeBefore, lidoARM.fee());
    }

    function test_PerformanceFee_SetFeeCollector() public asLidoARMOwner {
        address feeCollectorBefore = lidoARM.feeCollector();

        address newFeeCollector = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.FeeCollectorUpdated(newFeeCollector);
        lidoARM.setFeeCollector(newFeeCollector);

        assertEq(lidoARM.feeCollector(), newFeeCollector);
        assertNotEq(feeCollectorBefore, lidoARM.feeCollector());
    }

    //////////////////////////////////////////////////////
    /// --- FIXED PRICE ARM - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SetPrices_Because_PriceCross() public {
        vm.expectRevert("ARM: Price cross");
        lidoARM.setPrices(90 * 1e33, 89 * 1e33);

        vm.expectRevert("ARM: Price cross");
        lidoARM.setPrices(72, 70);

        vm.expectRevert("ARM: Price cross");
        lidoARM.setPrices(1005 * 1e33, 1000 * 1e33);

        // Both set to 1.0
        vm.expectRevert("ARM: Price cross");
        lidoARM.setPrices(1e36, 1e36);
    }

    function test_RevertWhen_FixedPriceARM_SetPrices_Because_PriceRange() public asLidoFixedPriceMulltiLpARMOperator {
        // buy price 11 basis points higher than 1.0
        vm.expectRevert("ARM: buy price too high");
        lidoARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(9980e32, 9989e32);

        // Forgot to scale up to 36 decimals
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(1e18, 1e18);
    }

    function test_RevertWhen_FixedPriceARM_SetPrices_Because_NotOwnerOrOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoARM.setPrices(0, 0);
    }

    function test_SellPriceCannotCrossOne() public asLidoFixedPriceMulltiLpARMOperator {
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(0.9997 * 1e36, 0.99999 * 1e36);
    }

    function test_BuyPriceCannotCrossOne() public asLidoFixedPriceMulltiLpARMOperator {
        vm.expectRevert("ARM: buy price too high");
        lidoARM.setPrices(1.0 * 1e36, 1.0001 * 1e36);
    }

    //////////////////////////////////////////////////////
    /// --- FIXED PRICE ARM - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_FixedPriceARM_SetPrices_Operator() public asLidoFixedPriceMulltiLpARMOperator {
        // buy price 10 basis points higher than 1.0
        lidoARM.setPrices(1001e33, 1002e33);
        // sell price 10 basis points lower than 1.0
        lidoARM.setPrices(9980e32, 9991e32);
        // 2% of one basis point spread
        lidoARM.setPrices(999999e30, 1000001e30);

        lidoARM.setPrices(992 * 1e33, 1001 * 1e33);
        lidoARM.setPrices(1001 * 1e33, 1004 * 1e33);
        lidoARM.setPrices(992 * 1e33, 2000 * 1e33);

        // Check the traderates
        assertEq(lidoARM.traderate0(), 500 * 1e33);
        assertEq(lidoARM.traderate1(), 992 * 1e33);
    }

    function test_FixedPriceARM_SetPrices_Owner() public {
        // buy price 11 basis points higher than 1.0
        lidoARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        lidoARM.setPrices(9980e32, 9989e32);
    }

    //////////////////////////////////////////////////////
    /// --- OWNABLE - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Ownable_SetOwner_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setOwner(address(0));
    }

    function test_RevertWhen_Ownable_SetOperator_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setOperator(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIIDITY PROVIDER CONTROLLER - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_LiquidityProviderController_SetLiquidityProvider_Because_NotOwner()
        public
        asRandomAddress
    {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setLiquidityProviderController(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIIDITY PROVIDER CONTROLLER - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_LiquidityProviderController_SetLiquidityProvider() public asLidoARMOwner {
        address newLiquidityProviderController = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.LiquidityProviderControllerUpdated(newLiquidityProviderController);
        lidoARM.setLiquidityProviderController(newLiquidityProviderController);

        assertEq(lidoARM.liquidityProviderController(), newLiquidityProviderController);
    }
}
