// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MultiLP} from "./MultiLP.sol";

/**
 * @title Added a performance fee to an ARM with Liquidity Providers (LP)
 * @author Origin Protocol Inc
 */
abstract contract PerformanceFee is MultiLP {
    /// @notice The scale of the performance fee
    /// 10,000 = 100% performance fee
    uint256 public constant FEE_SCALE = 10000;

    /// @notice The account that can collect the performance fee
    address public feeCollector;
    /// @notice Performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 2,000 = 20% performance fee
    /// 500 = 5% performance fee
    uint16 public fee;
    /// @notice The performance fees accrued but not collected.
    /// This is removed from the total assets.
    uint112 public feesAccrued;
    /// @notice The total assets at the last time performance fees were calculated.
    /// This can only go up so is a high watermark.
    uint128 public lastTotalAssets;

    uint256[48] private _gap;

    event FeeCalculated(uint256 newFeesAccrued, uint256 assetIncrease);
    event FeeCollected(address indexed feeCollector, uint256 fee);
    event FeeUpdated(uint256 fee);
    event FeeCollectorUpdated(address indexed newFeeCollector);

    function _initPerformanceFee(uint256 _fee, address _feeCollector) internal {
        // Initialize the last total assets to the current total assets
        // This ensures no performance fee is accrued when the performance fee is calculated when the fee is set
        lastTotalAssets = SafeCast.toUint128(_rawTotalAssets());
        _setFee(_fee);
        _setFeeCollector(_feeCollector);
    }

    /// @dev Calculate the performance fee based on the increase in total assets before
    /// the liquidity asset from the deposit is transferred into the ARM
    function _preDepositHook() internal virtual override {
        _calcFee();
    }

    /// @dev Calculate the performance fee based on the increase in total assets before
    /// the liquidity asset from the redeem is reserved for the ARM withdrawal queue
    function _preWithdrawHook() internal virtual override {
        _calcFee();
    }

    /// @dev Save the new total assets after the deposit and performance fee accrued
    function _postDepositHook(uint256) internal virtual override {
        lastTotalAssets = SafeCast.toUint128(_rawTotalAssets());
    }

    /// @dev Save the new total assets after the withdrawal and performance fee accrued
    function _postWithdrawHook(uint256) internal virtual override {
        lastTotalAssets = SafeCast.toUint128(_rawTotalAssets());
    }

    /// @dev Calculate the performance fee based on the increase in total assets
    /// Needs to be called before any action that changes the liquidity provider shares. eg deposit and redeem
    function _calcFee() internal {
        uint256 newTotalAssets = _rawTotalAssets();

        // Do not accrued a performance fee if the total assets has decreased
        if (newTotalAssets <= lastTotalAssets) return;

        uint256 assetIncrease = newTotalAssets - lastTotalAssets;
        uint256 newFeesAccrued = (assetIncrease * fee) / FEE_SCALE;

        // Save the new accrued fees back to storage
        feesAccrued = SafeCast.toUint112(feesAccrued + newFeesAccrued);
        // Save the new total assets back to storage less the new accrued fees.
        // This is be updated again in the post deposit and post withdraw hooks to include
        // the assets deposited or withdrawn
        lastTotalAssets = SafeCast.toUint128(newTotalAssets - newFeesAccrued);

        emit FeeCalculated(newFeesAccrued, assetIncrease);
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 totalAssetsBeforeFees = _rawTotalAssets();

        // If the total assets have decreased, then we don't charge a performance fee
        if (totalAssetsBeforeFees <= lastTotalAssets) return totalAssetsBeforeFees;

        // Calculate the increase in assets since the last time fees were calculated
        uint256 assetIncrease = totalAssetsBeforeFees - lastTotalAssets;

        // Calculate the performance fee and remove from the total assets before new fees are removed
        return totalAssetsBeforeFees - ((assetIncrease * fee) / FEE_SCALE);
    }

    /// @dev Calculate the total assets in the ARM, external withdrawal queue,
    /// less liquidity assets reserved for the ARM's withdrawal queue and past accrued fees.
    /// The accrued fees are from the last time fees were calculated.
    function _rawTotalAssets() internal view returns (uint256) {
        return super.totalAssets() - feesAccrued;
    }

    /// @notice Owner sets the performance fee on increased assets
    /// @param _fee The performance fee measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Owner sets the account/contract that receives the performance fee
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE, "ARM: fee too high");

        // Calculate fees up to this point using the old fee
        _calcFee();

        fee = SafeCast.toUint16(_fee);

        emit FeeUpdated(_fee);
    }

    function _setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "ARM: invalid fee collector");

        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Transfer accrued performance fees to the fee collector
    /// This requires enough liquidity assets in the ARM to cover the accrued fees.
    function collectFees() external returns (uint256 fees) {
        // Accrued all fees up to this point
        _calcFee();

        // Read the updated accrued fees from storage
        fees = feesAccrued;
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        // Reset the accrued fees in storage
        feesAccrued = 0;

        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }
}
