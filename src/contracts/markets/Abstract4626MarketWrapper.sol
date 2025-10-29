// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "../Ownable.sol";
import {IDistributor} from "../Interfaces.sol";
/**
 * @title Abstract 4626 lending market wrapper
 * @author Origin Protocol Inc
 */

contract Abstract4626MarketWrapper is Initializable, Ownable {
    /// @notice The address of the asset deposited in the lending market.
    address public immutable asset;
    /// @notice The address of the linked Automated Redemption Manager (ARM).
    address public immutable arm;
    /// @notice The address of the 4626 lending market.
    address public immutable market;

    /// @notice The address of the Harvester contract that collects token rewards.
    address public harvester;

    /// @notice The address of the Merkle Distributor contract.
    IDistributor public merkleDistributor;

    uint256[48] private _gap;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event HarvesterUpdated(address harvester);
    event CollectedRewards(address[] tokens, uint256[] amounts);

    /// @notice Constructor to set immutable storage variables.
    /// @param _arm The address of the ARM contract.
    /// @param _market The address of the lending market.
    constructor(address _arm, address _market) {
        arm = _arm;
        market = _market;

        asset = IERC4626(_market).asset();
    }

    /// @notice Initialize the proxy contract with the Harvester address.
    /// @param _harvester The address of the Harvester contract.
    function initialize(address _harvester, address _merkleDistributor) external initializer onlyOwner {
        _setHarvester(_harvester);
        _setMerkleDistributor(_merkleDistributor);
    }

    /// @notice Deposit an exact amount of asset tokens to the lending market
    /// and mint a variable amount of lending market shares to this contract.
    /// @param assets The exact amount of asset tokens to deposit.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @return shares The amount of lending market shares that were minted.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm, "Only ARM can deposit");

        // Transfer liquidity from the ARM to this contract
        IERC20(asset).transferFrom(arm, address(this), assets);

        // Approve the lending market to spend the asset tokens
        IERC20(asset).approve(market, assets);
        // Deposit assets to the lending market from this contract
        // and mint shares to this contract
        shares = IERC4626(market).deposit(assets, address(this));

        emit Deposit(arm, arm, assets, shares);
    }

    /// @notice Get the max amount of asset tokens that can be withdrawn from the lending market
    /// from the lending market shares owned by this contract.
    /// @param owner The owner account has to be the address of the ARM contract.
    /// @return maxAssets The max amount of asset tokens that can be withdrawn.
    function maxWithdraw(address owner) external view returns (uint256 maxAssets) {
        if (owner != arm) return 0;

        maxAssets = IERC4626(market).maxWithdraw(address(this));
    }

    /// @notice Withdraw an exact amount of asset tokens from the lending market
    /// from the lending market shares owned by this contract.
    /// @param assets The exact amount of asset tokens to withdraw.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return shares The amount of lending market shares that were burnt.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can withdraw");

        // Withdraw assets from the lending market to the ARM
        shares = IERC4626(market).withdraw(assets, arm, address(this));

        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Get the amount of asset tokens that can be received
    /// from burning an exact amount of lending market shares.
    /// @param shares The exact amount of lending market shares to burn.
    /// @return assets The amount of asset tokens that will be received.
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        // Preview the amount of assets that can be redeemed for a given number of shares
        assets = IERC4626(market).previewRedeem(shares);
    }

    /// @notice Get the max amount of lending market shares that can be redeemed
    /// from the lending market shares owned by this contract.
    /// @dev This can return a smaller amount than balanceOf() if there is not enough liquidity
    /// in the lending market.
    /// @param owner The owner account has to be the address of the ARM contract.
    /// @return maxShares The max amount of lending market shares in this contract that can be burnt.
    function maxRedeem(address owner) external view returns (uint256 maxShares) {
        if (owner != arm) return 0;

        maxShares = IERC4626(market).maxRedeem(address(this));
    }

    /// @notice Burn an exact amount of lending market shares from this contract
    /// and sends the asset tokens to the ARM.
    /// @param shares The exact amount of lending market shares to burn.
    /// @param receiver The receiver has to be the address of the ARM contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return assets The amount of asset tokens that were sent to the ARM.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(msg.sender == arm && receiver == arm && owner == arm, "Only ARM can redeem");

        // Redeem shares for assets from the lending market to the ARM
        assets = IERC4626(market).redeem(shares, arm, address(this));

        emit Withdraw(arm, arm, arm, assets, shares);
    }

    /// @notice Claim all reward tokens from the market and send them to the Harvester.
    /// @return tokens The address of the reward tokens.
    /// @return amounts The amount of reward tokens to be collected.
    function collectRewards() external returns (address[] memory, uint256[] memory) {
        require(msg.sender == harvester, "Only harvester can collect");

        return _collectRewards();
    }

    /// @notice Collect rewards from the lending market. Override this function to implement the logic.
    /// @return tokens The address of the reward tokens.
    /// @return amounts The amount of reward tokens to be collected.
    function _collectRewards() internal virtual returns (address[] memory, uint256[] memory) {
        revert("Not implemented");
    }

    /// @notice Claim tokens from the Merkle Distributor
    /// @param tokens The addresses of the tokens to claim.
    /// @param amounts The amounts of the tokens to claim.
    /// @param proofs The Merkle proofs for the claims.
    function merkleClaim(address[] calldata tokens, uint256[] calldata amounts, bytes32[][] calldata proofs) external {
        address[] memory users = new address[](1);
        users[0] = address(this);

        merkleDistributor.claim(users, tokens, amounts, proofs);
    }

    ////////////////////////////////////////////////////
    ///         View Functions
    ////////////////////////////////////////////////////

    /// @notice Get the amount of Market shares owned by this contract.
    /// @param owner The owner has to be the address of the ARM contract.
    /// @return shares The amount of lending market shares owned by this contract.
    function balanceOf(address owner) external view returns (uint256) {
        if (owner != arm) return 0;

        // Get the balance of shares in the lending market
        return IERC4626(market).balanceOf(address(this));
    }

    /// @notice The amount of shares that would exchanged for the amount of assets provided.
    /// @param assets The amount of asset tokens to convert to shares.
    /// @return shares The amount of lending market shares that would be received.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        shares = IERC4626(market).convertToShares(assets);
    }

    /// @notice The amount of assets that would be exchanged for the amount of shares provided.
    /// @param shares The amount of lending market shares to convert to assets.
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

    /// @notice The contract owner sets the address of the Merkle Distributor contract.
    /// @param _merkleDistributor The address of the Merkle Distributor contract.
    function setMerkleDistributor(address _merkleDistributor) external onlyOwner {
        _setMerkleDistributor(_merkleDistributor);
    }

    function _setMerkleDistributor(address _merkleDistributor) internal {
        require(_merkleDistributor != address(0), "MerkleDistributor cannot be zero address");
        merkleDistributor = IDistributor(_merkleDistributor);
    }

    /**
     * @dev Helps recovering any tokens accidentally sent to this contract.
     * @param token Token to transfer. 0x0 to transfer Native token.
     * @param to Address to transfer the tokens to.
     * @param amount Amount to transfer. 0 to transfer all balance.
     */
    function transferTokens(address token, address to, uint256 amount) external onlyOwner {
        require(token != asset && token != market, "Cannot transfer asset or market token");
        require(to != address(0), "Invalid address");
        require(to == owner() || to == harvester, "Cannot transfer to non-owner or non-harvester");

        if (address(token) == address(0)) {
            // Move ETH
            amount = amount > 0 ? amount : address(this).balance;
            payable(to).transfer(amount);
            return;
        }

        // Move all balance if amount set to 0
        amount = amount > 0 ? amount : IERC20(token).balanceOf(address(this));

        // Transfer to owner
        IERC20(token).transfer(to, amount);
    }
}
