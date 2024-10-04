// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {CapManager} from "contracts/CapManager.sol";

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

        uint256 newFee = _bound(vm.randomUint(), 0, lidoARM.FEE_SCALE() / 2);

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
        // buy price 2 basis points higher than 1.0
        lidoARM.setPrices(1002e32, 10004e32);
        // sell price 2 basis points lower than 1.0
        lidoARM.setPrices(9980e32, 99998e32);
        // 2% of one basis point spread
        lidoARM.setPrices(999999e30, 1000001e30);

        lidoARM.setPrices(992 * 1e33, 1001 * 1e33);
        lidoARM.setPrices(10002 * 1e32, 1004 * 1e33);
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
    function test_RevertWhen_CapManager_SetLiquidityProvider_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setCapManager(address(0));
    }

    function test_RevertWhen_CapManager_SetLiquidityProvider_Because_Operator() public asOperator {
        vm.expectRevert("ARM: Only owner can call this function.");
        lidoARM.setCapManager(address(0));
    }

    //////////////////////////////////////////////////////
    /// --- LIQUIIDITY PROVIDER CONTROLLER - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CapManager_SetLiquidityProvider() public asLidoARMOwner {
        address newCapManager = vm.randomAddress();

        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.CapManagerUpdated(newCapManager);
        lidoARM.setCapManager(newCapManager);

        assertEq(lidoARM.capManager(), newCapManager);
    }

    //////////////////////////////////////////////////////
    /// --- AccountCapEnabled - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_CapManager_SetAccountCapEnabled_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only owner can call this function.");
        capManager.setAccountCapEnabled(false);
    }

    function test_RevertWhen_CapManager_SetAccountCapEnabled_Because_Operator() public asOperator {
        vm.expectRevert("ARM: Only owner can call this function.");
        capManager.setAccountCapEnabled(false);
    }

    function test_RevertWhen_CapManager_SetAccountCapEnabled_Because_AlreadySet() public asLidoARMOwner {
        vm.expectRevert("LPC: Account cap already set");
        capManager.setAccountCapEnabled(true);
    }

    //////////////////////////////////////////////////////
    /// --- AccountCapEnabled - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CapManager_SetAccountCapEnabled() public asLidoARMOwner {
        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.AccountCapEnabled(false);
        capManager.setAccountCapEnabled(false);

        assertEq(capManager.accountCapEnabled(), false);
    }

    //////////////////////////////////////////////////////
    /// --- TotalAssetsCap - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_CapManager_SetTotalAssetsCap_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        capManager.setTotalAssetsCap(100 ether);
    }

    //////////////////////////////////////////////////////
    /// --- TotalAssetsCap - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CapManager_SetTotalAssetsCap_Owner() public asLidoARMOwner {
        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.TotalAssetsCap(100 ether);
        capManager.setTotalAssetsCap(100 ether);

        assertEq(capManager.totalAssetsCap(), 100 ether);
    }

    function test_CapManager_SetTotalAssetsCap_Operator() public asOperator {
        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.TotalAssetsCap(0);
        capManager.setTotalAssetsCap(0);

        assertEq(capManager.totalAssetsCap(), 0);
    }

    //////////////////////////////////////////////////////
    /// --- LiquidityProviderCaps - REVERTING TEST
    //////////////////////////////////////////////////////
    function test_RevertWhen_CapManager_SetLiquidityProviderCaps_Because_NotOwner() public asRandomAddress {
        vm.expectRevert("ARM: Only operator or owner can call this function.");
        capManager.setLiquidityProviderCaps(testProviders, 50 ether);
    }

    //////////////////////////////////////////////////////
    /// --- LiquidityProviderCaps - PASSING TESTS
    //////////////////////////////////////////////////////
    function test_CapManager_SetLiquidityProviderCaps_Owner() public asLidoARMOwner {
        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.LiquidityProviderCap(testProviders[0], 50 ether);
        emit CapManager.LiquidityProviderCap(testProviders[1], 50 ether);
        capManager.setLiquidityProviderCaps(testProviders, 50 ether);

        assertEq(capManager.liquidityProviderCaps(testProviders[0]), 50 ether);
        assertEq(capManager.liquidityProviderCaps(testProviders[1]), 50 ether);
    }

    function test_CapManager_SetLiquidityProviderCaps_Operator() public asOperator {
        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.LiquidityProviderCap(testProviders[0], 50 ether);
        emit CapManager.LiquidityProviderCap(testProviders[1], 50 ether);
        capManager.setLiquidityProviderCaps(testProviders, 50 ether);

        assertEq(capManager.liquidityProviderCaps(testProviders[0]), 50 ether);
        assertEq(capManager.liquidityProviderCaps(testProviders[1]), 50 ether);
    }

    function test_CapManager_SetLiquidityProviderCaps_ToZero()
        public
        asOperator
        setLiquidityProviderCap(testProviders[0], 10 ether)
    {
        address[] memory providers = new address[](1);
        providers[0] = testProviders[0];

        vm.expectEmit({emitter: address(capManager)});
        emit CapManager.LiquidityProviderCap(providers[0], 0);

        capManager.setLiquidityProviderCaps(providers, 0);

        assertEq(capManager.liquidityProviderCaps(providers[0]), 0);
    }
}
