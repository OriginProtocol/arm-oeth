// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Solmate
import {Owned} from "@solmate/auth/Owned.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";

// Interfaces
import {UserCooldown} from "contracts/Interfaces.sol";

contract MockSUSDE is ERC4626, Owned {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////
    address public immutable SILO;
    uint256 public immutable VESTING_DURATION;

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////
    uint256 public vestingAmount;
    uint256 public lastDistribution;
    uint256 public cooldownDuration;
    mapping(address => UserCooldown) public cooldowns;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////
    event CooldownSet(uint256 oldDuration, uint256 newDuration);
    event RewardReceived(uint256 amount);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address _underlying, address _governor)
        ERC4626(ERC20(_underlying), "Staked USDe", "sUSDe")
        Owned(_governor)
    {
        SILO = address(new MockSilo(asset));
        VESTING_DURATION = 8 hours;
    }

    //////////////////////////////////////////////////////
    /// --- VIEWS
    //////////////////////////////////////////////////////
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) - getUnvestedAmount();
    }

    function getUnvestedAmount() public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - lastDistribution;

        if (timeSinceLastDistribution >= VESTING_DURATION) {
            return 0;
        }

        uint256 deltaT;
        unchecked {
            deltaT = VESTING_DURATION - timeSinceLastDistribution;
        }
        return (vestingAmount * deltaT) / VESTING_DURATION;
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    function unstake(address receiver) external {
        UserCooldown storage cooldown = cooldowns[msg.sender];
        uint256 assets = cooldown.underlyingAmount;

        if (block.timestamp >= cooldown.cooldownEnd) {
            delete cooldowns[msg.sender];

            MockSilo(SILO).withdraw(receiver, assets);
        } else {
            revert("SUSDE: Invalid cooldown");
        }
    }

    function cooldownAssets(uint256 assets) external returns (uint256 shares) {
        if (assets > maxWithdraw(msg.sender)) revert("SUSDE: Excessive withdraw amount");

        shares = previewWithdraw(assets);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp + cooldownDuration);
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        withdraw(assets, SILO, msg.sender);
    }

    function cooldownShares(uint256 shares) external returns (uint256 assets) {
        if (shares > maxRedeem(msg.sender)) revert("SUSDE: Excessive redeem amount");

        assets = previewRedeem(shares);

        cooldowns[msg.sender].cooldownEnd = uint104(block.timestamp + cooldownDuration);
        cooldowns[msg.sender].underlyingAmount += uint152(assets);

        withdraw(assets, SILO, msg.sender);
    }

    //////////////////////////////////////////////////////
    /// --- ADMIN FUNCTIONS
    //////////////////////////////////////////////////////
    function setCooldownDuration(uint256 _cooldownDuration) external onlyOwner {
        require(_cooldownDuration <= 30 days, "SUSDE: cooldown too long");
        emit CooldownSet(cooldownDuration, _cooldownDuration);
        cooldownDuration = _cooldownDuration;
    }

    function transferInRewards(uint256 amount) external onlyOwner {
        require(amount != 0, "SUSDE: amount zero");

        // Ensure previous vesting period is complete before starting a new one
        // _updateVestingAmount(amount) in original contract
        require(getUnvestedAmount() == 0, "SUSDE: previous vesting not complete");
        vestingAmount += amount;
        lastDistribution = block.timestamp;

        asset.transferFrom(msg.sender, address(this), amount);
        emit RewardReceived(amount);
    }
}

contract MockSilo is Owned {
    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////
    ERC20 public immutable _USDE;

    /////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(ERC20 _usde) Owned(msg.sender) {
        _USDE = _usde;
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    function withdraw(address to, uint256 amount) external onlyOwner {
        _USDE.transfer(to, amount);
    }
}
