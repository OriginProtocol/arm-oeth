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
    /// @notice The maximum performance fee that can be set
    /// 10,000 = 100% performance fee
    uint256 public constant MAX_FEE = 10000;

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

    event FeeCalculated(uint256 newFeesAccrued, uint256 totalAssets);
    event FeeCollected(address indexed feeCollector, uint256 fee);
    event FeeUpdated(uint256 fee);
    event FeeCollectorUpdated(address indexed newFeeCollector);

    function _initPerformanceFee(uint256 _fee, address _feeCollector) internal {
        _setFee(_fee);
        _setFeeCollector(_feeCollector);
    }

    function _preDepositHook() internal virtual override {
        _calcFee();
    }

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

        // Only collected a performance fee if the total assets have increased
        if (newTotalAssets > lastTotalAssets) {
            uint256 newAssets = newTotalAssets - lastTotalAssets;
            uint256 newFeesAccrued = (newAssets * fee) / MAX_FEE;

            // Save the new values back to storage
            feesAccrued = SafeCast.toUint112(feesAccrued + newFeesAccrued);

            emit FeeCalculated(newFeesAccrued, newTotalAssets);
        }
    }

    function totalAssets() public view virtual override returns (uint256) {
        // valuing both assets 1:1
        uint256 totalAssetsBeforeFees = _rawTotalAssets();

        // Calculate new fees from increased assets
        uint256 newAssets = totalAssetsBeforeFees > lastTotalAssets ? totalAssetsBeforeFees - lastTotalAssets : 0;
        uint256 accruedFees = (newAssets * fee) / MAX_FEE;

        return totalAssetsBeforeFees - accruedFees;
    }

    /// @dev Calculate the total assets in the contract, withdrawal queue less accrued fees
    function _rawTotalAssets() internal view returns (uint256) {
        return
            token0.balanceOf(address(this)) + token1.balanceOf(address(this)) + _assetsInWithdrawQueue() - feesAccrued;
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
        require(_fee <= MAX_FEE, "ARM: fee too high");

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
    function collectFees() external returns (uint256 fees) {
        require(msg.sender == feeCollector, "ARM: not fee collector");

        // Calculate any new fees up to this point
        _calcFee();

        fees = feesAccrued;
        require(fees <= IERC20(liquidityToken).balanceOf(address(this)), "ARM: insufficient liquidity");

        // Reset fees collected in storage
        feesAccrued = 0;

        IERC20(liquidityToken).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }
}
