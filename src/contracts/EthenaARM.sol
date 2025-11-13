// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {EthenaUnstaker} from "./EthenaUnstaker.sol";
import {IERC20, IStakedUSDe} from "./Interfaces.sol";

/**
 * @title Ethena sUSDe/USDe Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
contract EthenaARM is Initializable, AbstractARM {
    /// @notice The delay before a new unstake request can be made
    uint256 public constant DELAY_REQUEST = 3 hours;
    /// @notice The maximum number of unstaker helper contracts
    uint8 public constant MAX_UNSTAKERS = 42;
    /// @notice The address of Ethena's synthetic dollar token (USDe)
    IERC20 public immutable usde;
    /// @notice The address of Ethena's staked synthetic dollar token (sUSDe)
    IStakedUSDe public immutable susde;

    /// @notice The total amount of liquidity asset (USDe) currently in cooldown
    uint256 internal _liquidityAmountInCooldown;
    /// @notice Array of unstaker helper contracts
    address[MAX_UNSTAKERS] internal unstakers;
    /// @notice The index of the next unstaker to use in the round robin
    uint8 public nextUnstakerIndex;
    /// @notice The timestamp of the last request made
    uint32 public lastRequestTimestamp;

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
    /// @dev Uses a round robin to select the next unstaker helper contract.
    /// @param baseAmount The amount of staked USDe (sUSDe) to withdraw.
    function requestBaseWithdrawal(uint256 baseAmount) external onlyOperatorOrOwner {
        require(block.timestamp >= lastRequestTimestamp + DELAY_REQUEST, "EthenaARM: Request delay not passed");
        lastRequestTimestamp = uint32(block.timestamp);

        // Get the next unstaker contract in the round robin
        address unstaker = unstakers[nextUnstakerIndex];
        // Ensure unstaker is valid
        require(unstaker != address(0), "EthenaARM: Invalid unstaker");

        // Ensure unstaker isn't used during last 7 days
        uint256 amount = EthenaUnstaker(unstaker).cooldownAmount();
        require(amount == 0, "EthenaARM: Unstaker in cooldown");

        // Update last used unstaker for the day. Safe to cast as there is a maximum of MAX_UNSTAKERS
        nextUnstakerIndex = uint8((nextUnstakerIndex + 1) % MAX_UNSTAKERS);

        // Transfer sUSDe to the helper contract
        susde.transfer(unstaker, baseAmount);

        uint256 liquidityAmount = EthenaUnstaker(unstaker).requestUnstake(baseAmount);

        _liquidityAmountInCooldown += liquidityAmount;

        // Emit event for the request
        emit RequestBaseWithdrawal(unstaker, baseAmount, liquidityAmount);
    }

    /// @notice Claim all the USDe that is now claimable from the Staked USDe contract.
    /// Reverts with `InvalidCooldown` from the Staked USDe contract if the cooldown period has not yet passed.
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

    /// @dev Gets the total amount of USDe waiting to be claimed from the Staked USDe contract.
    /// This can be for many different cooldowns.
    /// This can be either in the cooldown period or ready to be claimed.
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

    /// @notice Set the unstaker helper contracts.
    /// @param _unstakers The array of unstaker contract addresses.
    function setUnstakers(address[MAX_UNSTAKERS] calldata _unstakers) external onlyOwner {
        require(_unstakers.length == MAX_UNSTAKERS, "EthenaARM: Invalid unstakers length");
        unstakers = _unstakers;
    }
}
