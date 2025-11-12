// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {EthenaUnstaker} from "./EthenaUnstaker.sol";
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
    /// @notice The maximum number of unstaker contracts that can be used per day of the week
    uint8 public constant MAX_REQUESTS_PER_DAY = 10;

    uint256 internal _liquidityAmountInCooldown;

    /// @notice Array of unstaker helper contracts
    /// Each day of the week has MAX_REQUESTS_PER_DAY unstakers assigned to it
    address[70] internal unstakers;
    /// @notice Mapping of day of the week to last used unstaker index
    mapping(uint8 => uint8) internal lastUsedUnstakerIndex;

    event RequestBaseWithdrawal(address indexed unstaker, uint256 baseAmount, uint256 liquidityAmount);
    event ClaimBaseWithdrawals(address indexed unstaker, uint256 liquidityAmount);

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

    /// @notice Request a cooldown of USDe from Ethena's Staked USDe (sUSDe) contract.
    /// @dev Uses a different unstaker contract each time to allow multiple cooldowns in parallel.
    ///      There is a limit of MAX_REQUESTS_PER_DAY unstakers that can be used per day of the week.
    /// @param baseAmount The amount of staked USDe (sUSDe) to withdraw.
    function requestBaseWithdrawal(uint256 baseAmount) external onlyOperatorOrOwner {
        // Find which day of the week it is (0 = Thursday, 6 = Wednesday)
        uint256 day = block.timestamp / 1 days % 7;
        // Get last used unstaker for the day
        uint8 index = lastUsedUnstakerIndex[day];

        // Cycle through unstakers for the day
        // If never interacted with, start at the beginning of the day's unstakers
        // If at the end of the day's unstakers, wrap around to the beginning
        // Otherwise, just move to the next unstaker
        if (index == 0 || index == (day + 1) * MAX_REQUESTS_PER_DAY - 1) {
            index = uint8(day * MAX_REQUESTS_PER_DAY);
        } else {
            ++index;
        }

        // Ensure unstaker isn't used during last 7 days
        address unstaker = unstakers[index];
        require(unstaker != address(0), "EthenaARM: Invalid unstaker");
        uint256 amount = EthenaUnstaker(unstaker).cooldownAmount();
        require(amount == 0, "EthenaARM: Unstaker in cooldown");

        // Update last used unstaker for the day
        lastUsedUnstakerIndex[day] = index;

        // Transfer sUSDe to the helper contract
        susde.transfer(unstaker, baseAmount);

        uint256 liquidityAmount = EthenaUnstaker(unstaker).requestUnstake(baseAmount);

        _liquidityAmountInCooldown += liquidityAmount;

        // Emit event for the request
        emit RequestBaseWithdrawal(unstaker, baseAmount, liquidityAmount);
    }

    /**
     * @notice Claim all the USDe that is now claimable from the Staked USDe contract.
     * Reverts with `InvalidCooldown` from the Staked USDe contract if the cooldown period has not yet passed.
     */
    function claimBaseWithdrawals(address unstaker) external {
        uint256 cooldownAmount = EthenaUnstaker(unstaker).cooldownAmount();
        require(cooldownAmount > 0, "EthenaARM: No cooldown amount");

        if (_liquidityAmountInCooldown < cooldownAmount) {
            _liquidityAmountInCooldown = 0;
        } else {
            _liquidityAmountInCooldown -= cooldownAmount;
        }

        // Claim all the underlying USDe that has cooled down for the unstaker and send to the ARM
        EthenaUnstaker(unstaker).claimUnstake();

        emit ClaimBaseWithdrawals(unstaker, cooldownAmount);
    }

    /**
     * @dev Gets the total amount of USDe waiting to be claimed from the Staked USDe contract.
     * This can be for many different cooldowns.
     * This can be either in the cooldown period or ready to be claimed.
     */
    function _externalWithdrawQueue() internal view override returns (uint256) {
        return _liquidityAmountInCooldown;
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
