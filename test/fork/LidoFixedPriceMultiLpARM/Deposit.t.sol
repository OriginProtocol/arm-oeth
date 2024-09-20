// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

import {MultiLP} from "contracts/MultiLP.sol";

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
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNull()
        public
        setLiquidityProviderCap(address(this), 0)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(10 ether);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNotNull()
        public
        setLiquidityProviderCap(address(this), 5 ether)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(5 ether + 1);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapReached()
        public
        setLiquidityProviderCap(address(this), 10 ether)
    {
        // Initial deposit
        lidoFixedPriceMulltiLpARM.deposit(6 ether);

        // Cap is now 4 ether (10 - 6)
        vm.expectRevert("LPC: LP cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(4 ether + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNull()
        public
        setTotalAssetsCap(0)
        setLiquidityProviderCap(address(this), 50 ether)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(20 ether);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNotNull()
        public
        setTotalAssetsCap(10 ether)
        setLiquidityProviderCap(address(this), 50 ether)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(10 ether + 1); // This should revert!
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapReached()
        public
        setTotalAssetsCap(10 ether)
        setLiquidityProviderCap(address(this), 50 ether)
    {
        lidoFixedPriceMulltiLpARM.deposit(5 ether);
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoFixedPriceMulltiLpARM.deposit(5 ether + 1); // This should revert!
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

   /*
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit() public {
        uint256 amount = 10 ether;
        // Assertions Before
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY);
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), 0); // Ensure no shares before
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY); // Minted to dead on deploy

        uint256 shares = lidoFixedPriceMulltiLpARM.deposit(amount);

        // Assertions After
        assertEq(lidoFixedPriceMulltiLpARM.outstandingEther(), 0);
        assertEqQueueMetadata(0, 0, 0, 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMulltiLpARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(steth.balanceOf(address(lidoFixedPriceMulltiLpARM)), 0);
        assertEq(lidoFixedPriceMulltiLpARM.lastTotalAssets(), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoFixedPriceMulltiLpARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoFixedPriceMulltiLpARM.balanceOf(address(this)), shares);
        assertEq(shares, amount); // No perfs, so 10 ether * totalSupply (1e12) / totalAssets (1e12) = 10 ether
        assertEq(lidoFixedPriceMulltiLpARM.totalSupply(), MIN_TOTAL_SUPPLY + amount);
    }*/

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
