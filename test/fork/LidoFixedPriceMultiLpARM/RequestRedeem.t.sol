// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

contract Fork_Concrete_LidoARM_RequestRedeem_Test_ is Fork_Shared_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), 1_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    /// @notice Test the `requestRedeem` function when there are no profits and the first deposit is made.
    function test_RequestRedeem_AfterFirstDeposit_NoPerfs_EmptyWithdrawQueue()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(0, 0, 0, 0);

        uint256 delay = lidoFixedPriceMultiLpARM.CLAIM_DELAY();

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit AbstractARM.RedeemRequested(address(this), 0, DEFAULT_AMOUNT, DEFAULT_AMOUNT, block.timestamp + delay);
        // Main Call
        (uint256 requestId, uint256 assets) = lidoFixedPriceMultiLpARM.requestRedeem(DEFAULT_AMOUNT);

        // Assertions After
        assertEq(requestId, 0); // First request
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 0, 1); // One request in the queue
        assertEqUserRequest(0, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT, DEFAULT_AMOUNT); // Requested the full amount
        assertEq(assets, DEFAULT_AMOUNT, "Wrong amount of assets"); // As no profits, assets returned are the same as deposited
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
    }

    /// @notice Test the `requestRedeem` function when there are no profits and the first deposit is made.
    function test_RequestRedeem_AfterFirstDeposit_NoPerfs_NonEmptyWithdrawQueue_SecondRedeem()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
        requestRedeemFromLidoARM(address(this), DEFAULT_AMOUNT / 4)
    {
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 3 / 4);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), DEFAULT_AMOUNT * 3 / 4);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 3 / 4);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // Down only
        assertEqQueueMetadata(DEFAULT_AMOUNT / 4, 0, 0, 1);

        uint256 delay = lidoFixedPriceMultiLpARM.CLAIM_DELAY();

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT / 2);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit AbstractARM.RedeemRequested(
            address(this), 1, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT * 3 / 4, block.timestamp + delay
        );
        // Main Call
        (uint256 requestId, uint256 assets) = lidoFixedPriceMultiLpARM.requestRedeem(DEFAULT_AMOUNT / 2);

        // Assertions After
        assertEq(requestId, 1); // Second request
        assertEqQueueMetadata(DEFAULT_AMOUNT * 3 / 4, 0, 0, 2); // Two requests in the queue
        assertEqUserRequest(
            1, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT * 3 / 4
        );
        assertEq(assets, DEFAULT_AMOUNT / 2, "Wrong amount of assets"); // As no profits, assets returned are the same as deposited
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 1 / 4);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), DEFAULT_AMOUNT * 1 / 4);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 1 / 4);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // Down only
    }

    /// @notice Test the `requestRedeem` function when there are profits and the first deposit is already made.
    function test_RequestRedeem_AfterFirstDeposit_WithPerfs_EmptyWithdrawQueue()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        // Not needed as the same as in `test_RequestRedeem_AfterFirstDeposit_NoPerfs_EmptyWithdrawQueue`

        // Simulate assets gain in ARM
        uint256 assetsGain = DEFAULT_AMOUNT;
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) + assetsGain
        );

        // Calculate expected values
        uint256 feeAccrued = assetsGain * 20 / 100; // 20% fee
        uint256 totalAsset = weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - feeAccrued;
        uint256 expectedAssets = DEFAULT_AMOUNT * totalAsset / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        uint256 expectedAssetsDead = MIN_TOTAL_SUPPLY * totalAsset / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit AbstractARM.FeeCalculated(feeAccrued, assetsGain);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);
        // Main call
        lidoFixedPriceMultiLpARM.requestRedeem(DEFAULT_AMOUNT);

        uint256 delay = lidoFixedPriceMultiLpARM.CLAIM_DELAY();
        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 2); // +perfs
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), feeAccrued);
        assertApproxEqAbs(lidoFixedPriceMultiLpARM.lastTotalAssets(), expectedAssetsDead, 1); // 1 wei of error
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(expectedAssets, 0, 0, 1);
        assertEqUserRequest(0, address(this), false, block.timestamp + delay, expectedAssets, expectedAssets);
    }

    /// @notice Test the `requestRedeem` function when ARM lost a bit of money before the request.
    function test_RequestRedeem_AfterFirstDeposit_WhenLosingFunds()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        // Not needed as the same as in `test_RequestRedeem_AfterFirstDeposit_NoPerfs_EmptyWithdrawQueue`

        // Simulate assets loss in ARM
        uint256 assetsLoss = DEFAULT_AMOUNT / 10; // 0.1 ether of loss
        deal(
            address(weth),
            address(lidoFixedPriceMultiLpARM),
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - assetsLoss
        );

        // Calculate expected values
        uint256 feeAccrued = 0; // No profits
        uint256 totalAsset = weth.balanceOf(address(lidoFixedPriceMultiLpARM));
        uint256 expectedAssets = DEFAULT_AMOUNT * totalAsset / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        uint256 expectedAssetsDead = MIN_TOTAL_SUPPLY * totalAsset / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);

        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);
        // Main call
        lidoFixedPriceMultiLpARM.requestRedeem(DEFAULT_AMOUNT);

        uint256 delay = lidoFixedPriceMultiLpARM.CLAIM_DELAY();
        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetsLoss);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), feeAccrued);
        assertApproxEqAbs(lidoFixedPriceMultiLpARM.lastTotalAssets(), expectedAssetsDead, 1); // 1 wei of error
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), 0);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(expectedAssets, 0, 0, 1);
        assertEqUserRequest(0, address(this), false, block.timestamp + delay, expectedAssets, expectedAssets);
    }
}
