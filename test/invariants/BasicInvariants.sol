// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Invariant_Base_Test_} from "./BaseInvariants.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";

// Handlers
import {LpHandler} from "./handlers/LpHandler.sol";
import {SwapHandler} from "./handlers/SwapHandler.sol";
import {DistributionHandler} from "./handlers/DistributionHandler.sol";

contract Invariant_Basic_Test_ is Invariant_Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    //////////////////////////////////////////////////////
    uint256 private constant NUM_LPS = 4;
    uint256 private constant NUM_SWAPS = 3;
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
            lps.push(users[i]);

            // Give them a lot of wETH
            deal(address(weth), users[i], MAX_WETH_PER_USERS);
        }
        for (uint256 i = NUM_LPS; i < NUM_LPS + NUM_SWAPS; i++) {
            swaps.push(users[i]);

            // Give them a lot of wETH and stETH
            deal(address(weth), users[i], MAX_WETH_PER_USERS);
            deal(address(steth), users[i], MAX_STETH_PER_USERS);
        }

        // --- Setup ARM ---
        // Max caps on the total asset that can be deposited
        vm.prank(liquidityProviderController.owner());
        liquidityProviderController.setTotalAssetsCap(type(uint248).max);

        // Disable account cap, unlimited capacity for user to provide liquidity
        vm.prank(liquidityProviderController.owner());
        liquidityProviderController.setAccountCapEnabled(false);

        // --- Handlers ---
        lpHandler = new LpHandler(address(lidoARM), address(weth), lps);
        swapHandler = new SwapHandler(address(lidoARM), address(weth), address(steth), swaps);

        lpHandler.setSelectorWeight(lpHandler.deposit.selector, 10_000); // 100%
        //Todo: swapHandler.setSelectorWeight();

        address[] memory targetContracts = new address[](2);
        targetContracts[0] = address(lpHandler);
        targetContracts[1] = address(swapHandler);

        uint256[] memory weightsDistributorHandler = new uint256[](2);
        weightsDistributorHandler[0] = 10_000; // 100%
        weightsDistributorHandler[1] = 0; // 0%

        address distributionHandler = address(new DistributionHandler(targetContracts, weightsDistributorHandler));

        // All call will be done through the distributor, so we set it as the target contract
        targetContract(distributionHandler);
        //bytes4[] memory selectors = new bytes4[](1);
        //selectors[0] = DistributionHandler.distributorEntryPoint.selector;
        //StdInvariant.FuzzSelector memory fs = StdInvariant.FuzzSelector(distributionHandler, selectors);
        //targetSelector(fs);
    }

    //////////////////////////////////////////////////////
    /// --- INVARIANTS
    //////////////////////////////////////////////////////
    function invariant_A() external {
        //address[] memory tc = targetContracts();
        //require(tc.length == 1, "IBT: INVALID_TARGET_CONTRACTS");
        //emit log_named_address("invariant_A", tc[0]);
        emit log("statefulFuzz_example");
        weth.balanceOf(address(lidoARM));
        assert_invariant_A();
        assert_invariant_B();
    }
}
