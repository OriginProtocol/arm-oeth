// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Redeem requests, run at both 18 and 6 decimal liquidity. The reserved liquidity is tracked in the
///         liquidity asset's decimals; the queued frontier is tracked in 18-decimal LP shares.
abstract contract RequestRedeem_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    function test_RequestRedeem_SplitsDecimals() public {
        firstDeposit(alice, DEFAULT_AMOUNT()); // 100 tokens -> 100e18 shares

        (uint256 requestId, uint256 assets) = requestRedeem(alice, 100e18);

        assertEq(requestId, 0, "first request id");
        // Round-trip of the full position returns exactly the principal, in liquidity decimals.
        assertEq(assets, DEFAULT_AMOUNT(), "assets == principal (liquidity decimals)");
        assertEq(arm.reservedWithdrawLiquidity(), assets, "reserved liquidity");
        // Queued shares stay 18-decimal regardless of the liquidity asset.
        assertEq(arm.withdrawsQueuedShares(), 100e18, "queued shares (18-dec)");

        assertEq(arm.balanceOf(alice), 0, "alice shares escrowed");
        assertEq(arm.balanceOf(address(arm)), 100e18, "ARM holds escrowed shares");

        _assertStoredRequest(requestId, alice, block.timestamp + CLAIM_DELAY, assets, 100e18, 100e18);
    }

    function test_RequestRedeem_RevertWhen_ZeroShares() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        vm.prank(alice);
        vm.expectRevert(AbstractARM.ZeroShares.selector);
        arm.requestRedeem(0);
    }
}

contract RequestRedeem_18dec_Test is RequestRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract RequestRedeem_6dec_Test is RequestRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
