// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";

contract Fork_Concrete_lidoARM_Setters_Test_ is Fork_Shared_Test_ {
    address[] testProviders;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        testProviders = new address[](2);
        testProviders[0] = vm.randomAddress();
        testProviders[1] = vm.randomAddress();
    }

    //////////////////////////////////////////////////////
    /// --- PERFORMANCE FEE - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_PerformanceFee_SetFee_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setFee(0);
    }

    function test_RevertWhen_PerformanceFee_SetFee_Because_Operator() public asOperator {
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

    function test_RevertWhen_PerformanceFee_SetFeeCollector_Because_Operator() public asOperator {
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
    /// --- Set Prices - REVERTING TESTS
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

    function test_RevertWhen_SetPrices_Because_PriceRange() public asOperator {
        // buy price 11 basis points higher than 1.0
        vm.expectRevert("ARM: buy price too high");
        lidoARM.setPrices(1.0011 * 1e36, 1.002 * 1e36);

        // sell price 11 basis points lower than 1.0
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(0.998 * 1e36, 0.9989 * 1e36);

        // Forgot to scale up to 36 decimals
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(1e18, 1e18);
    }

    function test_RevertWhen_SetPrices_Because_NotOwnerOrOperator() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        lidoARM.setPrices(0, 0);
    }

    function test_SellPriceCannotCrossOneByMoreThanTenBps() public asOperator {
        vm.expectRevert("ARM: sell price too low");
        lidoARM.setPrices(0.998 * 1e36, 0.9989 * 1e36);
    }

    function test_BuyPriceCannotCrossOneByMoreThanTenBps() public asOperator {
        vm.expectRevert("ARM: buy price too high");
        lidoARM.setPrices(1.0011 * 1e36, 1.002 * 1e36);
    }

    //////////////////////////////////////////////////////
    /// --- Set Prices - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SetPrices_Operator() public asOperator {
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

    function test_SetPrices_Owner() public {
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

    function test_RevertWhen_Ownable_SetOwner_Because_Operator() public asOperator {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setOwner(address(0));
    }

    function test_RevertWhen_Ownable_SetOperator_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setOperator(address(0));
    }

    function test_RevertWhen_Ownable_SetOperator_Because_Operator() public asOperator {
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

    function test_RevertWhen_LiquidityProviderController_SetLiquidityProvider_Because_Operator() public asOperator {
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

    //////////////////////////////////////////////////////
    /// --- AccountCapEnabled - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_LiquidityProviderController_SetAccountCapEnabled_Because_NotOwner()
        public
        asRandomAddress
    {
        vm.expectRevert("ARM: Only owner can call this function.");
        liquidityProviderController.setAccountCapEnabled(false);
    }

    function test_RevertWhen_LiquidityProviderController_SetAccountCapEnabled_Because_Operator() public asOperator {
        vm.expectRevert("ARM: Only owner can call this function.");
        liquidityProviderController.setAccountCapEnabled(false);
    }

    function test_RevertWhen_LiquidityProviderController_SetAccountCapEnabled_Because_AlreadySet()
        public
        asLidoARMOwner
    {
        vm.expectRevert("LPC: Account cap already set");
        liquidityProviderController.setAccountCapEnabled(true);
    }

    //////////////////////////////////////////////////////
    /// --- AccountCapEnabled - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_LiquidityProviderController_SetAccountCapEnabled() public asLidoARMOwner {
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.AccountCapEnabled(false);
        liquidityProviderController.setAccountCapEnabled(false);

        assertEq(liquidityProviderController.accountCapEnabled(), false);
    }

    //////////////////////////////////////////////////////
    /// --- TotalAssetsCap - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_LiquidityProviderController_SetTotalAssetsCap_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        liquidityProviderController.setTotalAssetsCap(100 ether);
    }

    //////////////////////////////////////////////////////
    /// --- TotalAssetsCap - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_LiquidityProviderController_SetTotalAssetsCap_Owner() public asLidoARMOwner {
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.TotalAssetsCap(100 ether);
        liquidityProviderController.setTotalAssetsCap(100 ether);

        assertEq(liquidityProviderController.totalAssetsCap(), 100 ether);
    }

    function test_LiquidityProviderController_SetTotalAssetsCap_Operator() public asOperator {
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.TotalAssetsCap(0);
        liquidityProviderController.setTotalAssetsCap(0);

        assertEq(liquidityProviderController.totalAssetsCap(), 0);
    }

    //////////////////////////////////////////////////////
    /// --- LiquidityProviderCaps - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_LiquidityProviderController_SetLiquidityProviderCaps_Because_NotOwner()
        public
        asRandomAddress
    {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        liquidityProviderController.setLiquidityProviderCaps(testProviders, 50 ether);
    }

    //////////////////////////////////////////////////////
    /// --- LiquidityProviderCaps - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_LiquidityProviderController_SetLiquidityProviderCaps_Owner() public asLidoARMOwner {
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(testProviders[0], 50 ether);
        emit LiquidityProviderController.LiquidityProviderCap(testProviders[1], 50 ether);
        liquidityProviderController.setLiquidityProviderCaps(testProviders, 50 ether);

        assertEq(liquidityProviderController.liquidityProviderCaps(testProviders[0]), 50 ether);
        assertEq(liquidityProviderController.liquidityProviderCaps(testProviders[1]), 50 ether);
    }

    function test_LiquidityProviderController_SetLiquidityProviderCaps_Operator() public asOperator {
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(testProviders[0], 50 ether);
        emit LiquidityProviderController.LiquidityProviderCap(testProviders[1], 50 ether);
        liquidityProviderController.setLiquidityProviderCaps(testProviders, 50 ether);

        assertEq(liquidityProviderController.liquidityProviderCaps(testProviders[0]), 50 ether);
        assertEq(liquidityProviderController.liquidityProviderCaps(testProviders[1]), 50 ether);
    }

    function test_LiquidityProviderController_SetLiquidityProviderCaps_ToZero()
        public
        asOperator
        setLiquidityProviderCap(testProviders[0], 10 ether)
    {
        address[] memory providers = new address[](1);
        providers[0] = testProviders[0];

        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(providers[0], 0);

        liquidityProviderController.setLiquidityProviderCaps(providers, 0);

        assertEq(liquidityProviderController.liquidityProviderCaps(providers[0]), 0);
    }
}
