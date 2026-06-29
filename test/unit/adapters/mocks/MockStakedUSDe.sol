// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";

// Interfaces
import {UserCooldown} from "contracts/Interfaces.sol";

/// @notice Minimal test double for Ethena's Staked USDe (sUSDe). Implements the subset used by
///         `EthenaAssetAdapter` and `EthenaUnstaker`: ERC4626-style conversions, `cooldownShares`,
///         `cooldownAssets`, `unstake`, and the `cooldowns` view. A configurable `rate`
///         (USDe per sUSDe, scaled to 1e18) exercises non 1:1 conversion paths. The mock must be
///         pre-funded with USDe so `unstake` can pay out cooled-down balances.
contract MockStakedUSDe is ERC20 {
    /// @notice USDe paid out when a cooldown is claimed.
    ERC20 public immutable usde;
    /// @notice Cooldown duration before `unstake` can release USDe.
    uint256 public constant COOLDOWN_DURATION = 7 days;
    /// @notice USDe per sUSDe scaled to 1e18. 1e18 = 1:1.
    uint256 public rate = 1e18;

    /// @notice Active cooldown per account, matching `IStakedUSDe.cooldowns`.
    mapping(address account => UserCooldown) public cooldowns;

    constructor(address _usde) ERC20("Staked USDe", "sUSDe", 18) {
        usde = ERC20(_usde);
    }

    /// @notice Test helper to mint sUSDe shares.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Test helper to set the USDe-per-sUSDe exchange rate (1e18 = 1:1).
    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * rate / 1e18;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return assets * 1e18 / rate;
    }

    /// @dev Burns the caller's sUSDe and records a cooldown for the equivalent USDe.
    function cooldownShares(uint256 shares) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        _burn(msg.sender, shares);
        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp + COOLDOWN_DURATION);
        cooldowns[msg.sender].underlyingAmount += uint152(assets);
    }

    /// @dev Burns the caller's sUSDe matching `assets` and records a cooldown for it.
    function cooldownAssets(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        _burn(msg.sender, shares);
        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp + COOLDOWN_DURATION);
        cooldowns[msg.sender].underlyingAmount += uint152(assets);
    }

    /// @dev Releases the caller's cooled-down USDe to `receiver` once the cooldown has elapsed.
    function unstake(address receiver) external {
        UserCooldown memory cooldown = cooldowns[msg.sender];
        require(block.timestamp >= cooldown.cooldownEnd, "MockSUSDe: invalid cooldown");
        delete cooldowns[msg.sender];
        usde.transfer(receiver, cooldown.underlyingAmount);
    }
}
