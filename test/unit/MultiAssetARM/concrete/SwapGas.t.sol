// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Gas snapshots for the two Uniswap-V2-style swap entrypoints (`swapExactTokensForTokens` and
///         `swapTokensForExactTokens`). Exactly one swap is measured per test, so every recorded call starts
///         from the same cold-storage baseline and the numbers are comparable across the SELL/BUY legs, the
///         pegged/adapter base assets and the 6/18-decimal liquidity variants.
///
/// @dev    MUST be run with `--isolate`. The flag executes each top-level swap call as its own transaction, so
///         the storage slots warmed during `setUp()` are reset to cold and the recorded gas matches what a
///         real on-chain swap pays. Without `--isolate` those slots stay warm, making the figures neither
///         realistic nor fairly comparable between calls.
///
///             forge test --match-contract SwapGas --isolate
///             # or: make gas-swap
///
///         Snapshots are written to `snapshots/MultiAssetARM_Swap.json`; the `_liq6` / `_liq18` suffix keeps
///         the 6- and 18-decimal liquidity variants in distinct entries within the shared group.
abstract contract SwapGas_Test is Unit_MultiAssetARM_Shared_Test {
    string internal constant GROUP = "MultiAssetARM_Swap";

    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    /// @dev Appends the liquidity-decimal variant so both subclasses share one snapshot group without colliding.
    function _name(string memory op) internal pure returns (string memory) {
        return string.concat(op, liquidityDecimals() == 18 ? "_liq18" : "_liq6");
    }

    //////////////////////////////////////////////////////
    /// --- swapExactTokensForTokens (exact-in)
    //////////////////////////////////////////////////////
    // SELL: liquidity -> base (no price factor, sell == cross).
    function _gasSellExactIn(IERC20 base, string memory op) internal {
        uint256 amountIn = DEFAULT_AMOUNT(); // 100 liquidity tokens
        dealBaseToARM(base, 1e30);
        _mint(liquidity, alice, amountIn);

        vm.prank(alice);
        arm.swapExactTokensForTokens(liquidity, base, amountIn, 0, alice);
        vm.snapshotGasLastCall(GROUP, _name(op));
    }

    // BUY: base -> liquidity (applies the 0.998 buy discount + swap fee).
    function _gasBuyExactIn(IERC20 base, string memory op) internal {
        uint256 amountIn = 100 * (10 ** base.decimals()); // 100 base tokens
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(base, alice, amountIn);

        vm.prank(alice);
        arm.swapExactTokensForTokens(base, liquidity, amountIn, 0, alice);
        vm.snapshotGasLastCall(GROUP, _name(op));
    }

    function test_gas_ExactIn_Sell_Peg6() public {
        _gasSellExactIn(peg6, "exactIn_sell_peg6");
    }

    function test_gas_ExactIn_Sell_Peg18() public {
        _gasSellExactIn(peg18, "exactIn_sell_peg18");
    }

    function test_gas_ExactIn_Sell_Adp6() public {
        _gasSellExactIn(adp6, "exactIn_sell_adp6");
    }

    function test_gas_ExactIn_Sell_Adp18() public {
        _gasSellExactIn(adp18, "exactIn_sell_adp18");
    }

    function test_gas_ExactIn_Buy_Peg6() public {
        _gasBuyExactIn(peg6, "exactIn_buy_peg6");
    }

    function test_gas_ExactIn_Buy_Peg18() public {
        _gasBuyExactIn(peg18, "exactIn_buy_peg18");
    }

    function test_gas_ExactIn_Buy_Adp6() public {
        _gasBuyExactIn(adp6, "exactIn_buy_adp6");
    }

    function test_gas_ExactIn_Buy_Adp18() public {
        _gasBuyExactIn(adp18, "exactIn_buy_adp18");
    }

    //////////////////////////////////////////////////////
    /// --- swapTokensForExactTokens (exact-out)
    //////////////////////////////////////////////////////
    // SELL exact-out: buy exact `base`, pay liquidity (+3 wei rounding buffer in liquidity decimals).
    function _gasSellExactOut(IERC20 base, uint256 amountOut, string memory op) internal {
        dealBaseToARM(base, 1e30);
        _mint(liquidity, alice, 1_000_000 * LIQUIDITY_UNIT());

        vm.prank(alice);
        arm.swapTokensForExactTokens(liquidity, base, amountOut, type(uint256).max, alice);
        vm.snapshotGasLastCall(GROUP, _name(op));
    }

    // BUY exact-out: buy exact liquidity, pay `base` (+3 wei rounding buffer in base decimals).
    function _gasBuyExactOut(IERC20 base, string memory op) internal {
        uint256 amountOut = DEFAULT_AMOUNT(); // 100 liquidity tokens
        dealLiquidityToARM(1_000_000 * LIQUIDITY_UNIT());
        dealBaseToUser(base, alice, 1e30);

        vm.prank(alice);
        arm.swapTokensForExactTokens(base, liquidity, amountOut, type(uint256).max, alice);
        vm.snapshotGasLastCall(GROUP, _name(op));
    }

    function test_gas_ExactOut_Sell_Peg6() public {
        _gasSellExactOut(peg6, 100 * 1e6, "exactOut_sell_peg6");
    }

    function test_gas_ExactOut_Sell_Peg18() public {
        _gasSellExactOut(peg18, 100 * 1e18, "exactOut_sell_peg18");
    }

    function test_gas_ExactOut_Sell_Adp6() public {
        _gasSellExactOut(adp6, 100 * 1e6, "exactOut_sell_adp6");
    }

    function test_gas_ExactOut_Sell_Adp18() public {
        _gasSellExactOut(adp18, 100 * 1e18, "exactOut_sell_adp18");
    }

    function test_gas_ExactOut_Buy_Peg6() public {
        _gasBuyExactOut(peg6, "exactOut_buy_peg6");
    }

    function test_gas_ExactOut_Buy_Peg18() public {
        _gasBuyExactOut(peg18, "exactOut_buy_peg18");
    }

    function test_gas_ExactOut_Buy_Adp6() public {
        _gasBuyExactOut(adp6, "exactOut_buy_adp6");
    }

    function test_gas_ExactOut_Buy_Adp18() public {
        _gasBuyExactOut(adp18, "exactOut_buy_adp18");
    }
}

contract SwapGas_18dec_Test is SwapGas_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract SwapGas_6dec_Test is SwapGas_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
