// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Invariant_Base_Test_} from "./BaseInvariants.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";
import {OwnerHandler} from "./handlers/OwnerHandler.sol";
import {DistributionHandler} from "./handlers/DistributionHandler.sol";

contract Invariant_Basic_Test_ is Invariant_Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    //////////////////////////////////////////////////////
    uint256 private constant NUM_LPS = 4;
    uint256 private constant NUM_SWAPS = 3;
    uint256 private constant MIN_BUY_T1 = 0.98 * 1e36; // We could have use 0, but this is non-sense
    uint256 private constant MAX_SELL_T1 = 1.02 * 1e36; // We could have use type(uint256).max, but this is non-sense
    uint256 public constant MAX_WETH_PER_USERS = 10_000_000 ether; // 10M
    uint256 public constant MAX_STETH_PER_USERS = 10_000_000 ether; // 10M, actual total supply

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        // --- Create Users ---
        // In this configuration, an user is either a LP or a Swap, but not both.
        require(NUM_LPS + NUM_SWAPS <= users.length, "IBT: NOT_ENOUGH_USERS");
        for (uint256 i; i < NUM_LPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            lps.push(user);

            // Give them a lot of wETH
            deal(address(weth), user, MAX_WETH_PER_USERS);
        }
        for (uint256 i = NUM_LPS; i < NUM_LPS + NUM_SWAPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            swaps.push(user);

            // Give them a lot of wETH and stETH
            deal(address(weth), user, MAX_WETH_PER_USERS);
            deal(address(steth), user, MAX_STETH_PER_USERS);
        }

        // --- Setup ARM ---
        // Max caps on the total asset that can be deposited
        vm.prank(liquidityProviderController.owner());
        liquidityProviderController.setTotalAssetsCap(type(uint248).max);

        // Disable account cap, unlimited capacity for user to provide liquidity
        vm.prank(liquidityProviderController.owner());
        liquidityProviderController.setAccountCapEnabled(false);

        // Set prices
        // Todo: use handler to set prices "randomly", but fixed at almost 1:1 atm.
        vm.prank(lidoARM.owner());
        lidoARM.setPrices(1e36 - 1, 1e36 + 1);

        // --- Handlers ---
        lpHandler = new LpHandler(address(lidoARM), address(weth), lps);
        swapHandler = new SwapHandler(address(lidoARM), address(weth), address(steth), swaps);
        ownerHandler = new OwnerHandler(address(lidoARM), address(weth), address(steth), MIN_BUY_T1, MAX_SELL_T1);

        lpHandler.setSelectorWeight(lpHandler.deposit.selector, 5_000); // 50%
        lpHandler.setSelectorWeight(lpHandler.requestRedeem.selector, 2_500); // 25%
        lpHandler.setSelectorWeight(lpHandler.claimRedeem.selector, 2_500); // 25%
        swapHandler.setSelectorWeight(swapHandler.swapExactTokensForTokens.selector, 5_000); // 50%
        swapHandler.setSelectorWeight(swapHandler.swapTokensForExactTokens.selector, 5_000); // 50%
        ownerHandler.setSelectorWeight(ownerHandler.setPrices.selector, 5_000); // 50%
        ownerHandler.setSelectorWeight(ownerHandler.collectFees.selector, 5_000); // 50%

        address[] memory targetContracts = new address[](3);
        targetContracts[0] = address(lpHandler);
        targetContracts[1] = address(swapHandler);
        targetContracts[2] = address(ownerHandler);

        uint256[] memory weightsDistributorHandler = new uint256[](3);
        weightsDistributorHandler[0] = 4_500; // 45%
        weightsDistributorHandler[1] = 4_500; // 45%
        weightsDistributorHandler[2] = 1_000; // 10%

        address distributionHandler = address(new DistributionHandler(targetContracts, weightsDistributorHandler));

        // All call will be done through the distributor, so we set it as the target contract
        targetContract(distributionHandler);
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariant_A() external {
        assert_invariant_A();
        assert_invariant_B();
    }
}
