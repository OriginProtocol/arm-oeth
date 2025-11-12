// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IStakedUSDe, UserCooldown} from "./Interfaces.sol";

/**
 * @title Ethena sUSDe/USDe Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
contract EthenaARM is Initializable, AbstractARM {
    /// @notice The address of Ethena's synthetic dollar token (USDe)
    IERC20 public immutable usde;
    /// @notice The address of Ethena's staked synthetic dollar token (sUSDe)
    IStakedUSDe public immutable susde;

    event RequestBaseWithdrawal(uint256 amount);
    event ClaimBaseWithdrawals(uint256 liquidityAmountClaimed);

    /// @param _usde The address of Ethena's synthetic dollar token (USDe)
    /// @param _susde The address of Ethena's staked synthetic dollar token (sUSDe)
    /// @param _claimDelay The delay in seconds before a user can claim a redeem from the request
    /// @param _minSharesToRedeem The minimum amount of shares to redeem from the active lending market
    /// @param _allocateThreshold The minimum amount of liquidity assets in excess of the ARM buffer before
    /// the ARM can allocate to a active lending market.
    constructor(
        address _usde,
        address _susde,
        uint256 _claimDelay,
        uint256 _minSharesToRedeem,
        int256 _allocateThreshold
    ) AbstractARM(_usde, _susde, _usde, _claimDelay, _minSharesToRedeem, _allocateThreshold) {
        usde = IERC20(_usde);
        susde = IStakedUSDe(_susde);

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 USDe.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim withdrawals.
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
     * @notice Request a cooldown of USDe from Ethena's Staked USDe (sUSDe) contract.
     * @param baseAmount The amount of base assets (sUSDe) to withdraw.
     */
    function requestBaseWithdrawal(uint256 baseAmount) external onlyOperatorOrOwner {
        // For now put in a restriction that only one request can be outstanding at a time.
        // TODO replace this with a pool of helper contracts that can manage multiple cooldowns in parallel.
        UserCooldown memory cooldown = susde.cooldowns(address(this));
        require(cooldown.underlyingAmount == 0, "EthenaARM: Existing cooldown");

        // Request an unstaked from Ethena's staked USDe (sUSDe) contract
        susde.cooldownShares(baseAmount);

        // Emit event for the request
        emit RequestBaseWithdrawal(baseAmount);
    }

    /**
     * @notice Claim all the USDe that is now claimable from the Staked USDe contract.
     * Reverts with `InvalidCooldown` from the Staked USDe contract if the cooldown period has not yet passed.
     */
    function claimBaseWithdrawals() external {
        UserCooldown memory cooldown = susde.cooldowns(address(this));

        susde.unstake(address(this));

        emit ClaimBaseWithdrawals(cooldown.underlyingAmount);
    }

    /**
     * @dev Gets the amount of USDe waiting to be claimed from the Staked USDe contract.
     * This can be either in the cooldown period or ready to be claimed.
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        UserCooldown memory cooldown = susde.cooldowns(address(this));

        return cooldown.underlyingAmount;
    }

    /// @dev Convert between base asset (sUSDe) and liquidity asset (USDe).
    /// ERC-4626 convert functions are used as the preview functions can return a
    /// smaller amount if the contract is paused or has high utilization.
    /// Although that is not the case the the sUSDe implementation.
    /// @param token The address of the token to convert from. sUSDe or USDe.
    /// @param amount The amount of the token to convert from.
    /// @return The converted to amount.
    function _convert(address token, uint256 amount) internal view override returns (uint256) {
        if (token == baseAsset) {
            // Convert base asset (sUSDe) to liquidity asset (USDe)
            return susde.convertToAssets(amount);
        } else if (token == liquidityAsset) {
            // Convert liquidity asset (USDe) to base asset (sUSDe)
            return susde.convertToShares(amount);
        } else {
            revert("EthenaARM: Invalid token");
        }
    }
}
