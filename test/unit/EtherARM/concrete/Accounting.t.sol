// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Unit_EtherARM_Shared_Test} from "../Shared.t.sol";

// Contracts
import {AbstractARM} from "contracts/AbstractARM.sol";

// Interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Coverage for the ARM's accounting view functions: `totalAssets`,
///         `convertToAssets` / `convertToShares`, `claimable`, `getReserves`,
///         and the `previewDeposit` / `previewRedeem` wrappers. Each test sets
///         up exactly one scenario along one of four axes (market, fees, LP
///         queue, yield/loss) and asserts the function's value with a
///         hand-computed expected.
contract Unit_EtherARM_Accounting_Test is Unit_EtherARM_Shared_Test {
    uint256 internal constant INITIAL = 1e12; // MIN_TOTAL_SUPPLY minted to dead at init

    function setUp() public override {
        super.setUp();
        desactiveCapManager();
    }

    //////////////////////////////////////////////////////
    /// --- totalAssets
    //////////////////////////////////////////////////////
    function test_Accounting_TotalAssets_Initial() public view {
        assertEq(etherARM.totalAssets(), INITIAL, "totalAssets at init");
    }

    function test_Accounting_TotalAssets_NoFees_NoMarket_SingleAsset() public {
        aliceFirstDeposit();
        assertEq(etherARM.totalAssets(), 100 ether + INITIAL, "totalAssets after deposit");
    }

    function test_Accounting_TotalAssets_WithMarketAllocated() public {
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market)); // buffer=0 → all to market
        assertEq(weth.balanceOf(address(etherARM)), 0, "ARM WETH (moved to market)");

        // Allocation moves liquidity; it should not change totalAssets.
        assertEq(etherARM.totalAssets(), 100 ether + INITIAL, "totalAssets unchanged by allocation");
    }

    function test_Accounting_TotalAssets_WithMarketLoss() public {
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));

        // 50% loss in the market drops the share value 1:1 (MockERC4626 reads WETH balance).
        uint256 halved = (100 ether + INITIAL) / 2;
        deal(address(weth), address(mockERC4626Market), halved);

        assertEq(etherARM.totalAssets(), halved, "totalAssets reflects market loss");
    }

    function test_Accounting_TotalAssets_WithMarketYield() public {
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));

        // Donating WETH to the market raises share value pro-rata. The ARM owns 100% of supply,
        // so the donation flows through as added totalAssets.
        deal(address(weth), address(mockERC4626Market), 100 ether + INITIAL + 10 ether);

        assertEq(etherARM.totalAssets(), 110 ether + INITIAL, "totalAssets reflects market yield");
    }

    function test_Accounting_TotalAssets_WithAccruedFees() public {
        _generateFees();

        uint256 wethBal = weth.balanceOf(address(etherARM));
        uint256 stethBal = steth.balanceOf(address(etherARM));
        uint256 fees = etherARM.feesAccrued();

        assertGt(fees, 0, "fees accrued");
        // stETH is pegged with crossPrice=1e36, so it contributes 1:1 to availableAssets.
        assertEq(etherARM.totalAssets(), wethBal + stethBal - fees, "totalAssets net of fees");
    }

    function test_Accounting_TotalAssets_AfterCollectFees() public {
        _generateFees();
        uint256 totalAssetsBefore = etherARM.totalAssets();
        uint256 fees = etherARM.feesAccrued();

        etherARM.collectFees();

        assertEq(etherARM.feesAccrued(), 0, "feesAccrued zeroed");
        assertEq(weth.balanceOf(feeCollector), fees, "feeCollector received the WETH");
        // The WETH transferred out was already excluded from totalAssets via feesAccrued, so the
        // visible totalAssets is unchanged across the collection.
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets unchanged across collect");
    }

    function test_Accounting_TotalAssets_WithPendingLPRequest() public {
        aliceFirstDeposit();
        uint256 totalAssetsBefore = etherARM.totalAssets();

        aliceRequest(50 ether);

        // Shares are escrowed (still counted in totalSupply) and no value left the ARM.
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets unchanged by pending request");
        assertEq(etherARM.totalSupply(), 100 ether + INITIAL, "totalSupply unchanged by pending request");
    }

    function test_Accounting_TotalAssets_AfterLPClaim() public {
        aliceFirstDeposit();
        (uint256 requestId,) = aliceRequest(50 ether);
        skip(CLAIM_DELAY);

        vm.prank(alice);
        etherARM.claimRedeem(requestId);

        // Claim burns 50 ether of shares and sends 50 ether of WETH out.
        assertEq(etherARM.totalAssets(), 50 ether + INITIAL, "totalAssets after claim");
        assertEq(etherARM.totalSupply(), 50 ether + INITIAL, "totalSupply after claim");
    }

    function test_Accounting_TotalAssets_WithBaseAssetBalance() public {
        addBaseAsset(steth);
        deal(address(steth), address(etherARM), 10 ether);

        // stETH is pegged with crossPrice=1e36, so its on-hand balance contributes 1:1.
        assertEq(etherARM.totalAssets(), INITIAL + 10 ether, "totalAssets with stETH balance");
    }

    function test_Accounting_TotalAssets_WithPendingBaseRedeem() public {
        addBaseAsset(steth);
        deal(address(steth), address(etherARM), 10 ether);
        uint256 totalAssetsBefore = etherARM.totalAssets();

        vm.prank(operator);
        etherARM.requestBaseAssetRedeem(address(steth), 5 ether);

        // 5 stETH moved off the ARM into the protocol queue; pendingRedeemAssets picks up the
        // same liquidity value at the (unchanged) crossPrice. Net effect on totalAssets: zero.
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets unchanged across request");
    }

    function test_Accounting_TotalAssets_AfterBaseRedeemClaimed() public {
        addBaseAsset(steth);
        deal(address(steth), address(etherARM), 10 ether);
        uint256 totalAssetsBefore = etherARM.totalAssets();

        vm.prank(operator);
        etherARM.requestBaseAssetRedeem(address(steth), 10 ether);
        vm.prank(operator);
        etherARM.claimBaseAssetRedeem(address(steth), 10 ether);

        // pendingRedeemAssets clears and 10 ether of WETH lands in the ARM.
        assertEq(etherARM.totalAssets(), totalAssetsBefore, "totalAssets unchanged across full cycle");
    }

    function test_Accounting_TotalAssets_AfterYield() public {
        aliceFirstDeposit();
        // Donate 10 WETH directly to the ARM.
        deal(address(weth), address(etherARM), 100 ether + INITIAL + 10 ether);

        assertEq(etherARM.totalAssets(), 110 ether + INITIAL, "totalAssets after WETH yield");
    }

    function test_Accounting_TotalAssets_AfterLoss_ClampedAtMinSupply() public {
        aliceFirstDeposit();
        aliceRequest(100 ether); // reserves the entire deposit
        deal(address(weth), address(etherARM), 0); // wipe out all liquidity

        // _availableAssets = 0; feesAccrued (0) + MIN_TOTAL_SUPPLY >= 0 → clamp.
        assertEq(etherARM.totalAssets(), INITIAL, "totalAssets clamped at MIN_TOTAL_SUPPLY");
    }

    //////////////////////////////////////////////////////
    /// --- convertToAssets / convertToShares
    //////////////////////////////////////////////////////
    function test_Accounting_ConvertToAssets_Initial_OneToOne() public view {
        // totalAssets = totalSupply = INITIAL → 1:1.
        assertEq(etherARM.convertToAssets(1 ether), 1 ether, "1 share -> 1 asset at init");
    }

    function test_Accounting_ConvertToShares_Initial_OneToOne() public view {
        assertEq(etherARM.convertToShares(1 ether), 1 ether, "1 asset -> 1 share at init");
    }

    function test_Accounting_ConvertToAssets_AfterYield_SharesAppreciate() public {
        aliceFirstDeposit();
        // 50 ether yield: totalAssets rises, totalSupply unchanged.
        deal(address(weth), address(etherARM), 100 ether + INITIAL + 50 ether);

        uint256 expected = uint256(1 ether) * (150 ether + INITIAL) / (100 ether + INITIAL);
        assertEq(etherARM.convertToAssets(1 ether), expected, "convertToAssets after yield");
        assertGt(expected, 1 ether, "shares appreciated");
    }

    function test_Accounting_ConvertToAssets_AfterLoss_SharesDepreciate() public {
        aliceFirstDeposit();
        // 50% loss: drop ARM WETH from 100 ether + INITIAL down to 50 ether.
        deal(address(weth), address(etherARM), 50 ether);

        uint256 expected = uint256(1 ether) * 50 ether / (100 ether + INITIAL);
        assertEq(etherARM.convertToAssets(1 ether), expected, "convertToAssets after loss");
        assertLt(expected, 1 ether, "shares depreciated");
    }

    function test_Accounting_ConvertToAssets_WithFees_NetOfAccrued() public {
        _generateFees();

        uint256 wethBal = weth.balanceOf(address(etherARM));
        uint256 stethBal = steth.balanceOf(address(etherARM));
        uint256 fees = etherARM.feesAccrued();
        uint256 expectedTotalAssets = wethBal + stethBal - fees;
        uint256 expectedShareValue = uint256(1 ether) * expectedTotalAssets / etherARM.totalSupply();

        assertEq(etherARM.convertToAssets(1 ether), expectedShareValue, "convertToAssets net of fees");
    }

    //////////////////////////////////////////////////////
    /// --- claimable
    //////////////////////////////////////////////////////
    function test_Accounting_Claimable_NoMarket() public {
        aliceFirstDeposit();
        // No claims yet, no market: claimable = convertToShares(WETH balance).
        uint256 expected = etherARM.convertToShares(100 ether + INITIAL);
        assertEq(etherARM.claimable(), expected, "claimable with no market");
    }

    function test_Accounting_Claimable_WithMarketAllocated() public {
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market)); // all WETH moved into the market

        // WETH balance now 0, but maxWithdraw from market replaces it.
        uint256 expected = etherARM.convertToShares(100 ether + INITIAL);
        assertEq(etherARM.claimable(), expected, "claimable includes market maxWithdraw");
    }

    function test_Accounting_Claimable_AfterLPClaim_AccumulatesClaimedShares() public {
        aliceFirstDeposit();
        (uint256 requestId,) = aliceRequest(50 ether);
        skip(CLAIM_DELAY);
        vm.prank(alice);
        etherARM.claimRedeem(requestId);

        // 50 ether of shares were burned; withdrawsClaimedShares is bumped by that amount.
        // Remaining WETH (50 ether + INITIAL) is still 1:1 with the remaining supply.
        uint256 expected = 50 ether + etherARM.convertToShares(50 ether + INITIAL);
        assertEq(etherARM.claimable(), expected, "claimable accumulates burned shares");
    }

    function test_Accounting_Claimable_MarketLiquidityConstrained() public {
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market));

        // Force maxWithdraw to 0. The market still has economic value (convertToAssets unchanged),
        // but claimable only counts what can actually be pulled out right now.
        vm.mockCall(address(mockERC4626Market), abi.encodeWithSelector(IERC4626.maxWithdraw.selector), abi.encode(0));

        assertEq(etherARM.claimable(), 0, "claimable drops when liquidity is constrained");

        vm.clearMockedCalls();
    }

    //////////////////////////////////////////////////////
    /// --- getReserves
    //////////////////////////////////////////////////////
    function test_Accounting_GetReserves_AfterDeposit() public {
        addBaseAsset(steth);
        aliceFirstDeposit();

        (uint256 liquidityAssets, uint256 baseAssetReserve) = etherARM.getReserves(address(steth));
        assertEq(liquidityAssets, 100 ether + INITIAL, "liquidityAssets after deposit");
        assertEq(baseAssetReserve, 0, "baseAssetReserve");
    }

    function test_Accounting_GetReserves_WithActiveMarket() public {
        addBaseAsset(steth);
        aliceFirstDeposit();
        addMarket(address(mockERC4626Market));
        setActiveMarket(address(mockERC4626Market)); // ARM WETH = 0, market maxWithdraw = deposited

        (uint256 liquidityAssets,) = etherARM.getReserves(address(steth));
        assertEq(liquidityAssets, 100 ether + INITIAL, "liquidityAssets includes market maxWithdraw");
    }

    function test_Accounting_GetReserves_WithReservedWithdrawLiquidity() public {
        addBaseAsset(steth);
        aliceFirstDeposit();
        aliceRequest(50 ether); // reservedWithdrawLiquidity = 50 ether

        (uint256 liquidityAssets,) = etherARM.getReserves(address(steth));
        assertEq(liquidityAssets, 50 ether + INITIAL, "liquidityAssets subtracts reserved");
    }

    function test_Accounting_GetReserves_ReservedExceedsBalance_ReturnsZero() public {
        addBaseAsset(steth);
        aliceFirstDeposit();
        aliceRequest(100 ether); // reserves the entire balance
        deal(address(weth), address(etherARM), 0); // wipe out WETH so reserved > balance

        (uint256 liquidityAssets,) = etherARM.getReserves(address(steth));
        assertEq(liquidityAssets, 0, "liquidityAssets clamps to zero");
    }

    function test_Accounting_GetReserves_WithBaseAssetBalance() public {
        addBaseAsset(steth);
        deal(address(steth), address(etherARM), 7 ether);

        (, uint256 baseAssetReserve) = etherARM.getReserves(address(steth));
        assertEq(baseAssetReserve, 7 ether, "baseAssetReserve reflects ARM stETH balance");
    }

    function test_Accounting_GetReserves_RevertWhen_UnsupportedAsset() public {
        // WETH is the liquidity asset, not a base asset.
        vm.expectRevert(AbstractARM.UnsupportedAsset.selector);
        etherARM.getReserves(address(weth));
    }

    //////////////////////////////////////////////////////
    /// --- previewDeposit / previewRedeem
    //////////////////////////////////////////////////////
    function test_Accounting_PreviewDeposit_MatchesConvertToShares() public {
        aliceFirstDeposit();
        deal(address(weth), address(etherARM), 100 ether + INITIAL + 25 ether); // create a non-trivial ratio

        assertEq(etherARM.previewDeposit(7 ether), etherARM.convertToShares(7 ether), "previewDeposit parity");
    }

    function test_Accounting_PreviewRedeem_MatchesConvertToAssets() public {
        aliceFirstDeposit();
        deal(address(weth), address(etherARM), 100 ether + INITIAL + 25 ether);

        assertEq(etherARM.previewRedeem(7 ether), etherARM.convertToAssets(7 ether), "previewRedeem parity");
    }

    //////////////////////////////////////////////////////
    /// --- Helpers
    //////////////////////////////////////////////////////
    /// @dev Accrues fees via a stETH → WETH buy-side swap. After this, the ARM holds added stETH
    ///      and slightly less WETH; `feesAccrued` reflects the discount captured on the swap.
    function _generateFees() internal {
        aliceFirstDeposit(); // gives the ARM enough WETH to satisfy the swap output
        addBaseAsset(steth);

        uint256 amountIn = 10 ether;
        deal(address(steth), bobby, amountIn);
        vm.prank(bobby);
        etherARM.swapExactTokensForTokens(steth, weth, amountIn, 0, bobby);
    }
}
