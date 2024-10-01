// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/Console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice OwnerHandler contract
/// @dev This contract is used to handle all functionnalities restricted to the owner of the ARM.
contract OwnerHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    IERC20 public immutable steth;
    LidoARM public immutable arm;
    address public immutable owner;
    address public immutable operator;
    uint256 public immutable priceScale;
    uint256 public immutable maxDeviation;
    uint256 public immutable minBuyT1; // = 0.99 * 1e36; // We could have use 0, but this is non-sense
    uint256 public immutable maxSellT1; // = 1.01 * 1e36; // We could have use type(uint256).max, but this is non-sense

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_fees;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address _steth, uint256 _minBuyT1, uint256 _maxSellT1) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);
        steth = IERC20(_steth);
        minBuyT1 = _minBuyT1;
        maxSellT1 = _maxSellT1;
        owner = arm.owner();
        operator = arm.operator();
        priceScale = arm.PRICE_SCALE();
        maxDeviation = arm.MAX_PRICE_DEVIATION();
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    /// @notice Set prices for the ARM
    function setPrices(uint256 _seed) external {
        numberOfCalls["ownerHandler.setPrices"]++;

        // Bound prices
        uint256 buyT1 = _bound(_randomize(_seed, "buy"), minBuyT1, priceScale + maxDeviation);
        uint256 sellT1 = _bound(_randomize(_seed, "sell"), max(buyT1, priceScale - maxDeviation), maxSellT1);

        console.log("OwnerHandler.setPrices(%36e,%36e)", buyT1, sellT1);

        // Prank operator instead of owner, to ensure price check
        vm.startPrank(operator);

        // Set prices
        arm.setPrices(buyT1, sellT1);

        // Stop prank
        vm.stopPrank();
    }

    /// @notice Collect fees from the ARM
    /// @dev skipped if there is not enough liquidity to collect fees
    function collectFees() external {
        numberOfCalls["ownerHandler.collectFees"]++;

        if (_estimatedFeesAccrued() > weth.balanceOf(address(arm))) {
            console.log("OwnerHandler.collectFees() - Not enough liquidity to collect fees");
            numberOfCalls["ownerHandler.collectFees.skip"]++;
            return;
        }

        console.log("OwnerHandler.collectFees()");

        // Collect fees
        uint256 fees = arm.collectFees();

        // Update sum of fees
        sum_of_fees += fees;
    }

    //////////////////////////////////////////////////////
    /// --- HELPERS
    //////////////////////////////////////////////////////
    function _estimateRawTotalAssets() internal view returns (uint256) {
        uint256 assets = steth.balanceOf(address(arm)) + weth.balanceOf(address(arm)) + arm.outstandingEther();

        uint256 queuedMem = arm.withdrawsQueued();
        uint256 claimedMem = arm.withdrawsClaimed();

        if (assets + claimedMem < queuedMem) {
            return 0;
        }

        return assets + claimedMem - queuedMem + arm.feesAccrued();
    }

    function _estimatedFeesAccrued() internal view returns (uint256) {
        uint256 newTotalAssets = _estimateRawTotalAssets();

        uint256 lastTotalAssets = arm.lastTotalAssets();
        if (newTotalAssets <= lastTotalAssets) {
            return arm.feesAccrued();
        }

        uint256 assetIncrease = newTotalAssets - lastTotalAssets;
        uint256 newFeesAccrued = (assetIncrease * arm.fee()) / arm.FEE_SCALE();

        return arm.feesAccrued() + newFeesAccrued;
    }
}
