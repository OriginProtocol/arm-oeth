// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Unit_MultiAssetARM_Shared_Test} from "../Shared.t.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";

/// @notice Claiming a matured redeem pays out the liquidity asset, run at both 18 and 6 decimals.
abstract contract ClaimRedeem_Test is Unit_MultiAssetARM_Shared_Test {
    function setUp() public virtual override {
        super.setUp();
        desactiveCapManager();
    }

    function test_ClaimRedeem_PaysOutLiquidity() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        (uint256 requestId, uint256 assets) = requestRedeem(alice, 100e18);

        assertGe(arm.claimable(), 100e18, "queued frontier funded");

        uint256 aliceBefore = liquidity.balanceOf(alice);
        vm.warp(block.timestamp + CLAIM_DELAY);

        vm.prank(alice);
        uint256 claimed = arm.claimRedeem(requestId);

        assertEq(claimed, assets, "claimed == reserved");
        assertEq(claimed, DEFAULT_AMOUNT(), "claimed == principal");
        assertEq(liquidity.balanceOf(alice) - aliceBefore, assets, "alice received liquidity");
        assertEq(arm.reservedWithdrawLiquidity(), 0, "reservation released");
    }

    function test_ClaimRedeem_RevertWhen_DelayNotMet() public {
        firstDeposit(alice, DEFAULT_AMOUNT());
        (uint256 requestId,) = requestRedeem(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(AbstractARM.ClaimDelayNotMet.selector);
        arm.claimRedeem(requestId);
    }
}

contract ClaimRedeem_18dec_Test is ClaimRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 18;
    }
}

contract ClaimRedeem_6dec_Test is ClaimRedeem_Test {
    function liquidityDecimals() internal pure override returns (uint8) {
        return 6;
    }
}
