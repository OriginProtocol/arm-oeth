// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {Mainnet} from "src/contracts/utils/Addresses.sol";

// Interfaces
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IATokenVaultLike {
    function ATOKEN() external view returns (address);
}

/// @notice Regression coverage for the Aave high-utilization totalAssets bug.
/// Before the fix `_availableAssets` used `previewRedeem`, which Aave's ATokenVault
/// caps at the pool's withdrawable liquidity. When the underlying Aave pool is
/// fully utilized, `previewRedeem` returns 0 and the entire ARM lending position
/// would disappear from `totalAssets()`. The fix valuates the position with
/// `convertToAssets` instead.
contract Fork_Concrete_EthenaARM_TotalAssets_Test_ is Fork_Shared_Test {
    IERC4626 internal waUSDe;
    address internal aUSDe;

    function setUp() public override {
        super.setUp();

        waUSDe = IERC4626(Mainnet.AAVE_USDE_VAULT);
        aUSDe = IATokenVaultLike(address(waUSDe)).ATOKEN();

        // Allocate everything in the ARM to the Aave waUSDe market.
        address[] memory markets = new address[](1);
        markets[0] = address(waUSDe);

        vm.startPrank(governor);
        ethenaARM.addMarkets(markets);
        ethenaARM.setARMBuffer(0);
        // setActiveMarket triggers an _allocate at the end.
        ethenaARM.setActiveMarket(address(waUSDe));
        vm.stopPrank();
    }

    /// @notice When the underlying Aave pool runs out of withdrawable USDe (≈100%
    /// utilization), waUSDe's `previewRedeem` collapses to 0 but `convertToAssets`
    /// keeps reporting the economic value. `totalAssets()` must stay invariant
    /// while `claimable()` correctly drops by the now-illiquid portion.
    function test_Fork_TotalAssets_When_AaveHighUtilization() public {
        uint256 marketShares = waUSDe.balanceOf(address(ethenaARM));
        require(marketShares > 0, "test setup: ARM should hold market shares");

        uint256 totalAssetsBefore = ethenaARM.totalAssets();
        uint256 claimableBefore = ethenaARM.claimable();
        uint256 economicMarketValue = waUSDe.convertToAssets(marketShares);

        // Sanity: with healthy liquidity, previewRedeem ~= convertToAssets and
        // claimable accounts for the full market position via maxWithdraw.
        assertApproxEqAbs(waUSDe.previewRedeem(marketShares), economicMarketValue, 1, "preview ~= convert before drain");
        assertApproxEqAbs(
            waUSDe.maxWithdraw(address(ethenaARM)), economicMarketValue, 1, "maxWithdraw ~= convert before drain"
        );

        // Force the Aave pool into "100% utilization" by zeroing the unborrowed
        // USDe sitting in the aToken. ATokenVault's `_maxAssetsWithdrawableFromAave`
        // returns `UNDERLYING.balanceOf(ATOKEN)`, so this collapses both
        // `previewRedeem` and `maxWithdraw` to 0.
        deal(address(usde), aUSDe, 0);

        assertEq(waUSDe.previewRedeem(marketShares), 0, "previewRedeem must be 0 after drain");
        assertEq(waUSDe.maxWithdraw(address(ethenaARM)), 0, "maxWithdraw must be 0 after drain");
        assertApproxEqAbs(
            waUSDe.convertToAssets(marketShares), economicMarketValue, 1, "convertToAssets must be unchanged"
        );

        // Regression: with the previous code (previewRedeem-based), totalAssets
        // would collapse by ~economicMarketValue. With the fix it must not move.
        assertEq(ethenaARM.totalAssets(), totalAssetsBefore, "totalAssets must be invariant under Aave illiquidity");

        // Liquidity-aware accounting: claimable drops by the now-unrealizable portion.
        assertApproxEqAbs(
            claimableBefore - ethenaARM.claimable(), economicMarketValue, 1, "claimable drops by the Aave portion"
        );
    }

    /// @notice Sanity check: the new valuation does not under- or over-report
    /// the lending market position when liquidity is healthy. With Aave behaving
    /// normally, previewRedeem ~= convertToAssets, so totalAssets is the same
    /// regardless of which one the implementation uses.
    function test_Fork_TotalAssets_When_AaveHealthy() public view {
        uint256 marketShares = waUSDe.balanceOf(address(ethenaARM));
        require(marketShares > 0, "test setup: ARM should hold market shares");

        uint256 valueByPreview = waUSDe.previewRedeem(marketShares);
        uint256 valueByConvert = waUSDe.convertToAssets(marketShares);

        // With healthy liquidity Aave's ATokenVault returns the same value
        // through both functions (1 wei rounding tolerance).
        assertApproxEqAbs(valueByPreview, valueByConvert, 1, "preview ~= convert when healthy");

        // totalAssets reflects: liquid USDe + ARM's sUSDe @ crossPrice + market value.
        uint256 ta = ethenaARM.totalAssets();
        assertGt(ta, valueByConvert, "totalAssets includes more than just the market");
    }
}
