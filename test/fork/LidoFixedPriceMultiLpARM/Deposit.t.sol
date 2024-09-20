// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {MultiLP} from "contracts/MultiLP.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {LiquidityProviderController} from "contracts/LiquidityProviderController.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_Deposit_Test_ is Fork_Shared_Test_ {
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12;
    AssertData beforeData;
    DeltaData noChangeDeltaData =
        DeltaData({totalAssets: 10, totalSupply: 0, totalAssetsCap: 0, armWeth: 0, armSteth: 0, feesAccrued: 0});

    struct AssertData {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 totalAssetsCap;
        uint256 armWeth;
        uint256 armSteth;
        uint256 feesAccrued;
    }

    struct DeltaData {
        int256 totalAssets;
        int256 totalSupply;
        int256 totalAssetsCap;
        int256 armWeth;
        int256 armSteth;
        int256 feesAccrued;
    }

    function _snapData() internal view returns (AssertData memory data) {
        return AssertData({
            totalAssets: lidoFixedPriceMulltiLpARM.totalAssets(),
            totalSupply: lidoFixedPriceMulltiLpARM.totalSupply(),
            totalAssetsCap: liquidityProviderController.totalAssetsCap(),
            armWeth: weth.balanceOf(address(lidoFixedPriceMulltiLpARM)),
            armSteth: steth.balanceOf(address(lidoFixedPriceMulltiLpARM)),
            feesAccrued: lidoFixedPriceMulltiLpARM.feesAccrued()
        });
    }

    function assertData(AssertData memory before, DeltaData memory delta) internal view {
        AssertData memory afterData = _snapData();

        assertEq(int256(afterData.totalAssets), int256(before.totalAssets) + delta.totalAssets, "totalAssets");
        assertEq(int256(afterData.totalSupply), int256(before.totalSupply) + delta.totalSupply, "totalSupply");
        assertEq(
            int256(afterData.totalAssetsCap), int256(before.totalAssetsCap) + delta.totalAssetsCap, "totalAssetsCap"
        );
        assertEq(int256(afterData.feesAccrued), int256(before.feesAccrued) + delta.feesAccrued, "feesAccrued");
        assertEq(int256(afterData.armWeth), int256(before.armWeth) + delta.armWeth, "armWeth");
        assertEq(int256(afterData.armSteth), int256(before.armSteth) + delta.armSteth, "armSteth");
    }

    /**
     * As Deposit is complex function due to the entaglement of virtual and override functions in inheritance.
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
        weth.approve(address(lidoFixedPriceMulltiLpARM), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNull()
        public
        setLiquidityProviderCap(address(this), 0)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNotNull()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT + 1);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapReached()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Initial deposit
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT / 2);

        // Cap is now 0.5 ether
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit((DEFAULT_AMOUNT / 2) + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNull()
        public
        setTotalAssetsCap(0)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT + 1)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNotNull()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT - MIN_TOTAL_SUPPLY + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapReached()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        lidoFixedPriceMulltiLpARM.deposit(DEFAULT_AMOUNT / 2);
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit((DEFAULT_AMOUNT / 2) - MIN_TOTAL_SUPPLY + 1); // This should revert!
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    /*function test_Deposit_SimpleCase()
        public
        asLidoFixedPriceMultiLpARMOwner
        setLiquidityProviderCap(address(this), 20 ether)
    {
        deal(address(weth), address(this), 10 ether);
        beforeData = _snapData();

        lidoFixedPriceMulltiLpARM.deposit(10 ether);

        DeltaData memory delta = noChangeDeltaData;
        delta.totalAssets = 10 ether;
        delta.totalSupply = 10 ether;
        delta.armWeth = 10 ether;
        assertData(beforeData, delta);
    }*/

    /// @notice Test the simplest case of depositing into the ARM, first deposit of first user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0); // Ensure no shares before
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY); // Minted to dead on deploy
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMulltiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // Main call
        uint256 shares = lidoFixedPriceMulltiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), shares);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether
    }

    /// @notice Test a simple case of depositing into the ARM, second deposit of first user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_SecondDepositSameUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 2 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT * 2)
        depositInLidoFixedPriceMultiLpARM(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), amount);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMulltiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // Main call
        uint256 shares = lidoFixedPriceMulltiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), shares * 2);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Test a simple case of depositing into the ARM, first deposit of second user.
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
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(alice), 0);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), amount);
        assertEqQueueMetadata(0, 0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoFixedPriceMulltiLpARM), amount);
        vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        emit IERC20.Transfer(address(0), alice, amount); // shares == amount here
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(alice, 0);

        vm.prank(alice);
        // Main call
        uint256 shares = lidoFixedPriceMulltiLpARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(alice), shares);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(liquidityProviderController.liquidityProviderCaps(alice), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit_WithPerfs()
        public
        setTotalAssetsCap(type(uint256).max) // No need to restrict it for this test.
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // simulate profit
        uint256 balanceBefore = weth.balanceOf(address(lidoFixedPriceMulltiLpARM));
        uint256 profit = DEFAULT_AMOUNT;
        deal(address(weth), address(lidoFixedPriceMulltiLpARM), balanceBefore + profit);

        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + profit);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0); // Ensure no shares before
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY); // Minted to dead on deploy
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), DEFAULT_AMOUNT);
        assertEqQueueMetadata(0, 0, 0, 0);

        uint256 feesAccrued = profit * lidoFixedPriceMulltiLpARM.fee() / lidoFixedPriceMulltiLpARM.FEE_SCALE();
        uint256 rawTotalAsset = weth.balanceOf(address(lidoFixedPriceMulltiLpARM)) - feesAccrued; // No steth and no externalWithdrawQueue
        uint256 amount = DEFAULT_AMOUNT;

        uint256 expectedShares = amount * MIN_TOTAL_SUPPLY / (rawTotalAsset);
        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoFixedPriceMulltiLpARM), amount);
        //vm.expectEmit({emitter: address(lidoFixedPriceMulltiLpARM)});
        //emit IERC20.Transfer(address(0), address(this), expectedShares);
        vm.expectEmit({emitter: address(liquidityProviderController)});
        emit LiquidityProviderController.LiquidityProviderCap(address(this), 0);

        // Main call
        uint256 shares = lidoFixedPriceMulltiLpARM.deposit(amount);
        assertEq(shares, expectedShares, "Wrong shares calculation"); // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether

        // Assertions After
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + profit + amount);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), feesAccrued); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + profit + amount);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), shares);
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount);
        assertEq(liquidityProviderController.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0, 0);
    }

    function assertEqQueueMetadata(
        uint256 expectedQueued,
        uint256 expectedClaimable,
        uint256 expectedClaimed,
        uint256 expectedNextIndex
    ) public {
        (uint256 queued, uint256 claimable, uint256 claimed, uint256 nextWithdrawalIndex) =
            lidoFixedPriceMulltiLpARM.withdrawalQueueMetadata();
        assertEq(queued, expectedQueued);
        assertEq(claimable, expectedClaimable);
        assertEq(claimed, expectedClaimed);
        assertEq(nextWithdrawalIndex, expectedNextIndex);
    }
}
