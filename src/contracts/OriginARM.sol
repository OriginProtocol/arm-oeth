// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IOriginVault} from "./Interfaces.sol";

/**
 * @title Automated Redemption Manager (ARM) for Origin Vaults with a single asset. eg OETH, OS and SuperOETH
 * @dev This implementation supports multiple Liquidity Providers (LPs) with single buy and sell prices.
 * It also integrates to a CapManager contract that caps the amount of assets a liquidity provider
 * can deposit and caps the ARM's total assets.
 * A performance fee is also collected on increases in the ARM's total assets.
 * @author Origin Protocol Inc
 */
contract OriginARM is Initializable, AbstractARM {
    /// @notice The address of the Origin Vault
    address public immutable vault;

    /// @notice The amount outstanding in the Origin Vault's withdrawal queue
    uint256 public vaultWithdrawalAmount;

    event RequestOriginWithdrawal(uint256 amount, uint256 requestId);
    event ClaimOriginWithdrawals(uint256[] requestIds, uint256 amountClaimed);

    /// @param _otoken The address of the Origin token. eg OETH or OS
    /// @param _liquidityAsset The address of the liquidity asset. eg WETH or wS
    /// @param _vault The address of the Origin Vault
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    constructor(
        address _otoken,
        address _liquidityAsset,
        address _vault,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem
    ) AbstractARM(_liquidityAsset, _otoken, _liquidityAsset, _claimDelay, _minSharesToRedeem) {
        vault = _vault;

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 liquid assets.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim Lido withdrawals.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 1,500 = 15% performance fee
    /// @param _feeCollector The account that can collect the performance fee
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

    /**
     * @notice Request a withdrawal of oTokens from the Origin Vault.
     * @param amount The amount of oTokens to withdraw from the Origin Vault.
     * @return requestId The ID of the Origin Vault withdrawal request.
     */
    function requestOriginWithdrawal(uint256 amount) external onlyOperatorOrOwner returns (uint256 requestId) {
        (requestId,) = IOriginVault(vault).requestWithdrawal(amount);

        // Increase the outstanding withdrawal amount from the Origin Vault
        vaultWithdrawalAmount += amount;

        emit RequestOriginWithdrawal(amount, requestId);
    }

    /**
     * @notice Claim multiple previously requested withdrawals from the Origin Vault.
     * The caller should check the withdrawal has passed the withdrawal delay
     * and there is enough liquidity in the Vault.
     * @param requestIds The request IDs of the withdrawal requests.
     * @param amountClaimed The total amount claimed across all withdrawal requests.
     */
    function claimOriginWithdrawals(uint256[] calldata requestIds) external returns (uint256 amountClaimed) {
        // Claim the previously requested withdrawals from the Origin Vault.
        (, amountClaimed) = IOriginVault(vault).claimWithdrawals(requestIds);

        // Store the reduced amount outstanding withdrawals from the Origin Vault
        vaultWithdrawalAmount -= amountClaimed;

        emit ClaimOriginWithdrawals(requestIds, amountClaimed);
    }

    /**
     * @dev Calculates the outstanding amount of oTokens in the Origin Vault
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        return vaultWithdrawalAmount;
    }
}
