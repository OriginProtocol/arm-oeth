// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";

// Test imports
import {Utils} from "./Utils.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Utils {
    ////////////////////////////////////////////////////
    /// --- GHOSTS
    ////////////////////////////////////////////////////
    uint256 sum_weth_fees;
    uint256 sum_weth_swap_in;
    uint256 sum_weth_swap_out;
    uint256 sum_weth_deposit;
    uint256 sum_weth_request;
    uint256 sum_weth_withdraw;
    uint256 sum_shares_request;
    uint256 sum_shares_withdraw;
    uint256 sum_weth_donated;
    uint256 sum_weth_lido_redeem;
    uint256 sum_steth_lido_requested;
    uint256 sum_steth_swap_out;
    uint256 sum_steth_swap_in;
    uint256 sum_steth_donated;
    uint256 ghost_requestCounter;
    bool ghost_swap_C = true;
    bool ghost_swap_D = true;
    bool ghost_lp_D = true;
    bool ghost_lp_E = true;
    bool ghost_lp_K = true;

    ////////////////////////////////////////////////////
    /// --- PROPERTIES
    ////////////////////////////////////////////////////

    // --- Swap properties ---
    // Invariant A: weth balance == ∑deposit + ∑wethIn + ∑wethRedeem + ∑wethDonated - ∑withdraw - ∑wethOut - ∑feesCollected
    // Invariant B: steth balance >= ∑stethIn + ∑stethDonated - ∑stethOut - ∑stethRedeem
    // Invariant C: when swap => AmountIn  == amounts[0]
    // Invariant D: when swap => AmountOut == amounts[1]

    // --- Liquidity Provider properties ---
    // Invariant A: ∑shares > 0 due to initial deposit
    // Invariant B: totalShares == ∑userShares + deadShares
    // Invariant C: previewRedeem(∑shares) == totalAssets
    // Invariant D: previewRedeem(shares) == (, uint256 assets) = previewRedeem(shares)
    // Invariant E: previewDeposit(amount) == uint256 shares = previewDeposit(amount)
    // Invariant F: nextWithdrawalIndex == requestRedeem call count
    // Invariant G: reservedWithdrawLiquidity == ∑unclaimed request.assets
    // Invariant H: withdrawsQueuedShares >= withdrawsClaimedShares
    // Invariant I: withdrawsQueuedShares == ∑request.shares
    // Invariant J: withdrawsClaimedShares == ∑claimed request.shares
    // Invariant K: ARM escrowed shares == withdrawsQueuedShares - withdrawsClaimedShares
    // Invariant M: ∑feesCollected == feeCollector.balance

    // --- Lido Liquidity Management properties ---
    // Invariant A: lidoWithdrawalQueueAmount == ∑lidoRequestRedeem.assets
    // Invariant B: address(arm).balance == 0

    ////////////////////////////////////////////////////
    /// --- SWAPS
    ////////////////////////////////////////////////////
    function property_swap_A() public view returns (bool) {
        uint256 inflows = sum_weth_deposit + sum_weth_swap_in + sum_weth_lido_redeem + sum_weth_donated;
        uint256 outflows = sum_weth_swap_out + sum_weth_withdraw + sum_weth_fees;

        return eq(weth.balanceOf(address(lidoARM)), MIN_TOTAL_SUPPLY + inflows - outflows);
    }

    function property_swap_B() public view returns (bool) {
        uint256 inflows = sum_steth_donated + sum_steth_swap_in;
        uint256 outflows = sum_steth_swap_out + sum_steth_lido_requested;

        return eq(steth.balanceOf(address(lidoARM)), inflows - outflows);
    }

    function property_swap_C() public view returns (bool) {
        return ghost_swap_C;
    }

    function property_swap_D() public view returns (bool) {
        return ghost_swap_D;
    }

    ////////////////////////////////////////////////////
    /// --- LIQUIDITY PROVIDERS
    ////////////////////////////////////////////////////
    function property_lp_A() public view returns (bool) {
        return gt(lidoARM.totalSupply(), 0);
    }

    function property_lp_B() public view returns (bool) {
        return eq(lidoARM.totalSupply(), sumOfUserShares());
    }

    function property_lp_C() public view returns (bool) {
        return eq(lidoARM.previewRedeem(sumOfUserShares()), lidoARM.totalAssets());
    }

    function property_lp_D() public view returns (bool) {
        return ghost_lp_D;
    }

    function property_lp_E() public view returns (bool) {
        return ghost_lp_E;
    }

    function property_lp_F() public view returns (bool) {
        return eq(lidoARM.nextWithdrawalIndex(), ghost_requestCounter);
    }

    function property_lp_G() public view returns (bool) {
        return eq(lidoARM.reservedWithdrawLiquidity(), sumOfUnclaimedRequestAssets());
    }

    function property_lp_H() public view returns (bool) {
        return gte(lidoARM.withdrawsQueuedShares(), lidoARM.withdrawsClaimedShares());
    }

    function property_lp_I() public view returns (bool) {
        return eq(lidoARM.withdrawsQueuedShares(), sum_shares_request);
    }

    function property_lp_invariant_J() public view returns (bool) {
        return eq(lidoARM.withdrawsClaimedShares(), sum_shares_withdraw);
    }

    function property_lp_invariant_K() public view returns (bool) {
        return
            eq(lidoARM.balanceOf(address(lidoARM)), lidoARM.withdrawsQueuedShares() - lidoARM.withdrawsClaimedShares());
    }

    function property_lp_invariant_M() public view returns (bool) {
        address feeCollector = lidoARM.feeCollector();
        return eq(weth.balanceOf(feeCollector), sum_weth_fees);
    }

    ////////////////////////////////////////////////////
    /// --- LIDO LIQUIDITY MANAGMENT
    ////////////////////////////////////////////////////
    function property_llm_A() public view returns (bool) {
        return eq(_lidoWithdrawalQueueAmount(), sum_steth_lido_requested - sum_weth_lido_redeem);
    }

    function property_llm_B() public view returns (bool) {
        return eq(address(lidoARM).balance, 0);
    }

    ////////////////////////////////////////////////////
    /// --- HELPERS
    ////////////////////////////////////////////////////
    function estimateAmountIn(IERC20 tokenOut, uint256 amountOut) public view returns (uint256) {
        if (tokenOut == weth) {
            return (amountOut * PRICE_SCALE) / _lidoBuyPrice() + 3;
        }
        return (amountOut * _lidoSellPrice()) / PRICE_SCALE + 3;
    }

    function estimateAmountOut(IERC20 tokenIn, uint256 amountIn) public view returns (uint256) {
        if (tokenIn == steth) {
            return (amountIn * _lidoBuyPrice()) / PRICE_SCALE;
        }
        return (amountIn * PRICE_SCALE) / _lidoSellPrice();
    }

    function price(IERC20 token) public view returns (uint256) {
        (uint128 buyPrice, uint128 sellPrice,,,,,,) = lidoARM.baseAssetConfigs(address(steth));
        return token == weth ? sellPrice : buyPrice;
    }

    function sumOfUserShares() public view returns (uint256) {
        uint256 sum_shares;

        for (uint256 i; i < lps.length; i++) {
            sum_shares += lidoARM.balanceOf(lps[i]);
        }

        sum_shares += lidoARM.balanceOf(address(lidoARM));
        sum_shares += lidoARM.balanceOf(address(0xdEaD));

        return sum_shares;
    }

    function sumOfUnclaimedRequestAssets() public view returns (uint256 sum) {
        uint256 nextWithdrawalIndex = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextWithdrawalIndex; i++) {
            (, bool claimed,, uint128 assets,,) = lidoARM.withdrawalRequests(i);
            if (!claimed) sum += assets;
        }
    }

    function _lidoWithdrawalQueueAmount() internal view returns (uint256 pendingRedeemAssets) {
        (,,,,, uint120 _pendingRedeemAssets,,) = lidoARM.baseAssetConfigs(address(steth));
        pendingRedeemAssets = _pendingRedeemAssets;
    }

    function _lidoBuyPrice() internal view returns (uint256 buyPrice) {
        (uint128 _buyPrice,,,,,,,) = lidoARM.baseAssetConfigs(address(steth));
        buyPrice = _buyPrice;
    }

    function _lidoSellPrice() internal view returns (uint256 sellPrice) {
        (, uint128 _sellPrice,,,,,,) = lidoARM.baseAssetConfigs(address(steth));
        sellPrice = _sellPrice;
    }

    function _lidoCrossPrice() internal view returns (uint256 crossPrice) {
        (,,,, uint128 _crossPrice,,,) = lidoARM.baseAssetConfigs(address(steth));
        crossPrice = _crossPrice;
    }

    function _requestLidoWithdrawals(uint256[] memory amounts) internal returns (uint256[] memory requestIds) {
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; ++i) {
            totalAmount += amounts[i];
        }

        uint256 previousLength = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestIdsLength();
        lidoARM.requestBaseAssetRedeem(address(steth), totalAmount);
        uint256 newLength = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestIdsLength();

        requestIds = new uint256[](newLength - previousLength);
        for (uint256 i = 0; i < requestIds.length; ++i) {
            requestIds[i] = AbstractLidoAssetAdapter(payable(stethAdapter)).pendingRequestId(previousLength + i);
        }
    }

    function _claimLidoWithdrawals(uint256[] memory requestIds) internal {
        if (requestIds.length == 0) return;

        uint256 shares;
        for (uint256 i = 0; i < requestIds.length; ++i) {
            shares += AbstractLidoAssetAdapter(payable(stethAdapter)).requestShares(requestIds[i]);
        }

        lidoARM.claimBaseAssetRedeem(address(steth), shares);
    }
}
