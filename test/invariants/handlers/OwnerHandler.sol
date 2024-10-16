// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

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
    uint256 public immutable maxFees;
    address public immutable operator;
    uint256 public immutable minBuyT1;
    uint256 public immutable maxSellT1;
    uint256 public immutable priceScale;
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12;

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_fees;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address _steth, uint256 _minBuyT1, uint256 _maxSellT1, uint256 _maxFees) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);
        steth = IERC20(_steth);
        maxFees = _maxFees;
        minBuyT1 = _minBuyT1;
        maxSellT1 = _maxSellT1;
        owner = arm.owner();
        operator = arm.operator();
        priceScale = arm.PRICE_SCALE();
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    /// @notice Set prices for the ARM
    function setPrices(uint256 _seed) external {
        numberOfCalls["ownerHandler.setPrices"]++;

        // Bound prices
        uint256 crossPrice = arm.crossPrice();
        uint256 buyT1 = _bound(_randomize(_seed, "buy"), minBuyT1, crossPrice - 1);
        uint256 sellT1 = _bound(_randomize(_seed, "sell"), crossPrice, maxSellT1);

        console.log("OwnerHandler.setPrices(%36e,%36e)", buyT1, sellT1);

        // Prank owner instead of operator to bypass price check
        vm.startPrank(owner);

        // Set prices
        arm.setPrices(buyT1, sellT1);

        // Stop prank
        vm.stopPrank();
    }

    /// @notice Set cross price for the ARM
    function setCrossPrice(uint256 _seed) external {
        numberOfCalls["ownerHandler.setCrossPrice"]++;

        // Bound prices
        uint256 currentPrice = arm.crossPrice();
        // Condition 1: 1e36 - 20e32 <= newCrossPrice <= 1e36
        // Condition 2: buyPrice < newCrossPrice <= sellPrice
        // <=>
        // max(buyPrice, 1e36 - 20e32) < newCrossPrice <= min(sellPrice, 1e36)
        uint256 sellPrice = priceScale * priceScale / arm.traderate0();
        uint256 buyPrice = arm.traderate1();
        uint256 newCrossPrice =
            _bound(_seed, max(priceScale - arm.MAX_CROSS_PRICE_DEVIATION(), buyPrice) + 1, min(priceScale, sellPrice));

        if (newCrossPrice < currentPrice && steth.balanceOf(address(arm)) >= MIN_TOTAL_SUPPLY) {
            console.log("OwnerHandler.setCrossPrice() - Skipping price decrease");
            numberOfCalls["ownerHandler.setCrossPrice.skip"]++;
            return;
        }

        console.log("OwnerHandler.setCrossPrice(%36e)", newCrossPrice);

        // Prank owner instead of operator to bypass price check
        vm.startPrank(owner);

        // Set prices
        arm.setCrossPrice(newCrossPrice);

        // Stop prank
        vm.stopPrank();
    }

    /// @notice Set fees for the ARM
    function setFees(uint256 _seed) external {
        numberOfCalls["ownerHandler.setFees"]++;

        uint256 feeAccrued = arm.feesAccrued();
        if (!enoughLiquidityAvailable(feeAccrued) || feeAccrued > weth.balanceOf(address(arm))) {
            console.log("OwnerHandler.setFees() - Not enough liquidity to collect fees");
            numberOfCalls["ownerHandler.setFees.skip"]++;
            return;
        }

        uint256 fee = _bound(_seed, 0, maxFees);
        console.log("OwnerHandler.setFees(%2e)", fee);

        // Prank owner
        vm.startPrank(owner);

        // Set fees
        arm.setFee(fee);

        // Stop prank
        vm.stopPrank();

        // Update sum of fees
        sum_of_fees += feeAccrued;
    }

    /// @notice Collect fees from the ARM
    /// @dev skipped if there is not enough liquidity to collect fees
    function collectFees(uint256) external {
        numberOfCalls["ownerHandler.collectFees"]++;

        uint256 feeAccrued = arm.feesAccrued();
        if (!enoughLiquidityAvailable(feeAccrued) || feeAccrued > weth.balanceOf(address(arm))) {
            console.log("OwnerHandler.collectFees() - Not enough liquidity to collect fees");
            numberOfCalls["ownerHandler.collectFees.skip"]++;
            return;
        }

        console.log("OwnerHandler.collectFees(%18e)", feeAccrued);

        // Collect fees
        uint256 fees = arm.collectFees();
        require(feeAccrued == fees, "OwnerHandler.collectFees() - Fees collected do not match fees accrued");

        // Update sum of fees
        sum_of_fees += fees;
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    function enoughLiquidityAvailable(uint256 amount) public view returns (bool) {
        // The amount of liquidity assets (WETH) that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = arm.withdrawsQueued() - arm.withdrawsClaimed();

        // Save gas on an external balanceOf call if there are no outstanding withdrawals
        if (outstandingWithdrawals == 0) return true;

        return amount + outstandingWithdrawals <= weth.balanceOf(address(arm));
    }
}
