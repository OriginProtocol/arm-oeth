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
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.outstandingEther(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT));
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(0, 0, 0);

        uint256 delay = lidoARM.CLAIM_DELAY();

        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemRequested(address(this), 0, DEFAULT_AMOUNT, DEFAULT_AMOUNT, block.timestamp + delay);
        // Main Call
        (uint256 requestId, uint256 assets) = lidoARM.requestRedeem(DEFAULT_AMOUNT);

        // Assertions After
        assertEq(requestId, 0); // First request
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 1); // One request in the queue
        assertEqUserRequest(0, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT, DEFAULT_AMOUNT); // Requested the full amount
        assertEq(assets, DEFAULT_AMOUNT, "Wrong amount of assets"); // As no profits, assets returned are the same as deposited
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.outstandingEther(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
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
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.outstandingEther(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 3 / 4));
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT * 3 / 4);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 3 / 4);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // Down only
        assertEqQueueMetadata(DEFAULT_AMOUNT / 4, 0, 1);

        uint256 delay = lidoARM.CLAIM_DELAY();

        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT / 2);
        vm.expectEmit({emitter: address(lidoARM)});
        emit AbstractARM.RedeemRequested(
            address(this), 1, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT * 3 / 4, block.timestamp + delay
        );
        // Main Call
        (uint256 requestId, uint256 assets) = lidoARM.requestRedeem(DEFAULT_AMOUNT / 2);

        // Assertions After
        assertEq(requestId, 1); // Second request
        assertEqQueueMetadata(DEFAULT_AMOUNT * 3 / 4, 0, 2); // Two requests in the queue
        assertEqUserRequest(
            1, address(this), false, block.timestamp + delay, DEFAULT_AMOUNT / 2, DEFAULT_AMOUNT * 3 / 4
        );
        assertEq(assets, DEFAULT_AMOUNT / 2, "Wrong amount of assets"); // As no profits, assets returned are the same as deposited
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.outstandingEther(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 1 / 4));
        assertEq(lidoARM.balanceOf(address(this)), DEFAULT_AMOUNT * 1 / 4);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 1 / 4);
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
        uint256 assetsBeforeGain = MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT;
        uint256 assetsGain = DEFAULT_AMOUNT;
        uint256 assetsAfterGain = assetsBeforeGain + assetsGain;
        deal(address(weth), address(lidoARM), assetsAfterGain);

        // Expected Events
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);

        // Main call
        (, uint256 actualAssetsFromRedeem) = lidoARM.requestRedeem(DEFAULT_AMOUNT);

        // Calculate expected values
        uint256 expectedFeeAccrued = assetsGain * 20 / 100; // 20% fee
        uint256 expectedTotalAsset = assetsAfterGain - expectedFeeAccrued;
        uint256 expectedAssetsFromRedeem = DEFAULT_AMOUNT * expectedTotalAsset / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);

        // Assertions After
        assertEq(actualAssetsFromRedeem, expectedAssetsFromRedeem, "Assets from redeem");
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), assetsAfterGain);
        assertEq(lidoARM.outstandingEther(), 0, "stETH in Lido withdrawal queue");
        assertEq(lidoARM.feesAccrued(), expectedFeeAccrued, "fees accrued");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT) - int256(expectedAssetsFromRedeem),
            1,
            "last available assets after"
        ); // 1 wei of error
        assertEq(lidoARM.balanceOf(address(this)), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(expectedAssetsFromRedeem, 0, 1);
        assertEqUserRequest(
            0,
            address(this),
            false,
            block.timestamp + lidoARM.CLAIM_DELAY(),
            expectedAssetsFromRedeem,
            expectedAssetsFromRedeem
        );
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
        uint256 assetsBeforeLoss = MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT;
        uint256 assetsLoss = DEFAULT_AMOUNT / 10; // 0.1 ether of loss
        uint256 assetsAfterLoss = assetsBeforeLoss - assetsLoss;
        deal(address(weth), address(lidoARM), assetsAfterLoss);

        // Expected Events
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(this), address(0), DEFAULT_AMOUNT);

        // Main call
        (, uint256 actualAssetsFromRedeem) = lidoARM.requestRedeem(DEFAULT_AMOUNT);

        uint256 delay = lidoARM.CLAIM_DELAY();
        // Assertions After
        uint256 expectedAssetsFromRedeem = DEFAULT_AMOUNT * assetsAfterLoss / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(actualAssetsFromRedeem, expectedAssetsFromRedeem, "Assets from redeem");
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - assetsLoss);
        assertEq(lidoARM.outstandingEther(), 0, "stETH in Lido withdrawal queue");
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(assetsBeforeLoss - expectedAssetsFromRedeem),
            1,
            "last available assets"
        ); // 1 wei of error
        assertEq(lidoARM.balanceOf(address(this)), 0, "user LP balance");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "total supply");
        assertEq(lidoARM.totalAssets(), assetsAfterLoss - actualAssetsFromRedeem, "total assets");
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0);
        assertEqQueueMetadata(expectedAssetsFromRedeem, 0, 1);
        assertEqUserRequest(
            0, address(this), false, block.timestamp + delay, expectedAssetsFromRedeem, expectedAssetsFromRedeem
        );
    }
}
