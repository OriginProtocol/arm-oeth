// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "../Ownable.sol";
import {IDistributionManager, SiloIncentivesControllerGaugeLike} from "../Interfaces.sol";

/**
 * @title Silo lending market wrapper so rewards can be collected.
 * @author Origin Protocol Inc
 */
contract SiloMarket is Initializable, Ownable {
    /// @notice The address of the asset deposited in the Silo lending market.
    address public immutable asset;
    /// @notice The address of the linked Automated Redemption Manager (ARM).
    address public immutable arm;
    /// @notice The address of the Silo lending market.
    address public immutable market;
    /// @notice The address of the Silo gauge for the lending market.
    address public immutable gauge;

    /// @notice The address of the Harvester contract that collects token rewards.
    address public harvester;

    uint256[49] private _gap;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event HarvesterUpdated(address harvester);
    event CollectedRewards(address[] tokens, uint256[] amounts);

    /// @notice Constructor to set immutable storage variables.
    /// @param _arm The address of the ARM contract.
    /// @param _market The address of the Silo lending market.
    constructor(address _arm, address _market, address _gauge) {
        arm = _arm;
        market = _market;

        asset = IERC4626(_market).asset();

        require(_gauge != address(0), "Gauge not configured");
        gauge = _gauge;
    }

    /// @notice Initialize the proxy contract with the Harvester address.
    /// @param _harvester The address of the Harvester contract.
    function initialize(address _harvester) external initializer {
        _setHarvester(_harvester);
    }

    /// @notice Deposit an exact amount of asset tokens to the Silo lending market
    /// and mint a variable amount of Silo lending market shares to this contract.
    /// @param assets The exact amount of asset tokens to deposit.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @return shares The amount of Silo lending market shares that were minted.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm, "Only ARM can deposit");

        // Transfer liquidity from the ARM to this contract
        IERC20(asset).transferFrom(arm, address(this), assets);

        // Approve the Silo lending market to spend the asset tokens
        IERC20(asset).approve(market, assets);
        // Deposit assets to the Silo lending market from this contract
        // and mint shares to this contract
        shares = IERC4626(market).deposit(assets, address(this));

        emit Deposit(arm, arm, assets, shares);
    }

    /// @notice Get the max amount of asset tokens that can be withdrawn from the Silo lending market
    /// from the Silo lending market shares owned by this contract.
    /// @param owner The owner account has to be the address of the ARM contract.
    /// @return maxAssets The max amount of asset tokens that can be withdrawn.
    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        if (owner != arm) return 0;

        maxAssets = IERC4626(market).maxWithdraw(address(this));
    }

    /// @notice Withdraw an exact amount of asset tokens from the Silo lending market
    /// from the Silo lending market shares owned by this contract.
    /// @param assets The exact amount of asset tokens to withdraw.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return shares The amount of Silo lending market shares that were burnt.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can withdraw");

        // Withdraw assets from the lending market to the ARM
        shares = IERC4626(market).withdraw(assets, arm, address(this));

        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Get the amount of asset tokens that can be received
    /// from burning an exact amount of Silo lending market shares.
    /// @param shares The exact amount of Silo lending market shares to burn.
    /// @return assets The amount of asset tokens that will be received.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        // Preview the amount of assets that can be redeemed for a given number of shares
        assets = IERC4626(market).previewRedeem(shares);
    }

    /// @notice Get the max amount of Silo lending market shares that can be redeemed
    /// from the Silo lending market shares owned by this contract.
    /// @dev This can return a smaller amount than balanceOf() if there is not enough liquidity
    /// in the Silo lending market.
    /// @param owner The owner account has to be the address of the ARM contract.
    /// @return maxShares The max amount of Silo lending market shares in this contract that can be burnt.
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        if (owner != arm) return 0;

        maxShares = IERC4626(market).maxRedeem(address(this));
    }

    /// @notice Burn an exact amount of Silo lending market shares from this contract
    /// and sends the asset tokens to the ARM.
    /// @param shares The exact amount of Silo lending market shares to burn.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return assets The amount of asset tokens that were sent to the ARM.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can redeem");

        // Redeem shares for assets from the lending market to the ARM
        assets = IERC4626(market).redeem(shares, arm, address(this));

        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Claim all reward tokens from the Silo gauge and send them to the Harvester.
    function collectRewards() external returns (address[] memory, uint256[] memory) {
        require(msg.sender == harvester, "Only harvester can collect");

        // Claim and send the rewards to the Harvester
        IDistributionManager.AccruedRewards[] memory data =
            SiloIncentivesControllerGaugeLike(gauge).claimRewards(harvester);

        uint256 length = data.length;
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            tokens[i] = data[i].rewardToken;
            amounts[i] = data[i].amount;
        }

        emit CollectedRewards(tokens, amounts);

        return (tokens, amounts);
    }

    ////////////////////////////////////////////////////
    ///         View Functions
    ////////////////////////////////////////////////////

    /// @notice Get the amount of Silo Market shares owned by this contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return shares The amount of Silo lending market shares owned by this contract.
    function balanceOf(address owner) external view returns (uint256) {
        if (owner != arm) return 0;

        // Get the balance of shares in the lending market
        return IERC4626(market).balanceOf(address(this));
    }

    /// @notice The amount of shares that would exchanged for the amount of assets provided.
    /// @param assets The amount of asset tokens to convert to shares.
    /// @return shares The amount of Silo lending market shares that would be received.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        shares = IERC4626(market).convertToShares(assets);
    }

    /// @notice The amount of assets that would be exchanged for the amount of shares provided.
    /// @param shares The amount of Silo lending market shares to convert to assets.
    /// @return assets The amount of asset tokens that would be received.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = IERC4626(market).convertToAssets(shares);
    }

    ////////////////////////////////////////////////////
    ///         Admin Functions
    ////////////////////////////////////////////////////

    /// @notice The contract owner sets the address of the Harvester contract.
    /// @param _harvester The address of the Harvester contract.
    function setHarvester(address _harvester) external onlyOwner {
        _setHarvester(_harvester);
    }

    function _setHarvester(address _harvester) internal {
        require(_harvester != address(0), "Harvester cannot be zero address");
        require(harvester != _harvester, "Harvester already set");

        harvester = _harvester;

        emit HarvesterUpdated(_harvester);
    }
}
