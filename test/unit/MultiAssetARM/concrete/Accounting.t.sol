// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

/// @notice totalAssets / getReserves valuation, run at both 18 and 6 decimal liquidity. Base balances are
///         valued at crossPrice (1e36 here) after decimal scaling into the liquidity asset's decimals.
abstract contract Accounting_Test is Unit_MultiAssetARM_Shared_Test {
    uint256 internal baseline;

    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
        firstDeposit(alice, DEFAULT_AMOUNT());
        baseline = MIN_LIQUIDITY() + DEFAULT_AMOUNT();
        assertEq(arm.totalAssets(), baseline, "baseline totalAssets");
    }

    function test_TotalAssets_Pegged6Base() public {
        dealBaseToARM(peg6, 50e6);
        assertEq(arm.totalAssets(), baseline + _scaleBaseToLiquidity(peg6, 50e6), "6-dec pegged base");
    }

    function test_TotalAssets_Pegged18Base() public {
        dealBaseToARM(peg18, 50e18);
        assertEq(arm.totalAssets(), baseline + _scaleBaseToLiquidity(peg18, 50e18), "18-dec pegged base");
    }

    function test_TotalAssets_AdapterBase() public {
        dealBaseToARM(adp18, 50e18);
        assertEq(arm.totalAssets(), baseline + _scaleBaseToLiquidity(adp18, 50e18), "adapter base");
    }

    function test_TotalAssets_Adapter_NonUnitRate() public {
        adapterAdp18.setRate(1.1e18);
        dealBaseToARM(adp18, 50e18);
        uint256 contribution = _scaleBaseToLiquidity(adp18, 50e18) * 1.1e18 / 1e18;
        assertEq(arm.totalAssets(), baseline + contribution, "rate-scaled adapter valuation");
    }

    function test_TotalAssets_MixedDecimalBases() public {
        dealBaseToARM(peg6, 10e6);
        dealBaseToARM(peg18, 20e18);
        dealBaseToARM(adp18, 30e18);
        uint256 sum = _scaleBaseToLiquidity(peg6, 10e6) + _scaleBaseToLiquidity(peg18, 20e18)
            + _scaleBaseToLiquidity(adp18, 30e18);
        assertEq(arm.totalAssets(), baseline + sum, "sum of mixed-decimal bases");
    }

    function test_GetReserves() public {
        dealBaseToARM(peg6, 30e6);
        (uint256 liquidityAssets, uint256 baseReserve) = arm.getReserves(address(peg6));
        assertEq(liquidityAssets, MIN_LIQUIDITY() + DEFAULT_AMOUNT(), "liquidity reserve");
        assertEq(baseReserve, 30e6, "base reserve (native base decimals)");
    }

    function test_ConvertRoundTrip() public view {
        uint256 amount = 50 * LIQUIDITY_UNIT();
        uint256 shares = arm.convertToShares(amount);
        uint256 assets = arm.convertToAssets(shares);
        assertApproxEqAbs(assets, amount, 2, "round-trip ~identity");
        assertLe(assets, amount, "rounding favors the vault");
    }
}

contract Accounting_18dec_Test is Accounting_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract Accounting_6dec_Test is Accounting_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
