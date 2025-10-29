// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {CapManager} from "contracts/CapManager.sol";
import {IStETHWithdrawal} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_Deposit_Test_ is Fork_Shared_Test_ {
    bool private ac;
    uint256[] private amounts1 = new uint256[](1);
    IStETHWithdrawal private stETHWithdrawal = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL);

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), 1_000 ether);

        // Alice
        deal(address(weth), alice, 1_000 ether);
        vm.prank(alice);
        weth.approve(address(lidoARM), type(uint256).max);

        // Amounts arrays
        amounts1[0] = DEFAULT_AMOUNT;

        ac = capManager.accountCapEnabled();
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNull()
        public
        enableCaps
        setLiquidityProviderCap(address(this), 0)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapNotNull()
        public
        enableCaps
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: LP cap exceeded");
        lidoARM.deposit(DEFAULT_AMOUNT + 1);
    }

    function test_RevertWhen_Deposit_Because_LiquidityProviderCapExceeded_WithCapReached()
        public
        enableCaps
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Initial deposit
        lidoARM.deposit(DEFAULT_AMOUNT / 2);

        // Cap is now 0.5 ether
        vm.expectRevert("LPC: LP cap exceeded");
        lidoARM.deposit((DEFAULT_AMOUNT / 2) + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNull()
        public
        setTotalAssetsCap(0)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT + 1)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoARM.deposit(DEFAULT_AMOUNT);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapNotNull()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoARM.deposit(DEFAULT_AMOUNT - MIN_TOTAL_SUPPLY + 1);
    }

    function test_RevertWhen_Deposit_Because_TotalAssetsCapExceeded_WithCapReached()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        lidoARM.deposit(DEFAULT_AMOUNT / 2);
        vm.expectRevert("LPC: Total assets cap exceeded");
        lidoARM.deposit((DEFAULT_AMOUNT / 2) - MIN_TOTAL_SUPPLY + 1); // This should revert!
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
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        if (ac) assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0); // Ensure no shares before
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "total supply before"); // Minted to dead on deploy
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY, "total assets before");
        assertEq(capManager.liquidityProviderCaps(address(this)), amount, "lp cap before");
        assertEqQueueMetadata(0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        if (ac) {
            vm.expectEmit({emitter: address(capManager)});
            emit CapManager.LiquidityProviderCap(address(this), 0);
        }

        // Main call
        uint256 shares = lidoARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + amount));
        assertEq(lidoARM.balanceOf(address(this)), shares);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + amount, "total supply after");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount, "total assets after");
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0, "lp cap after"); // All the caps are used
        assertEqQueueMetadata(0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, second deposit of first user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_SecondDepositSameUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 2 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT * 2)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;

        // Assertions Before
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + amount));
        assertEq(lidoARM.balanceOf(address(this)), amount);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), amount);
        assertEqQueueMetadata(0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), amount); // shares == amount here
        if (ac) {
            vm.expectEmit({emitter: address(capManager)});
            emit CapManager.LiquidityProviderCap(address(this), 0);
        }

        // Main call
        uint256 shares = lidoARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + amount * 2));
        assertEq(lidoARM.balanceOf(address(this)), shares * 2);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, first deposit of second user.
    /// @dev No fees accrued, no withdrawals queued, and no performance fees generated
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_SecondDepositDiffUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 2 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        setLiquidityProviderCap(alice, DEFAULT_AMOUNT)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        uint256 amount = DEFAULT_AMOUNT;

        // Assertions Before
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + amount);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + amount));
        assertEq(lidoARM.balanceOf(alice), 0);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + amount); // Minted to dead on deploy
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount);
        if (ac) assertEq(capManager.liquidityProviderCaps(alice), amount);
        assertEqQueueMetadata(0, 0, 0);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, amount); // shares == amount here
        if (ac) {
            vm.expectEmit({emitter: address(capManager)});
            emit CapManager.LiquidityProviderCap(alice, 0);
        }

        vm.prank(alice);
        // Main call
        uint256 shares = lidoARM.deposit(amount);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + amount * 2));
        assertEq(lidoARM.balanceOf(alice), shares);
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + amount * 2);
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount * 2);
        if (ac) assertEq(capManager.liquidityProviderCaps(alice), 0); // All the caps are used
        assertEqQueueMetadata(0, 0, 0);
        assertEq(shares, amount); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Depositing into the ARM, first deposit of user with performance fees.
    /// @dev No fees accrued yet, no withdrawals queued, and performance fee taken
    function test_Deposit_NoFeesAccrued_EmptyWithdrawQueue_FirstDeposit_WithPerfs()
        public
        setTotalAssetsCap(type(uint256).max) // No need to restrict it for this test.
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT * 20)
    {
        // simulate asset gain
        uint256 balanceBefore = weth.balanceOf(address(lidoARM));
        uint256 assetGain = DEFAULT_AMOUNT;
        deal(address(weth), address(lidoARM), balanceBefore + assetGain);

        // 20% of the asset gain goes to the performance fees
        uint256 expectedFeesAccrued = assetGain * 20 / 100;
        uint256 expectedTotalAssetsBeforeDeposit = balanceBefore + assetGain * 80 / 100;

        // Assertions Before
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + assetGain);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0, "Outstanding ether before");
        assertEq(lidoARM.feesAccrued(), expectedFeesAccrued, "fee accrued before"); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY), "last available assets before");
        assertEq(lidoARM.balanceOf(address(this)), 0, "user shares before"); // Ensure no shares before
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "Total supply before"); // Minted to dead on deploy
        // 80% of the asset gain goes to the total assets
        assertEq(lidoARM.totalAssets(), expectedTotalAssetsBeforeDeposit, "Total assets before");
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), DEFAULT_AMOUNT * 20, "lp cap before");
        assertEqQueueMetadata(0, 0, 0);

        uint256 depositedAssets = DEFAULT_AMOUNT * 20;
        uint256 expectedShares = depositedAssets * MIN_TOTAL_SUPPLY / expectedTotalAssetsBeforeDeposit;
        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), depositedAssets);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), expectedShares);
        if (ac) {
            vm.expectEmit({emitter: address(capManager)});
            emit CapManager.LiquidityProviderCap(address(this), 0);
        }

        // deposit assets
        uint256 shares = lidoARM.deposit(depositedAssets);

        assertEq(shares, expectedShares, "minted shares");
        // No perfs, so 1 ether * totalSupply (1e12) / totalAssets (1e12) = 1 ether

        // Assertions After
        assertEq(steth.balanceOf(address(lidoARM)), 0, "stETH balance after");
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + assetGain + depositedAssets, "WETH balance after");
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0, "Outstanding ether after");
        assertEq(lidoARM.feesAccrued(), expectedFeesAccrued, "fees accrued after"); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + depositedAssets), "last total assets after");
        assertEq(lidoARM.balanceOf(address(this)), expectedShares, "user shares after");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + expectedShares, "total supply after");
        assertEq(lidoARM.totalAssets(), expectedTotalAssetsBeforeDeposit + depositedAssets, "Total assets after");
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0, "lp cap after"); // All the caps are used
        assertEqQueueMetadata(0, 0, 0);
    }

    /// @notice Depositing into the ARM reserves WETH for the withdrawal queue.
    /// @dev No fees accrued, withdrawal queue shortfall, and no performance fees generated
    function test_Deposit_NoFeesAccrued_WithdrawalRequestsOutstanding_SecondDepositDiffUser_NoPerfs()
        public
        setTotalAssetsCap(DEFAULT_AMOUNT * 3 + MIN_TOTAL_SUPPLY)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
        setLiquidityProviderCap(alice, DEFAULT_AMOUNT * 5)
        depositInLidoARM(address(this), DEFAULT_AMOUNT)
    {
        // set stETH/WETH buy price to 1
        lidoARM.setCrossPrice(1e36);
        lidoARM.setPrices(1e36 - 1, 1e36);

        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT, "total assets before swap");
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT), "last available before swap");

        // User Swap stETH for 3/4 of WETH in the ARM
        deal(address(steth), address(this), DEFAULT_AMOUNT);
        lidoARM.swapTokensForExactTokens(steth, weth, 3 * DEFAULT_AMOUNT / 4, DEFAULT_AMOUNT, address(this));
        assertApproxEqAbs(
            lidoARM.totalAssets(),
            MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT + 2,
            STETH_ERROR_ROUNDING,
            "total assets after swap"
        );
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT), "last available after swap");

        // First user requests a full withdrawal
        uint256 firstUserShares = lidoARM.balanceOf(address(this));
        (, uint256 assetsRedeem) = lidoARM.requestRedeem(firstUserShares);

        // Assertions Before
        uint256 stethBalanceBefore = 3 * DEFAULT_AMOUNT / 4;
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)),
            stethBalanceBefore,
            STETH_ERROR_ROUNDING,
            "stETH ARM balance before deposit"
        );
        uint256 wethBalanceBefore = MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT - 3 * DEFAULT_AMOUNT / 4;
        assertEq(weth.balanceOf(address(lidoARM)), wethBalanceBefore, "WETH ARM balance before deposit");
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0, "Outstanding ether before");
        assertEq(lidoARM.feesAccrued(), 0, "Fees accrued before deposit");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY),
            STETH_ERROR_ROUNDING,
            "last available assets before"
        );
        assertEq(lidoARM.balanceOf(alice), 0, "alice shares before deposit");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "total supply before deposit");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + 1, "total assets before deposit");
        if (ac) assertEq(capManager.liquidityProviderCaps(alice), DEFAULT_AMOUNT * 5, "lp cap before deposit");
        assertEqQueueMetadata(assetsRedeem, 0, 1);
        assertApproxEqAbs(assetsRedeem, DEFAULT_AMOUNT, STETH_ERROR_ROUNDING, "assets redeem before deposit");

        uint256 amount = DEFAULT_AMOUNT * 2;

        // Expected values
        uint256 expectedShares = amount * MIN_TOTAL_SUPPLY / (MIN_TOTAL_SUPPLY + 1);

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(alice, address(lidoARM), amount);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), alice, expectedShares);
        if (ac) {
            vm.expectEmit({emitter: address(capManager)});
            emit CapManager.LiquidityProviderCap(alice, DEFAULT_AMOUNT * 3);
        }

        vm.prank(alice);
        // Main call
        uint256 shares = lidoARM.deposit(amount);

        // Assertions After
        assertApproxEqAbs(
            steth.balanceOf(address(lidoARM)), stethBalanceBefore, STETH_ERROR_ROUNDING, "stETH ARM balance after"
        );
        assertEq(weth.balanceOf(address(lidoARM)), wethBalanceBefore + amount, "WETH ARM balance after deposit");
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0, "Outstanding ether after deposit");
        assertEq(lidoARM.feesAccrued(), 0, "Fees accrued after deposit"); // No perfs so no fees
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY + amount),
            STETH_ERROR_ROUNDING,
            "last available assets after deposit"
        );
        assertEq(lidoARM.balanceOf(alice), shares, "alice shares after deposit");
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY + expectedShares, "total supply after deposit");
        assertEq(lidoARM.totalAssets(), MIN_TOTAL_SUPPLY + amount + 1, "total assets after deposit");
        if (ac) assertEq(capManager.liquidityProviderCaps(alice), DEFAULT_AMOUNT * 3, "alice cap after deposit"); // All the caps are used
        // withdrawal request is now claimable
        assertEqQueueMetadata(assetsRedeem, 0, 1);
        assertApproxEqAbs(shares, expectedShares, STETH_ERROR_ROUNDING, "shares after deposit"); // No perfs, so 1 ether * totalSupply (1e18 + 1e12) / totalAssets (1e18 + 1e12) = 1 ether
    }

    /// @notice Test the following scenario:
    /// 1. ARM gain assets in stETH
    /// 2. Operator request a withdraw from Lido on steth
    /// 3. User deposit liquidity
    /// 4. Operator claim the withdrawal on Lido
    /// 5. User burn shares
    /// 6. Operator collects the performance fees
    /// Checking that amount deposited can be retrieved
    function test_Deposit_WithOutStandingWithdrawRequest_BeforeDeposit_ClaimedLidoWithdraw_WithAssetGain()
        public
        deal_(address(steth), address(lidoARM), DEFAULT_AMOUNT)
        requestLidoWithdrawalsOnLidoARM(amounts1)
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        uint256 expectedTotalSupplyBeforeDeposit = MIN_TOTAL_SUPPLY;
        uint256 expectTotalAssetsBeforeDeposit = MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 80 / 100;
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), DEFAULT_AMOUNT, "stETH in Lido withdrawal queue before deposit");
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit, "total supply before deposit");
        assertEq(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit, "total assets before deposit");
        assertEq(lidoARM.feesAccrued(), DEFAULT_AMOUNT * 20 / 100, "fees accrued before deposit");
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY), "last available assets before deposit");
        assertEq(lidoARM.balanceOf(address(this)), 0); // Ensure no shares before
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), DEFAULT_AMOUNT);
        assertEqQueueMetadata(0, 0, 0);

        // Expected values = 1249998437501
        // shares = assets * total supply / total assets
        uint256 expectShares = DEFAULT_AMOUNT * expectedTotalSupplyBeforeDeposit / expectTotalAssetsBeforeDeposit;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), expectShares);

        uint256 requestId = stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](1);
        requests[0] = requestId;

        // Main calls
        // 3. User mint shares
        uint256 shares = lidoARM.deposit(DEFAULT_AMOUNT);

        assertEq(shares, expectShares, "shares after deposit");
        assertEq(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit + DEFAULT_AMOUNT, "total assets after deposit");
        assertEq(lidoARM.feesAccrued(), DEFAULT_AMOUNT * 20 / 100, "fees accrued after deposit");
        assertEq(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT),
            "last available assets after deposit"
        );

        // 4. Lido finalization process is simulated
        lidoARM.totalAssets();
        _mockFunctionClaimWithdrawOnLidoARM(DEFAULT_AMOUNT);

        // 4. Operator claim withdrawal on lido
        uint256 lastIndex = stETHWithdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = stETHWithdrawal.findCheckpointHints(requests, 1, lastIndex);
        lidoARM.totalAssets();
        lidoARM.claimLidoWithdrawals(requests, hintIds);

        // 5. User burn shares
        (, uint256 receivedAssets) = lidoARM.requestRedeem(shares);

        // Assertions after redeem
        // This difference comes from the small value of shares, which reduces the precision of the calculation
        assertApproxEqRel(receivedAssets, DEFAULT_AMOUNT, 1e6, "received assets from redeem"); // 1e6  -> 0.0000000001%,
        assertEq(steth.balanceOf(address(lidoARM)), 0, "ARM stETH balance after redeem");
        assertEq(
            weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 2, "ARM WETH balance after redeem"
        );
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0, "stETH in Lido withdrawal queue after redeem");
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit, "total supply after redeem");
        assertApproxEqRel(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit, 1e6, "total assets after redeem");
        assertEq(lidoARM.feesAccrued(), DEFAULT_AMOUNT * 20 / 100, "fees accrued after redeem");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY), 4e6, "last available assets after redeem"
        );
        assertEq(lidoARM.balanceOf(address(this)), 0, "User shares after redeem");
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0, "all user cap used");
        assertEqQueueMetadata(receivedAssets, 0, 1);

        // 6. collect fees
        lidoARM.collectFees();

        // Assertions after collect fees
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit, "total supply after collect fees");
        assertApproxEqRel(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit, 1e6, "total assets after collect fees");
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued after collect fees");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(expectTotalAssetsBeforeDeposit),
            4e6,
            "last available assets after collect fees"
        );
    }

    /// @notice Test the following scenario:
    /// 1. User deposit liquidity
    /// 2. ARM swap between WETH and stETH (no assets gains)
    /// 2. Operator request a withdraw from Lido on steth
    /// 4. Operator claim the withdrawal on Lido
    /// 5. User burn shares
    /// Checking that amount deposited can be retrieved
    function test_Deposit_WithOutStandingWithdrawRequest_AfterDeposit_ClaimedLidoWithdraw_WithoutAssetGain()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        // Not needed, as one of the previous test already covers this scenario

        // Main calls:
        // 1. User mint shares
        uint256 shares = lidoARM.deposit(DEFAULT_AMOUNT);
        // Simulate a swap from WETH to stETH
        deal(address(weth), address(lidoARM), MIN_TOTAL_SUPPLY);
        deal(address(steth), address(lidoARM), DEFAULT_AMOUNT);
        // 2. Operator request a claim on withdraw
        lidoARM.requestLidoWithdrawals(amounts1);
        // 3. We simulate the finalization of the process
        _mockFunctionClaimWithdrawOnLidoARM(DEFAULT_AMOUNT);
        uint256 requestId = stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](1);
        requests[0] = requestId;
        // 4. Operator claim the withdrawal on lido
        uint256 lastIndex = stETHWithdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = stETHWithdrawal.findCheckpointHints(requests, 1, lastIndex);
        lidoARM.claimLidoWithdrawals(requests, hintIds);
        // 5. User burn shares
        (, uint256 receivedAssets) = lidoARM.requestRedeem(shares);

        // Assertions After
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertEq(lidoARM.feesAccrued(), 0); // No perfs so no fees
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY));
        assertEq(lidoARM.balanceOf(address(this)), 0); // Ensure no shares after
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY); // Minted to dead on deploy
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0); // All the caps are used
        assertEqQueueMetadata(receivedAssets, 0, 1);
        assertEq(receivedAssets, DEFAULT_AMOUNT, "received assets");
    }

    /// @notice Test the following scenario:
    /// 1. User deposit liquidity
    /// 2. ARM asset gain (on steth)
    /// 3. Operator request a withdraw from Lido on steth
    /// 4. Operator claim the withdrawal on Lido
    /// 5. User burn shares
    /// Checking that amount deposited + benefice can be retrieved
    function test_Deposit_WithOutStandingWithdrawRequest_AfterDeposit_ClaimedLidoWithdraw_WithAssetGain()
        public
        setLiquidityProviderCap(address(this), DEFAULT_AMOUNT)
    {
        // Assertions Before
        // Not needed, as one of the previous test already covers this scenario

        // Main calls:
        // 1. User mint shares
        assertEq(lidoARM.lastAvailableAssets(), int256(MIN_TOTAL_SUPPLY), "last available assets before deposit");

        uint256 shares = lidoARM.deposit(DEFAULT_AMOUNT);

        assertEq(lidoARM.feesAccrued(), 0, "fees accrued after deposit");
        assertEq(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT),
            "last available assets after deposit"
        );

        // 2. Simulate asset gain (on steth)
        deal(address(steth), address(lidoARM), DEFAULT_AMOUNT);
        assertApproxEqAbs(
            lidoARM.feesAccrued(), DEFAULT_AMOUNT * 20 / 100, STETH_ERROR_ROUNDING, "fees accrued before redeem"
        );

        // 3. Operator request a claim on withdraw
        lidoARM.requestLidoWithdrawals(amounts1);

        // 3. We simulate the finalization of the process
        _mockFunctionClaimWithdrawOnLidoARM(DEFAULT_AMOUNT);
        uint256 requestId = stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](1);
        requests[0] = requestId;

        // 4. Operator claim the withdrawal on lido
        uint256 lastIndex = stETHWithdrawal.getLastCheckpointIndex();
        uint256[] memory hintIds = stETHWithdrawal.findCheckpointHints(requests, 1, lastIndex);
        lidoARM.claimLidoWithdrawals(requests, hintIds);

        // 5. User burn shares
        (, uint256 receivedAssets) = lidoARM.requestRedeem(shares);

        uint256 userBenef = (DEFAULT_AMOUNT * 80 / 100) * DEFAULT_AMOUNT / (MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT);
        // Assertions After
        assertEq(receivedAssets, DEFAULT_AMOUNT + userBenef, "received assets");
        assertEq(steth.balanceOf(address(lidoARM)), 0);
        assertEq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT * 2);
        assertEq(lidoARM.lidoWithdrawalQueueAmount(), 0);
        assertApproxEqAbs(lidoARM.feesAccrued(), DEFAULT_AMOUNT * 20 / 100, 2, "fees accrued after redeem");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            // initial assets + user deposit - (user deposit + asset gain less fees)
            int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT) - int256(DEFAULT_AMOUNT + userBenef),
            STETH_ERROR_ROUNDING,
            "last available assets after redeem"
        );
        assertEq(lidoARM.balanceOf(address(this)), 0, "user shares after"); // Ensure no shares after
        assertEq(lidoARM.totalSupply(), MIN_TOTAL_SUPPLY, "total supply after"); // Minted to dead on deploy
        if (ac) assertEq(capManager.liquidityProviderCaps(address(this)), 0, "user cap"); // All the caps are used
        assertEqQueueMetadata(receivedAssets, 0, 1);
    }

    /// @notice Test the following scenario:
    /// 1. ARM gain assets in WETH after small initial deposit
    /// 2. User deposit liquidity
    /// 3. Operator collects the performance fees
    /// Check depositor hasn't lost value
    function test_Deposit_WithAssetGain()
        public
        deal_(address(weth), address(lidoARM), 2 * MIN_TOTAL_SUPPLY)
        disableCaps
    {
        // Assertions Before
        uint256 expectedTotalSupplyBeforeDeposit = MIN_TOTAL_SUPPLY;
        uint256 expectTotalAssetsBeforeDeposit = MIN_TOTAL_SUPPLY + (MIN_TOTAL_SUPPLY * 80 / 100);
        uint256 assetsPerShareBefore = expectTotalAssetsBeforeDeposit * 1e18 / expectedTotalSupplyBeforeDeposit;
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit, "total supply before deposit");
        assertEq(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit, "total assets before deposit");
        assertEq(lidoARM.feesAccrued(), MIN_TOTAL_SUPPLY * 20 / 100, "fees accrued before deposit");

        // shares = assets * total supply / total assets
        uint256 expectShares = DEFAULT_AMOUNT * expectedTotalSupplyBeforeDeposit / expectTotalAssetsBeforeDeposit;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), DEFAULT_AMOUNT);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), expectShares);

        // Main calls
        // 2. User mint shares
        uint256 shares = lidoARM.deposit(DEFAULT_AMOUNT);

        assertEq(shares, expectShares, "shares after deposit");
        assertEq(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit + DEFAULT_AMOUNT, "total assets after deposit");
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit + shares, "total supply after deposit");
        assertEq(lidoARM.feesAccrued(), MIN_TOTAL_SUPPLY * 20 / 100, "fees accrued after deposit");
        assertEq(
            lidoARM.lastAvailableAssets(),
            int256(MIN_TOTAL_SUPPLY + DEFAULT_AMOUNT),
            "last available assets after deposit"
        );
        assertGe(
            lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply(), assetsPerShareBefore, "assets per share after deposit"
        );
        assertGe(lidoARM.convertToAssets(shares), DEFAULT_AMOUNT - 1, "depositor has not lost value after deposit");

        // 3. collect fees
        lidoARM.collectFees();

        // Assertions after collect fees
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit + shares, "total supply after collect fees");
        assertApproxEqRel(
            lidoARM.totalAssets(),
            expectTotalAssetsBeforeDeposit + DEFAULT_AMOUNT,
            1e6,
            "total assets after collect fees"
        );
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued after collect fees");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(expectTotalAssetsBeforeDeposit + DEFAULT_AMOUNT),
            3,
            "last available assets after collect fees"
        );
        assertGe(
            lidoARM.convertToAssets(shares), DEFAULT_AMOUNT - 1, "depositor has not lost value after collected fees"
        );
    }

    /// @notice Test the following scenario:
    /// 1. Alice deposits 800 WETH
    /// 2. Set fee to zero
    /// 3. Swap 500 stETH for WETH
    /// 4. Bob deposits 600 WETH
    /// 5. Owner sets fee to 33%
    /// Check depositor hasn't lost value
    function test_Deposit_AfterSwapWithZeroFees()
        public
        disableCaps
        /// Give 500 stETH to tester for swapping
        deal_(address(steth), address(this), 600e18)
        /// 1. Alice deposits 800 WETH
        depositInLidoARM(address(alice), 800e18)
        /// 2. Set buy, cross and sell prices
        setPrices(0.998e36, 0.999e36, 1e36)
    {
        // Assertions Before
        uint256 aliceDeposit = 800e18;
        uint256 expectedTotalSupplyBeforeSwap = MIN_TOTAL_SUPPLY + aliceDeposit;
        uint256 expectTotalAssetsBeforeSwap = MIN_TOTAL_SUPPLY + aliceDeposit;
        uint256 assetsPerShareBeforeSwap = expectedTotalSupplyBeforeSwap * 1e18 / expectedTotalSupplyBeforeSwap;
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeSwap, "total supply before swap");
        assertEq(lidoARM.totalAssets(), expectTotalAssetsBeforeSwap, "total assets before swap");
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued before swap");

        // Main calls
        // 2. Owner sets the fee
        lidoARM.setFee(0);

        // 3. Swap 500 stETH for WETH
        uint256 swapInAmount = 500e18;
        lidoARM.swapExactTokensForTokens(
            steth, // inToken
            weth, // outToken
            swapInAmount,
            0,
            address(this) // to
        );

        uint256 expectedTotalSupplyBeforeDeposit = expectTotalAssetsBeforeSwap;
        uint256 expectTotalAssetsBeforeDeposit = expectTotalAssetsBeforeSwap - 1
            // steth in discounted to the cross price
            + ((swapInAmount * 0.999e36) / 1e36)
            // weth out discounted by the buy price
            - ((swapInAmount * 0.998e36) / 1e36);
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit, "total supply before deposit");
        assertApproxEqAbs(lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit, 3, "total assets before deposit");
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued before swap");

        /// 4. Bob deposits 600 WETH
        uint256 bobDeposit = 600e18;
        // shares = assets * total supply / total assets
        uint256 expectShares = bobDeposit * expectedTotalSupplyBeforeDeposit / expectTotalAssetsBeforeDeposit;

        // Expected events
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(this), address(lidoARM), bobDeposit);
        vm.expectEmit({emitter: address(lidoARM)});
        emit IERC20.Transfer(address(0), address(this), expectShares);

        uint256 bobShares = lidoARM.deposit(bobDeposit);

        assertEq(bobShares, expectShares, "shares after deposit");
        assertApproxEqAbs(
            lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit + bobDeposit, 3, "total assets after deposit"
        );
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit + bobShares, "total supply after deposit");
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued after deposit");
        assertEq(
            lidoARM.lastAvailableAssets(),
            int256(expectTotalAssetsBeforeSwap + bobDeposit),
            "last available assets after deposit"
        );
        assertGe(
            lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply(),
            assetsPerShareBeforeSwap,
            "assets per share after deposit"
        );
        assertGe(lidoARM.convertToAssets(bobShares), bobDeposit - 1, "depositor has not lost value after deposit");

        // 5. Owner sets fee to 33%
        lidoARM.setFee(3300);

        // Assertions after collect fees
        assertEq(lidoARM.totalSupply(), expectedTotalSupplyBeforeDeposit + bobShares, "total supply after collect fees");
        assertApproxEqRel(
            lidoARM.totalAssets(), expectTotalAssetsBeforeDeposit + bobDeposit, 1e6, "total assets after collect fees"
        );
        assertEq(lidoARM.feesAccrued(), 0, "fees accrued after collect fees");
        assertApproxEqAbs(
            lidoARM.lastAvailableAssets(),
            int256(expectTotalAssetsBeforeDeposit + bobDeposit),
            3,
            "last available assets after collect fees"
        );
        assertGe(
            lidoARM.convertToAssets(bobShares), bobDeposit - 1, "depositor has not lost value after collected fees"
        );
    }
}
