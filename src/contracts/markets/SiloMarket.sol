// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "../Ownable.sol";
import {IDistributionManager, SiloIncentivesControllerGaugeLike} from "contracts/Interfaces.sol";

interface ISiloMarket {
    function hookReceiver() external returns (address);
}

interface IHookReceiver {
    function configuredGauges(address shareToken) external returns (address gauge);
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

    function balanceOf(address owner) external view returns (uint256) {
        if (owner != arm) return 0;

        // Get the balance of shares in the lending market
        return IERC4626(market).balanceOf(address(this));
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

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        if (msg.sender != arm) return 0;

        // Preview the amount of assets that can be redeemed for a given number of shares
        assets = IERC4626(market).previewRedeem(shares);
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

    function collectRewards() external returns (address[] memory, uint256[] memory) {
        require(msg.sender == harvester, "Only harvester can collect");

        // Claim and send the rewards to the Harvester
        IDistributionManager.AccruedRewards[] memory data =
            SiloIncentivesControllerGaugeLike(gauge).claimRewards(harvester);

        uint256 length = data.length;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = data[i].rewardToken;
            amounts[i] = data[i].amount;
        }
        return (tokens, amounts);
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
