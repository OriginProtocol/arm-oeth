// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";

/// @notice Decimal-scaling fuzz, run at both 18 and 6 decimal liquidity. Verifies the share scaling and the
///         1e12 swap scaling hold across a wide amount range, and that no value leaks to the trader (truncation
///         dust is retained by the vault).
abstract contract Scaling_Fuzz_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    /// @dev First deposit mints `amount * MIN_TOTAL_SUPPLY / MIN_LIQUIDITY` shares (1:1 at 18-dec, x1e12 at 6-dec).
    function testFuzz_FirstDeposit_Scales(uint256 amount) public {
        amount = bound(amount, 1e6, 1e24);
        uint256 shares = firstDeposit(alice, amount);
        assertEq(shares, amount * MIN_TOTAL_SUPPLY / MIN_LIQUIDITY(), "share scaling");
    }

    /// @dev Deposit then redeem-all returns exactly the principal.
    function testFuzz_DepositRedeem_RoundTrip(uint256 amount) public {
        amount = bound(amount, 1e6, 1e24);
        firstDeposit(alice, amount);
        (uint256 requestId, uint256 assets) = requestRedeem(alice, 0);
        assertEq(assets, amount, "reserved == principal");

        vm.warp(block.timestamp + CLAIM_DELAY);
        uint256 before = liquidity.balanceOf(alice);
        vm.prank(alice);
        uint256 claimed = arm.claimRedeem(requestId);
        assertEq(claimed, amount, "claimed == principal");
        assertEq(liquidity.balanceOf(alice) - before, amount, "principal returned");
    }

    /// @dev Sell liquidity for an 18-decimal base scales by the decimal gap exactly (sell == cross price).
    function testFuzz_Sell_ScalesExactly(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 1e18);
        dealBaseToARM(peg18, 1e30);
        _mint(liquidity, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(liquidity, peg18, amountIn, 0, alice);
        assertEq(amounts[1], _scaleLiquidityToBase(peg18, amountIn), "base out scaled exactly");
    }

    /// @dev Buy liquidity with an 18-decimal base never pays out more value than scaled in; dust stays in the vault.
    function testFuzz_Buy_NoVaultLoss(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e12, 1e24);
        dealLiquidityToARM(1e25);
        dealBaseToUser(peg18, alice, amountIn);

        vm.prank(alice);
        uint256[] memory amounts = arm.swapExactTokensForTokens(peg18, liquidity, amountIn, 0, alice);

        uint256 scaled = _scaleBaseToLiquidity(peg18, amountIn);
        assertEq(amounts[1], scaled * BUY_PRICE / PRICE_SCALE, "liquidity out at buy price");
        assertLe(amounts[1], scaled, "no value created for the trader");
        assertEq(peg18.balanceOf(address(arm)), amountIn, "vault keeps the full input incl. dust");
    }
}

contract Scaling_Fuzz_18dec_Test is Scaling_Fuzz_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract Scaling_Fuzz_6dec_Test is Scaling_Fuzz_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
