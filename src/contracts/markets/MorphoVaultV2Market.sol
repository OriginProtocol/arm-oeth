// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MorphoMarket} from "./MorphoMarket.sol";

/**
 * @title Morpho Vault V2 lending market wrapper.
 * @notice Adapts a Morpho Vault V2 position for an ARM.
 * @dev Morpho Vault V2 deliberately returns zero from all ERC-4626 max functions because gates,
 *      caps, and downstream liquidity make a useful revert-free bound impossible. This wrapper
 *      overrides only maxWithdraw and maxRedeem because the ARM uses them to account for claimable
 *      liquidity and to pull funds back from its active market.
 *
 *      The returned values are the full economic position, not guaranteed currently withdrawable
 *      amounts. They can therefore be greater than the vault's downstream liquidity, and a later
 *      withdraw or redeem can revert. The wrapper does not bypass Vault V2 gates, allocation caps,
 *      pauses, or liquidity constraints.
 *
 *      This wrapper assumes the Vault V2's adapters report losses through realAssets(), allowing
 *      Vault V2 totalAssets() and convertToAssets() to decrease. It must not be used for a Vault V2
 *      whose position is valued through a MorphoVaultV1Adapter over a MetaMorpho V1.1 vault:
 *      MetaMorpho V1.1 includes lostAssets in its share price, so such bad debt is not reported to
 *      Vault V2. The intended integration is a Vault V2 using direct, loss-aware adapters such as
 *      MorphoMarketV1AdapterV2. This is an ongoing integration assumption, not an immutable Vault
 *      V2 property: a curator may add or replace adapters after the wrapper is deployed. Operators
 *      must monitor adapter changes and deactivate this market before a MorphoVaultV1Adapter over
 *      MetaMorpho V1.1 becomes effective.
 *
 *      Vault V2 snapshots its exchange rate on the first accrual in each transaction. A downstream
 *      loss occurring later in that same transaction is reflected from the next transaction, not by
 *      subsequent convertToAssets calls in the transaction that realized the loss.
 * @author Origin Protocol Inc
 */
contract MorphoVaultV2Market is MorphoMarket {
    /// @param _arm The address of the ARM contract.
    /// @param _market The address of the Morpho Vault V2 market.
    constructor(address _arm, address _market) MorphoMarket(_arm, _market) {}

    /// @notice Get the economic asset value of this wrapper's full vault-share position.
    /// @dev This intentionally does not promise that `maxAssets` can be withdrawn without reverting.
    /// Morpho Vault V2 provides no non-zero revert-free liquidity bound, while the ARM requires a
    /// non-zero value for claimable-liquidity and allocation accounting. `convertToAssets` includes
    /// losses reported by the Vault V2 adapters, subject to Vault V2's per-transaction rate snapshot.
    /// @param owner The owner account, which must be the linked ARM.
    /// @return maxAssets The full economic position value in underlying assets, not a liquidity guarantee.
    function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {
        if (owner != arm) return 0;

        uint256 shares = IERC4626(market).balanceOf(address(this));
        maxAssets = IERC4626(market).convertToAssets(shares);
    }

    /// @notice Get this wrapper's full vault-share position.
    /// @dev This intentionally reports every share even when downstream liquidity, gates, or pauses
    /// would prevent redeeming all shares in the current transaction. A later redeem can revert.
    /// @param owner The owner account, which must be the linked ARM.
    /// @return maxShares The full vault-share balance, not a redeemability guarantee.
    function maxRedeem(address owner) external view override returns (uint256 maxShares) {
        if (owner != arm) return 0;

        maxShares = IERC4626(market).balanceOf(address(this));
    }
}
