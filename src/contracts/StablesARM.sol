// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";

/**
 * @title Stablecoin Automated Redemption Manager (ARM)
 * @notice ARM using USDC as the liquidity asset and supported stablecoins as base assets.
 * @author Origin Protocol Inc
 */
contract StablesARM is Initializable, AbstractARM {
    /// @param _usdc The address of USDC.
    /// @param _claimDelay Delay in seconds before an LP redeem request can be claimed.
    /// @param _minSharesToRedeem Minimum active market shares to redeem when pulling liquidity.
    /// @param _allocateThreshold Minimum excess liquidity delta before allocation deposits into a market.
    constructor(address _usdc, uint256 _claimDelay, uint256 _minSharesToRedeem, int256 _allocateThreshold)
        AbstractARM(_usdc, _claimDelay, _minSharesToRedeem, _allocateThreshold)
    {
        _disableInitializers();
    }

    /// @notice Initialize storage for the proxy.
    /// @dev The initializer caller must approve this ARM proxy to transfer 1,000 base units of USDC.
    /// @param _name LP token name.
    /// @param _symbol LP token symbol.
    /// @param _operator Account allowed to run operator-only actions.
    /// @param _fee Fee on discounted base-asset buy swaps measured in basis points.
    /// 10,000 = 100% fee
    /// 500 = 5% fee
    /// @param _feeCollector Account or contract that receives accrued swap fees.
    /// @param _capManager Optional CapManager contract. Use address(0) to disable caps.
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
}
