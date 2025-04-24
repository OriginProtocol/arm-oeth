// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "../Ownable.sol";

interface ISiloMarket {
    function hookReceiver() external returns (address);
}

interface IHookReceiver {
    function configuredGauges(address shareToken) external returns (address gauge);
}

interface IGauge {
    struct AccruedRewards {
        uint256 amount;
        bytes32 programId;
        address rewardToken;
    }

    function claimRewards(address _to) external returns (AccruedRewards[] memory accruedRewards);
}

/**
 * @title ARM strategy for the Silo lending market.
 * @author Origin Protocol Inc
 */
contract SiloMarket is Initializable, Ownable {
    address public immutable asset;
    /// @notice The address of the linked Automated Redemption Manager (ARM).
    address public immutable arm;
    address public immutable market;
    address public immutable gauge;

    /// @notice The address of the harvester contract that collects token rewards.
    address public harvester;

    uint256[49] private _gap;

    event HarvesterUpdated(address harvester);

    constructor(address _arm, address _market) {
        arm = _arm;
        market = _market;

        asset = IERC4626(_market).asset();

        // Get gauge for the Silo lending market
        address hookReceiver = ISiloMarket(_market).hookReceiver();
        gauge = IHookReceiver(hookReceiver).configuredGauges(_market);
        require(gauge != address(0), "Gauge not configured");
    }

    function initialize(address _harvester) external initializer {
        _setHarvester(_harvester);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm, "Only ARM can deposit");

        // Transfer liquidity from the ARM to this contract
        IERC20(asset).transferFrom(arm, address(this), assets);

        IERC20(asset).approve(market, assets);
        shares = IERC4626(market).deposit(assets, address(this));
    }

    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        if (owner != arm) return 0;

        maxAssets = IERC4626(market).maxWithdraw(address(this));
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can withdraw");

        // Withdraw assets from the lending market to the ARM
        shares = IERC4626(market).withdraw(assets, arm, address(this));
    }

    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        if (owner != arm) return 0;

        maxShares = IERC4626(market).maxRedeem(address(this));
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can redeem");

        // Redeem shares for assets from the lending market to the ARM
        assets = IERC4626(market).redeem(shares, arm, address(this));
    }

    function collectRewards() external {
        require(msg.sender == harvester, "Only harvester can collect");

        // Claim and send the rewards to the Harvester
        IGauge(gauge).claimRewards(harvester);
    }

    ////////////////////////////////////////////////////
    ///         Admin Functions
    ////////////////////////////////////////////////////

    /// @notice
    function setHarvester(address _harvester) external onlyOwner {
        _setHarvester(_harvester);
    }

    function _setHarvester(address _harvester) internal {
        require(harvester != _harvester, "Harvester already set");

        harvester = _harvester;

        emit HarvesterUpdated(_harvester);
    }
}
