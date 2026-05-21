// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";

/**
 * @title Lido (stETH) Automated Redemption Manager (ARM)
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a CapManager contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A fee is accrued on discounted base-asset buy swaps.
 * @author Origin Protocol Inc
 */
contract LidoARM is Initializable, AbstractARM {
    error LegacyLidoWithdrawalsPending();

    /// @dev Deprecated queue amount retained for storage layout compatibility.
    uint256 internal _deprecatedLidoWithdrawalQueueAmount;

    /// @dev Deprecated withdrawal request mapping retained for storage layout compatibility.
    uint256 internal _deprecatedLidoWithdrawalRequests;

    /// @param _weth The address of the WETH token
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    /// @param _minSharesToRedeem The minimum amount of shares to redeem from the active lending market
    /// @param _allocateThreshold The minimum amount of liquidity assets in excess of the ARM buffer before
    /// the ARM can allocate to a active lending market.
    constructor(address _weth, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold)
        AbstractARM(_weth, _claimDelay, _minSharesToRedeem, _allocateThreshold)
    {
        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The fee accrued on discounted base-asset buy swaps measured in basis points (1/100th of a percent).
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    /// @param _feeCollector The account that can collect the accrued swap fee
    /// @param _capManager The address of the CapManager contract
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _operator,
        uint256 _fee,
        address _feeCollector,
        address _capManager
    ) external initializer {
        _initARM(_operator, _name, _symbol, _fee, _feeCollector, _capManager);
    }

    /// @dev Revert if legacy Lido withdrawal requests are still outstanding.
    function _checkNoLegacyWithdrawQueue() internal view override {
        if (_deprecatedLidoWithdrawalQueueAmount != 0) revert LegacyLidoWithdrawalsPending();
    }

    /// @notice This payable method is necessary for receiving ETH claimed from the Lido withdrawal queue.
    receive() external payable {}
}
