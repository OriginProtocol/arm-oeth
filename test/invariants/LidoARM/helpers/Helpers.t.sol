// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {Base_Test_} from "../base/Base.t.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

/// @title Helpers
/// @notice Utility functions shared across invariant target functions.
///         Provides user/request selection, token helpers, and array manipulation.
abstract contract Helpers is Base_Test_ {
    ////////////////////////////////////////////////////
    /// --- MODIFIERS
    ////////////////////////////////////////////////////

    modifier ensureSharePriceNotDecreased() {
        uint256 priceBefore = lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply();
        _;
        uint256 priceAfter = lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply();
        // Allow 2 wei tolerance for ERC4626 convertToAssets rounding on split operations
        require(priceAfter + 2 >= priceBefore, "SHARE_PRICE_DECREASED");
        ghost_lastSharePrice = priceAfter;
    }

    modifier updateSharePrice() {
        _;
        ghost_lastSharePrice = lidoARM.totalAssets() * 1e18 / lidoARM.totalSupply();
        ghost_crossPriceChanged = true;
    }

    ////////////////////////////////////////////////////
    /// --- DEAL HELPERS
    ////////////////////////////////////////////////////

    /// @notice Mint wstETH to `to` via the proper ERC-4626 mint path.
    /// @dev Cannot use Forge's `deal` for wstETH because it would bypass the
    ///      underlying stETH transfer and break vault accounting.
    function dealWsteth(address to, uint256 amount) internal {
        address from = address(0xfeed);
        require(wsteth.balanceOf(from) == 0, "from address should start with 0 wstETH");

        // Convert share amount to the required stETH deposit.
        uint256 requiredStETH = mockWstETH.previewMint(amount);
        MockERC20(address(steth)).mint(from, requiredStETH);

        vm.startPrank(from);
        steth.approve(address(wsteth), requiredStETH);
        mockWstETH.mint(amount, from);
        wsteth.transfer(to, amount);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////
    /// --- USER SELECTION
    ////////////////////////////////////////////////////

    /// @notice Pick the first LP (round-robin from `seed`) that holds WETH.
    /// @return user  Address of the selected LP, or address(0) if none found.
    /// @return balance  WETH balance of the selected LP.
    function selectUserWithLiqudity(uint256 seed) internal view returns (address, uint256) {
        uint256 start = seed % LP_COUNT;
        for (uint256 i; i < LP_COUNT; i++) {
            address user = lps[(start + i) % LP_COUNT];
            if (weth.balanceOf(user) > 0) {
                return (user, weth.balanceOf(user));
            }
        }
        return (address(0), 0);
    }

    /// @notice Pick the first LP (round-robin from `seed`) that holds ARM shares.
    /// @return user  Address of the selected LP, or address(0) if none found.
    /// @return balance  ARM share balance of the selected LP.
    function selectUserWithShares(uint256 seed) internal view returns (address, uint256) {
        uint256 start = seed % LP_COUNT;
        for (uint256 i; i < LP_COUNT; i++) {
            address user = lps[(start + i) % LP_COUNT];
            if (lidoARM.balanceOf(user) > 0) {
                return (user, lidoARM.balanceOf(user));
            }
        }
        return (address(0), 0);
    }

    /// @notice Find the first pending withdrawal request that is claimable right now.
    /// @dev A request is claimable when:
    ///      1. Its claim delay has elapsed (claimTimestamp <= block.timestamp)
    ///      2. Enough liquidity backs its FIFO position (queued <= claimable)
    ///      3. It hasn't been claimed yet
    /// @return user  The withdrawer, or address(0) if no claimable request exists.
    /// @return requestId  The withdrawal request id.
    /// @return index  Position in `_pendingRequestIds` (for removal after claim).
    function selectUserWithPendingRequest() internal view returns (address, uint256, uint256) {
        uint256 claimable = lidoARM.claimable();
        uint256 pendingRequestCount = _pendingRequestIds.length;

        // Early exit: nothing to claim if no requests exist or no liquidity is available.
        if (pendingRequestCount == 0 || claimable == 0) return (address(0), 0, 0);

        for (uint256 i; i < pendingRequestCount; i++) {
            uint256 requestId = _pendingRequestIds[i];
            (address user, bool claimed, uint40 claimTimestamp,, uint128 queued) = lidoARM.withdrawalRequests(requestId);
            if (claimTimestamp > block.timestamp) continue; // Claim delay not elapsed
            if (queued > claimable) continue; // FIFO gate: not enough backed liquidity

            require(!claimed, "Request already claimed");

            return (user, requestId, i);
        }

        return (address(0), 0, 0);
    }

    ////////////////////////////////////////////////////
    /// --- ARRAY UTILITIES
    ////////////////////////////////////////////////////

    /// @notice Fisher-Yates shuffle on a storage array.
    /// @dev O(n) with one keccak256 per element. Negligible cost for small arrays.
    function shuffle(uint256[] storage arr, uint256 seed) internal {
        for (uint256 i = arr.length; i > 1;) {
            seed = uint256(keccak256(abi.encodePacked(seed)));
            uint256 j = seed % i;
            --i;
            (arr[i], arr[j]) = (arr[j], arr[i]);
        }
    }

    /// @notice Remove element at `index` by swapping with the last element and popping.
    /// @dev O(1) but does not preserve order — fine since the array is shuffled anyway.
    function removeFromList(uint256[] storage arr, uint256 index) internal {
        require(index < arr.length, "Index out of bounds");
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    ////////////////////////////////////////////////////
    /// --- INVARIANT HELPERS
    ////////////////////////////////////////////////////

    /// @notice Sum of all ARM share balances across LPs, ARM escrow, dead address, and frank.
    function sumOfUserShares() public view returns (uint256 total) {
        for (uint256 i; i < lps.length; i++) {
            total += lidoARM.balanceOf(lps[i]);
        }
        total += lidoARM.balanceOf(address(lidoARM));
        total += lidoARM.balanceOf(0x000000000000000000000000000000000000dEaD);
        total += lidoARM.balanceOf(frank);
    }

    /// @notice Sum of assets in all unclaimed withdrawal requests.
    function sumOfUnclaimedRequestAssets() public view returns (uint256 total) {
        uint256 nextIdx = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextIdx; i++) {
            (, bool claimed,, uint128 assets,) = lidoARM.withdrawalRequests(i);
            if (!claimed) total += assets;
        }
    }

    /// @notice Sum of pending (unclaimed) request assets for a specific user.
    function sumOfUserPendingAssets(address user) public view returns (uint256 total) {
        uint256 nextIdx = lidoARM.nextWithdrawalIndex();
        for (uint256 i; i < nextIdx; i++) {
            (address withdrawer, bool claimed,, uint128 assets,) = lidoARM.withdrawalRequests(i);
            if (withdrawer == user && !claimed) total += assets;
        }
    }
}
