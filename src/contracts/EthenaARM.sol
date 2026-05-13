// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {AbstractARM} from "./AbstractARM.sol";
import {IERC20, IStakedUSDe} from "./Interfaces.sol";

/**
 * @title Ethena sUSDe/USDe Automated Redemption Manager (ARM)
 * @author Origin Protocol Inc
 */
contract EthenaARM is Initializable, AbstractARM {
    /// @notice The delay before a new unstake request can be made
    uint256 public constant DELAY_REQUEST = 30 minutes;
    /// @notice The maximum number of unstaker helper contracts
    uint8 public constant MAX_UNSTAKERS = 42;
    /// @notice The address of Ethena's synthetic dollar token (USDe)
    IERC20 public immutable usde;
    /// @notice The address of Ethena's staked synthetic dollar token (sUSDe)
    IStakedUSDe public immutable susde;

    /// @dev Deprecated cooldown amount retained for storage layout compatibility.
    uint256 internal _deprecatedLiquidityAmountInCooldown;
    /// @dev Deprecated unstaker helper array retained for storage layout compatibility.
    address[MAX_UNSTAKERS] internal _deprecatedUnstakers;
    /// @dev Deprecated unstaker index retained for storage layout compatibility.
    uint8 internal _deprecatedNextUnstakerIndex;
    /// @dev Deprecated request timestamp retained for storage layout compatibility.
    uint32 internal _deprecatedLastRequestTimestamp;

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
    ) AbstractARM(_usde, _claimDelay, _minSharesToRedeem, _allocateThreshold) {
        usde = IERC20(_usde);
        susde = IStakedUSDe(_susde);

        _disableInitializers();
    }

    /// @notice Initialize the storage variables stored in the proxy contract.
    /// The deployer that calls initialize has to approve the ARM's proxy contract to transfer 1e12 USDe.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _operator The address of the account that can request and claim withdrawals.
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

    /// @notice Deprecated legacy cooldown amount view.
    /// @dev New protocol cooldown state is owned by `EthenaAssetAdapter`.
    /// @return The deprecated stored cooldown amount.
    function liquidityAmountInCooldown() external view returns (uint256) {
        return _deprecatedLiquidityAmountInCooldown;
    }

    /// @notice Deprecated legacy unstaker helper view.
    /// @dev New unstaker helpers are owned by `EthenaAssetAdapter`.
    /// @param index Unstaker index.
    /// @return The deprecated unstaker address.
    function unstakers(uint256 index) external view returns (address) {
        return _deprecatedUnstakers[index];
    }

    /// @notice Deprecated legacy unstaker index view.
    /// @dev New unstaker rotation state is owned by `EthenaAssetAdapter`.
    /// @return The deprecated next unstaker index.
    function nextUnstakerIndex() external view returns (uint8) {
        return _deprecatedNextUnstakerIndex;
    }

    /// @notice Deprecated legacy request timestamp view.
    /// @dev New request timing state is owned by `EthenaAssetAdapter`.
    /// @return The deprecated last request timestamp.
    function lastRequestTimestamp() external view returns (uint32) {
        return _deprecatedLastRequestTimestamp;
    }
}
