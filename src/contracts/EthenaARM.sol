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

    uint256 internal _liquidityAmountInCooldown;

    address[] public unstakers;
    uint256 public nextUnstakerIndex;

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

    /**
     * @notice Request a cooldown of USDe from Ethena's Staked USDe (sUSDe) contract.
     * @param baseAmount The amount of base assets (sUSDe) to withdraw.
     */
    function requestBaseWithdrawal(uint256 baseAmount) external onlyOperatorOrOwner {
        uint256 index = nextUnstakerIndex;
        address unstaker;
        if (unstakers.length == 0 || index >= unstakers.length) {
            // Ensure we don't deploy too many unstaker contracts
            require(unstakers.length < 50, "EthenaARM: Too many unstakers");
            // Deploy a new EthenaUnstaker helper contract
            unstaker = address(new EthenaUnstaker(address(this), susde));
            // Add the new unstaker to the array
            unstakers.push(unstaker);
        } else {
            // Reuse an existing unstaker
            unstaker = unstakers[index];
        }
        // Move to the next unstaker for the next request
        ++nextUnstakerIndex;

        // Transfer sUSDe to the helper contract
        susde.transfer(address(unstaker), baseAmount);

        uint256 liquidityAmount = EthenaUnstaker(unstaker).requestUnstake(baseAmount);

        _liquidityAmountInCooldown += liquidityAmount;

        // Emit event for the request
        emit RequestBaseWithdrawal(address(unstaker), baseAmount, liquidityAmount);
    }

    function claimBaseWithdrawals() external {
        // Take the first unstaker in the array
        address unstaker = unstakers[0];

        // Get the cooldown amount for that unstaker
        uint256 cooldownAmount = EthenaUnstaker(unstaker).cooldownAmount();
        require(cooldownAmount > 0, "EthenaARM: No cooldown amount");

        // Shift all the other unstakers to the left
        for (uint256 i; i < unstakers.length - 1; i++) {
            unstakers[i] = unstakers[i + 1];
        }
        // Put the first unstaker at the end and decrease the nextUnstakerIndex
        unstakers[unstakers.length - 1] = unstaker;
        --nextUnstakerIndex;

        // Manage the liquidity amount in cooldown
        if (_liquidityAmountInCooldown < cooldownAmount) {
            _liquidityAmountInCooldown = 0;
        } else {
            _liquidityAmountInCooldown -= cooldownAmount;
        }

        // Claim all the underlying USDe that has cooled down for the unstaker and send to the ARM
        EthenaUnstaker(unstaker).claimUnstake();

        emit ClaimBaseWithdrawals(unstaker, cooldownAmount);
    }

    function _remove(uint256 index) internal {
        for (uint256 i = index; i < unstakers.length - 1; i++) {
            unstakers[i] = unstakers[i + 1];
        }
        unstakers.pop();
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
