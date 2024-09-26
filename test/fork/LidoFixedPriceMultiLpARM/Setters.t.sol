// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {MultiLP} from "contracts/MultiLP.sol";
import {PerformanceFee} from "contracts/PerformanceFee.sol";
import {LiquidityProviderControllerARM} from "contracts/LiquidityProviderControllerARM.sol";

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
        lidoFixedPriceMultiLpARM.setFee(0);
    }

    function test_RevertWhen_PerformanceFee_SetFee_Because_FeeIsTooHigh() public asLidoFixedPriceMultiLpARMOwner {
        uint256 max = lidoFixedPriceMultiLpARM.FEE_SCALE();
        vm.expectRevert("ARM: fee too high");
        lidoFixedPriceMultiLpARM.setFee(max + 1);
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMultiLpARM.setFeeCollector(address(0));
    }

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_FeeCollectorIsZero()
        public
        asLidoFixedPriceMultiLpARMOwner
    {
        vm.expectRevert("ARM: invalid fee collector");
        lidoFixedPriceMultiLpARM.setFeeCollector(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - PASSING TEST
    //////////////////////////////////////////////////////
    function test_PerformanceFee_SetFee_() public asLidoFixedPriceMultiLpARMOwner {
        uint256 feeBefore = lidoFixedPriceMultiLpARM.fee();

        uint256 newFee = _bound(vm.randomUint(), 0, lidoFixedPriceMultiLpARM.FEE_SCALE());

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit PerformanceFee.FeeUpdated(newFee);
        lidoFixedPriceMultiLpARM.setFee(newFee);

        assertEq(lidoFixedPriceMultiLpARM.fee(), newFee);
        assertNotEq(feeBefore, lidoFixedPriceMultiLpARM.fee());
    }

    function test_PerformanceFee_SetFeeCollector() public asLidoFixedPriceMultiLpARMOwner {
        address feeCollectorBefore = lidoFixedPriceMultiLpARM.feeCollector();

        address newFeeCollector = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit PerformanceFee.FeeCollectorUpdated(newFeeCollector);
        lidoFixedPriceMultiLpARM.setFeeCollector(newFeeCollector);

        assertEq(lidoFixedPriceMultiLpARM.feeCollector(), newFeeCollector);
        assertNotEq(feeCollectorBefore, lidoFixedPriceMultiLpARM.feeCollector());
    }

    //////////////////////////////////////////////////////
    /// --- FIXED PRICE ARM - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_SetPrices_Because_PriceCross() public {
        vm.expectRevert("ARM: Price cross");
        lidoFixedPriceMultiLpARM.setPrices(90 * 1e33, 89 * 1e33);

        vm.expectRevert("ARM: Price cross");
        lidoFixedPriceMultiLpARM.setPrices(72, 70);

        vm.expectRevert("ARM: Price cross");
        lidoFixedPriceMultiLpARM.setPrices(1005 * 1e33, 1000 * 1e33);

        // Both set to 1.0
        vm.expectRevert("ARM: Price cross");
        lidoFixedPriceMultiLpARM.setPrices(1e36, 1e36);
    }

    function test_RevertWhen_FixedPriceARM_SetPrices_Because_PriceRange() public asLidoFixedPriceMulltiLpARMOperator {
        // buy price 11 basis points higher than 1.0
        vm.expectRevert("ARM: buy price too high");
        lidoFixedPriceMultiLpARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        vm.expectRevert("ARM: sell price too low");
        lidoFixedPriceMultiLpARM.setPrices(9980e32, 9989e32);

        // Forgot to scale up to 36 decimals
        vm.expectRevert("ARM: sell price too low");
        lidoFixedPriceMultiLpARM.setPrices(1e18, 1e18);
    }

    function test_RevertWhen_FixedPriceARM_SetPrices_Because_NotOwnerOrOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoFixedPriceMultiLpARM.setPrices(0, 0);
    }

    function test_SellPriceCannotCrossOne() public asLidoFixedPriceMulltiLpARMOperator {
        vm.expectRevert("ARM: sell price too low");
        lidoFixedPriceMulltiLpARM.setPrices(0.9997 * 1e36, 0.99999 * 1e36);
    }

    function test_BuyPriceCannotCrossOne() public asLidoFixedPriceMulltiLpARMOperator {
        vm.expectRevert("ARM: buy price too high");
        lidoFixedPriceMulltiLpARM.setPrices(1.0 * 1e36, 1.0001 * 1e36);
    }

    //////////////////////////////////////////////////////
    /// --- FIXED PRICE ARM - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_FixedPriceARM_SetPrices_Operator() public asLidoFixedPriceMulltiLpARMOperator {
        // buy price 10 basis points higher than 1.0
        lidoFixedPriceMultiLpARM.setPrices(1001e33, 1002e33);
        // sell price 10 basis points lower than 1.0
        lidoFixedPriceMultiLpARM.setPrices(9980e32, 9991e32);
        // 2% of one basis point spread
        lidoFixedPriceMultiLpARM.setPrices(999999e30, 1000001e30);

        lidoFixedPriceMultiLpARM.setPrices(992 * 1e33, 1001 * 1e33);
        lidoFixedPriceMultiLpARM.setPrices(1001 * 1e33, 1004 * 1e33);
        lidoFixedPriceMultiLpARM.setPrices(992 * 1e33, 2000 * 1e33);

        // Check the traderates
        assertEq(lidoFixedPriceMultiLpARM.traderate0(), 500 * 1e33);
        assertEq(lidoFixedPriceMultiLpARM.traderate1(), 992 * 1e33);
    }

    function test_FixedPriceARM_SetPrices_Owner() public {
        // buy price 11 basis points higher than 1.0
        lidoFixedPriceMultiLpARM.setPrices(10011e32, 10020e32);

        // sell price 11 basis points lower than 1.0
        lidoFixedPriceMultiLpARM.setPrices(9980e32, 9989e32);
    }

    //////////////////////////////////////////////////////
    /// --- OWNABLE - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Ownable_SetOwner_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMultiLpARM.setOwner(address(0));
    }

    function test_RevertWhen_Ownable_SetOperator_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMultiLpARM.setOperator(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIIDITY PROVIDER CONTROLLER - REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_LiquidityProviderController_SetLiquidityProvider_Because_NotOwner()
        public
        asRandomAddress
    {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoFixedPriceMultiLpARM.setLiquidityProviderController(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIIDITY PROVIDER CONTROLLER - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_LiquidityProviderController_SetLiquidityProvider() public asLidoFixedPriceMultiLpARMOwner {
        address newLiquidityProviderController = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit LiquidityProviderControllerARM.LiquidityProviderControllerUpdated(newLiquidityProviderController);
        lidoFixedPriceMultiLpARM.setLiquidityProviderController(newLiquidityProviderController);

        assertEq(lidoFixedPriceMultiLpARM.liquidityProviderController(), newLiquidityProviderController);
    }
}
