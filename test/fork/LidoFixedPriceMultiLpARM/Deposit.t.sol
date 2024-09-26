// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Deposit_Test_ is Fork_Shared_Test_ {
    /**
     * As Deposit is complex function due to the entanglement of virtual and override functions in inheritance.
     * This is a small recap of the functions that are called in the deposit function.
     * 1. ML: _preDepositHook() -> PF: _calcFee() -> PF: _rawTotalAssets() -> ML: _totalAssets()
     * 2. ML: convertToShares() -> ML: _totalAssets() -> ARM: totalAssets() -> PF : totalAssets() ->
     *      -> PF: _rawTotalAssets() -> ML: _totalAssets()
     * 3. ML: _postDepositHook() -> ARM: _postDepositHook() =>
     *    | -> LCPARM: postDepositHook() -> LPC: postDepositHook() -> ARM: totalAssets() ->
     *      -> PF : totalAssets() -> PF: _rawTotalAssets() -> ML: _totalAssets()
     *    | -> PF: _postDepositHook() -> PF: _rawTotalAssets() -> ML: _totalAssets()
     *
     * ML = MultiLP
     * PF = PerformanceFee
     * ARM = LidoFixedPriceMultiLpARM
     * LPC = LiquidityProviderController
     * LCPARM = LiquidityProviderControllerARM
     */
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), 1_000 ether);

        // Alice
        deal(address(weth), alice, 1_000 ether);
        vm.prank(alice);
        weth.approve(address(lidoFixedPriceMultiLpARM), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNull()
        public
        setLiquidityProviderCap(address(this), 0)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNotNull()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT + 1);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapReached()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Initial deposit
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT / 2);

        // Cap is now 0.5 ether
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMultiLpARM.deposit((DEFAULT_AMOUNT / 2) + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNull()
        public
        setTotalAssetsCap(0)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT + 1)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNotNull()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT - MIN_TOTAL_SUPPLY + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapReached()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        lidoFixedPriceMultiLpARM.deposit(DEFAULT_AMOUNT / 2);
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMultiLpARM.deposit((DEFAULT_AMOUNT / 2) - MIN_TOTAL_SUPPLY + 1); // This should revert!
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////

    /// @notice Depositing into the ARM, first deposit of first user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), 0); // Ensure no shares before
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY); // Minted to dead on deploy
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMultiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // Main call
        uint256 shares = lidoFixedPriceMultiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), shares);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, second deposit of first user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_SecondDepositSameUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 2 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT * 2)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), amount);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMultiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // Main call
        uint256 shares = lidoFixedPriceMultiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), shares * 2);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, first deposit of second user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_SecondDepositDiffUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 2 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        setLiquidityProviderCap(alice, DEFAULT_AMOUNT)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(alice), 0);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoFixedPriceMultiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(0), alice, amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(alice, 0);

        vm.prank(alice);
        // Main call
        uint256 shares = lidoFixedPriceMultiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(alice), shares);
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, first deposit of user with performance fees.
    /// @dev No fees accrued yet, no withdrawals queued, and performance fee taken
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit_WithPerfs()
        public
        setTotalAssetsCap(type(uint256).max) // No need to restrict it for this test.
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // simulate asset gain
        uint256 balanceBefore = weth.balanceOf(address(lidoFixedPriceMultiLpARM));
        uint256 assetGain = DEFAULT_AMOUNT;
        deal(address(weth), address(lidoFixedPriceMultiLpARM), balanceBefore + assetGain);

        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), MIN_TOTAL_SUPPLY + assetGain);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0, "Outstanding ether before");
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0, "fee accrued before"); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY, "last total assets before");
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), 0, "user shares before"); // Ensure no shares before
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY, "Total supply before"); // Minted to dead on deploy
        // 80% of the asset gain goes to the total assets
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), balanceBefore + assetGain * 80 / 100, "Total assets before");
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), DEFAULT_AMOUNT, "lp cap before");
        assertEqQueueMetadata(0, 0, 0, 0);

        // 20% of the asset gain goes to the performance fees
        uint256 feesAccrued = assetGain * 20 / 100;
        uint256 rawTotalAsset = weth.balanceOf(address(lidoFixedPriceMultiLpARM)) - feesAccrued; // No steth and no externalWithdrawQueue
        uint256 depositedAssets = DEFAULT_AMOUNT;

        uint256 expectedShares = depositedAssets * MIN_TOTAL_SUPPLY / rawTotalAsset;
        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMultiLpARM), depositedAssets);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(0), address(this), expectedShares);
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // deposit assets
        uint256 shares = lidoFixedPriceMultiLpARM.deposit(depositedAssets);

        assertEq(shares, expectedShares, "minted shares");
        // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), 0, "stETH balance after");
        assertEq(
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)),
            MIN_TOTAL_SUPPLY + assetGain + depositedAssets,
            "WETH balance after"
        );
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0, "Outstanding ether after");
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), feesAccrued, "fees accrued after"); // No perfs so no fees
        assertEq(
            lidoFixedPriceMultiLpARM.lastTotalAssets(),
            MIN_TOTAL_SUPPLY + (assetGain * 80 / 100) + depositedAssets,
            "last total assets after"
        );
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(address(this)), expectedShares, "user shares after");
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + expectedShares, "total supply after");
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0, "lp cap after"); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
    }

    /// @notice Depositing into the ARM reserves WETH for the withdrawal queue.
    /// @dev No fees accrued, withdrawal queue shortfall, and no performance fees generated
    function test_Deposit_NoFeesAccrued_WithdrawalRequestsOutstanding_SecondDepositDiffUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 3 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        setLiquidityProviderCap(alice, DEFAULT_AMOUNT * 5)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        // set stETH/WETH buy price to 1
        lidoFixedPriceMultiLpARM.setPrices(1e36, 1e36 + 1);

        // User Swap stETH for 3/4 of WETH in the ARM
        deal(address(steth), address(this), DEFAULT_AMOUNT);
        lidoFixedPriceMultiLpARM.swapTokensForExactTokens(
            steth, weth, 3 * DEFAULT_AMOUNT / 4, DEFAULT_AMOUNT, address(this)
        );

        // First user requests a full withdrawal
        uint256 firstUserShares = lidoFixedPriceMultiLpARM.balanceOf(address(this));
        lidoFixedPriceMultiLpARM.requestRedeem(firstUserShares);

        // Assertions Before
        uint256 stethBalanceBefore = 3 * DEFAULT_AMOUNT / 4;
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), stethBalanceBefore, "stETH ARM balance before");
        uint256 wethBalanceBefore = MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - 3 * DEFAULT_AMOUNT / 4;
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), wethBalanceBefore, "WETH ARM balance before");
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0, "Outstanding ether before");
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0, "Fees accrued before");
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY, "last total assets before");
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(alice), 0, "alice shares before");
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY, "total supply before");
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY, "total assets before");
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), DEFAULT_AMOUNT * 5, "lp cap before");
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 0, 1);

        uint256 amount = DEFAULT_AMOUNT * 2;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoFixedPriceMultiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMultiLpARM)});
        emit IERC20.Transfer(address(0), alice, amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(alice, DEFAULT_AMOUNT * 3);

        vm.prank(alice);
        // Main call
        uint256 shares = lidoFixedPriceMultiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMultiLpARM)), stethBalanceBefore, "stETH ARM balance after");
        assertEq(
            weth.balanceOf(address(lidoFixedPriceMultiLpARM)), wethBalanceBefore + amount, "WETH ARM balance after"
        );
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0, "Outstanding ether after");
        assertEq(lidoFixedPriceMultiLpARM.feesAccrued(), 0, "Fees accrued after"); // No perfs so no fees
        assertEq(lidoFixedPriceMultiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount, "last total assets after");
        assertEq(lidoFixedPriceMultiLpARM.balanceOf(alice), shares, "alice shares after");
        assertEq(lidoFixedPriceMultiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount, "total supply after");
        assertEq(lidoFixedPriceMultiLpARM.totalAssets(), MIN_TOTAL_SUPPLY + amount, "total assets after");
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), DEFAULT_AMOUNT * 3, "alice cap after"); // All the caps are used
        // withdrawal request is now claimable
        assertEqQueueMetadata(DEFAULT_AMOUNT, 0, 0, 1);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }
}
