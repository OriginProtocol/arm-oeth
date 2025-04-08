// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Ownable} from "./OwnableOperable.sol";
import {IERC20, IStrategy} from "./Interfaces.sol";

/**
 * @title Automated Redemption Manager (ARM) Vault
 * @author Origin Protocol Inc
 */
contract ARMVault is Ownable, ERC20Upgradeable {
    ////////////////////////////////////////////////////
    ///                 Constants
    ////////////////////////////////////////////////////

    /// @dev The amount of shares that are minted to a dead address on initialization
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;
    /// @dev The address with no known private key that the initial shares are minted to
    address internal constant DEAD_ACCOUNT = 0x000000000000000000000000000000000000dEaD;
    /// @notice The scale of the performance fee
    /// 10,000 = 100% performance fee
    uint256 public constant FEE_SCALE = 10000;

    ////////////////////////////////////////////////////
    ///             Immutable Variables
    ////////////////////////////////////////////////////

    /// @notice The address of the asset that is used to add and remove liquidity. eg WETH
    /// This is also the quote asset when the prices are set.
    /// eg the stETH/WETH price has a base asset of stETH and quote asset of WETH.
    address public immutable liquidityAsset;
    /// @notice The delay before a withdrawal request can be claimed in seconds. eg 600 is 10 minutes.
    uint256 public immutable claimDelay;

    ////////////////////////////////////////////////////
    ///             Storage Variables
    ////////////////////////////////////////////////////

    /// @notice list of ARM strategies
    address[] public armStrategies;
    /// @notice list of liquid strategies. eg money markets
    address[] public liquidStrategies;

    /// @notice Cumulative total of all withdrawal requests including the ones that have already been claimed.
    uint128 public withdrawsQueued;
    /// @notice Total of all the withdrawal requests that have been claimed.
    uint128 public withdrawsClaimed;
    /// @notice Index of the next withdrawal request starting at 0.
    uint256 public nextWithdrawalIndex;

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        // When the withdrawal can be claimed
        uint40 claimTimestamp;
        // Amount of liquidity assets to withdraw. eg WETH
        uint128 assets;
        // Cumulative total of all withdrawal requests including this one when the redeem request was made.
        uint128 queued;
    }

    /// @notice Mapping of withdrawal request indices to the user withdrawal request data.
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    /// @notice Performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 2,000 = 20% performance fee
    /// 500 = 5% performance fee
    uint16 public fee;
    /// @notice The available assets the last time the performance fees were collected and adjusted
    /// for liquidity assets (WETH) deposited and redeemed.
    /// This can be negative if there were asset gains and then all the liquidity providers redeemed.
    int128 public lastAvailableAssets;
    /// @notice The account or contract that can collect the performance fee.
    address public feeCollector;

    uint256[45] private _gap;

    ////////////////////////////////////////////////////
    ///                 Events
    ////////////////////////////////////////////////////

    event Deposit(address indexed owner, uint256 assets, uint256 shares);
    event RedeemRequested(
        address indexed withdrawer, uint256 indexed requestId, uint256 assets, uint256 queued, uint256 claimTimestamp
    );
    event RedeemClaimed(address indexed withdrawer, uint256 indexed requestId, uint256 assets);
    event FeeCollected(address indexed feeCollector, uint256 fee);
    event FeeUpdated(uint256 fee);
    event FeeCollectorUpdated(address indexed newFeeCollector);

    constructor(address _liquidityAsset, uint256 _claimDelay) {
        require(IERC20(_liquidityAsset).decimals() == 18);

        claimDelay = _claimDelay;

        _setOwner(address(0)); // Revoke owner for implementation contract at deployment
    }

    /// @notice Initialize the contract.
    /// The deployer that calls initialize has to approve the this ARM's proxy contract to transfer 1e12 WETH.
    /// @param _name The name of the liquidity provider (LP) token.
    /// @param _symbol The symbol of the liquidity provider (LP) token.
    /// @param _fee The performance fee that is collected by the feeCollector measured in basis points (1/100th of a percent).
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    /// @param _feeCollector The account that can collect the performance fee
    function _initARM(string calldata _name, string calldata _symbol, uint256 _fee, address _feeCollector) internal {
        __ERC20_init(_name, _symbol);

        // Transfer a small bit of liquidity from the initializer to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        // mint a small amount of shares to a dead account so the total supply can never be zero
        // This avoids donation attacks when there are no assets in the ARM contract
        _mint(DEAD_ACCOUNT, MIN_TOTAL_SUPPLY);

        // Initialize the last available assets to the current available assets
        // This ensures no performance fee is accrued when the performance fee is calculated when the fee is set
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(_availableAssets()));
        _setFee(_fee);
        _setFeeCollector(_feeCollector);
    }

    ////////////////////////////////////////////////////
    ///         Liquidity Provider Functions
    ////////////////////////////////////////////////////

    /// @notice Preview the amount of shares that would be minted for a given amount of assets
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that would be minted
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    /// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
    /// The caller needs to have approved the contract to transfer the assets.
    /// @param assets The amount of liquidity assets to deposit
    /// @return shares The amount of shares that were minted
    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = _deposit(assets, msg.sender);
    }

    /// @notice deposit liquidity assets in exchange for liquidity provider (LP) shares.
    /// Funds will be transferred from msg.sender.
    /// @param assets The amount of liquidity assets to deposit
    /// @param receiver The address that will receive shares.
    /// @return shares The amount of shares that were minted
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = _deposit(assets, receiver);
    }

    /// @dev Internal logic for depositing liquidity assets in exchange for liquidity provider (LP) shares.
    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        // Calculate the amount of shares to mint after the performance fees have been accrued
        // which reduces the available assets, and before new assets are deposited.
        shares = convertToShares(assets);

        // Add the deposited assets to the last available assets
        lastAvailableAssets += SafeCast.toInt128(SafeCast.toInt256(assets));

        // Transfer the liquidity asset from the sender to this contract
        IERC20(liquidityAsset).transferFrom(msg.sender, address(this), assets);

        // mint shares
        _mint(receiver, shares);

        emit Deposit(receiver, assets, shares);
    }

    /// @notice Preview the amount of assets that would be received for burning a given amount of shares
    /// @param shares The amount of shares to burn
    /// @return assets The amount of liquidity assets that would be received
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /// @notice Request to redeem liquidity provider shares for liquidity assets
    /// @param shares The amount of shares the redeemer wants to burn for liquidity assets
    /// @return requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that will be claimable by the redeemer
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets) {
        // Calculate the amount of assets to transfer to the redeemer
        assets = convertToAssets(shares);

        requestId = nextWithdrawalIndex;
        // Store the next withdrawal request
        nextWithdrawalIndex = requestId + 1;

        uint128 queued = SafeCast.toUint128(withdrawsQueued + assets);
        // Store the updated queued amount which reserves liquidity assets (WETH) in the withdrawal queue
        withdrawsQueued = queued;

        uint40 claimTimestamp = uint40(block.timestamp + claimDelay);

        // Store requests
        withdrawalRequests[requestId] = WithdrawalRequest({
            withdrawer: msg.sender,
            claimed: false,
            claimTimestamp: claimTimestamp,
            assets: SafeCast.toUint128(assets),
            queued: queued
        });

        // burn redeemer's shares
        _burn(msg.sender, shares);

        // Remove the redeemed assets from the last available assets
        lastAvailableAssets -= SafeCast.toInt128(SafeCast.toInt256(assets));

        emit RedeemRequested(msg.sender, requestId, assets, queued, claimTimestamp);
    }

    /// @notice Claim liquidity assets from a previous withdrawal request after the claim delay has passed
    /// @param requestId The index of the withdrawal request
    /// @return assets The amount of liquidity assets that were transferred to the redeemer
    function claimRedeem(uint256 requestId) external returns (uint256 assets) {
        // Load the struct from storage into memory
        WithdrawalRequest memory request = withdrawalRequests[requestId];

        require(request.claimTimestamp <= block.timestamp, "Claim delay not met");
        // Is there enough liquidity to claim this request?
        require(request.queued <= claimable(), "Queue pending liquidity");
        require(request.withdrawer == msg.sender, "Not requester");
        require(request.claimed == false, "Already claimed");

        assets = request.assets;

        // Store the request as claimed
        withdrawalRequests[requestId].claimed = true;
        // Store the updated claimed amount
        withdrawsClaimed += SafeCast.toUint128(assets);

        // transfer the liquidity asset to the withdrawer
        IERC20(liquidityAsset).transfer(msg.sender, assets);

        emit RedeemClaimed(msg.sender, requestId, assets);
    }

    /// @notice Used to work out if an ARM's withdrawal request can be claimed.
    /// If the withdrawal request's `queued` amount is less than the returned `claimable` amount, then it can be claimed.
    function claimable() public view returns (uint256) {
        return withdrawsClaimed + IERC20(liquidityAsset).balanceOf(address(this));
    }

    /// @dev Checks if there is enough liquidity asset (WETH) in the ARM is not reserved for the withdrawal queue.
    // That is, the amount of liquidity assets (WETH) that is available to be swapped or collected as fees.
    // If no outstanding withdrawals, no check will be done of the amount against the balance of the liquidity assets in the ARM.
    // This is a gas optimization for swaps.
    // The ARM can swap out liquidity assets (WETH) that has been accrued from the performance fee for the fee collector.
    // There is no liquidity guarantee for the fee collector. If there is not enough liquidity assets (WETH) in
    // the ARM to collect the accrued fees, then the fee collector will have to wait until there is enough liquidity assets.
    function _requireLiquidityAvailable(uint256 amount) internal view {
        // The amount of liquidity assets (WETH) that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // Save gas on an external balanceOf call if there are no outstanding withdrawals
        if (outstandingWithdrawals == 0) return;

        // If there is not enough liquidity assets in the ARM to cover the outstanding withdrawals and the amount
        require(
            amount + outstandingWithdrawals <= IERC20(liquidityAsset).balanceOf(address(this)),
            "ARM: Insufficient liquidity"
        );
    }

    /// @notice The total amount of assets in the ARM and external withdrawal queue,
    /// less the liquidity assets reserved for the ARM's withdrawal queue and accrued fees.
    function totalAssets() public view virtual returns (uint256) {
        (uint256 fees, uint256 newAvailableAssets) = _feesAccrued();

        // total assets should only go up from the initial deposit amount that is burnt
        // but in case of something unforeseen, return MIN_TOTAL_SUPPLY if fees is
        // greater than or equal the available assets
        if (fees >= newAvailableAssets) return MIN_TOTAL_SUPPLY;

        // Remove the performance fee from the available assets
        return newAvailableAssets - fees;
    }

    /// @notice The total amount of liquid and base assets in the ARM Vault and strategies.
    /// @dev Calculate the liquidity assets in the ARM Vault,
    /// base assets in each ARM strategy which includes the external withdrawal queue,
    /// less liquidity assets reserved for the ARM Vault's withdrawal queue.
    /// This does not exclude any accrued performance fees.
    function _availableAssets() internal view returns (uint256) {
        uint256 assets = IERC20(liquidityAsset).balanceOf(address(this));

        uint256 armStrategiesLength = armStrategies.length;
        for (uint256 i = 0; i < armStrategiesLength; i++) {
            assets += IStrategy(armStrategies[i]).checkBalance();
        }

        uint256 liquidStrategiesLength = liquidStrategies.length;
        for (uint256 i = 0; i < liquidStrategiesLength; i++) {
            assets += IStrategy(liquidStrategies[i]).checkBalance();
        }

        // The amount of liquidity assets that are still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // If the ARM becomes insolvent enough that the available assets in the ARM Vault and ARM Strategies
        // is less than the outstanding withdrawals and accrued fees.
        if (assets < outstandingWithdrawals) {
            return 0;
        }

        // Need to remove the liquidity assets that have been reserved for the withdrawal queue
        return assets - outstandingWithdrawals;
    }

    function availableLiquidity() external view returns (uint256) {
        uint256 assets = IERC20(liquidityAsset).balanceOf(address(this));

        // The amount of liquidity assets (WETH) that is still to be claimed in the withdrawal queue
        uint256 outstandingWithdrawals = withdrawsQueued - withdrawsClaimed;

        // If there is currently not enough liquidity available in the ARM Vault to cover the withdrawals
        if (assets < outstandingWithdrawals) {
            return 0;
        }

        // Need to remove the liquidity assets that have been reserved for the withdrawal queue
        return assets - outstandingWithdrawals;
    }

    /// @notice Calculates the amount of shares for a given amount of liquidity assets
    /// @dev Total assets can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        shares = assets * totalSupply() / totalAssets();
    }

    /// @notice Calculates the amount of liquidity assets for a given amount of shares
    /// @dev Total supply can't be zero. The lowest it can be is MIN_TOTAL_SUPPLY
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        assets = (shares * totalAssets()) / totalSupply();
    }

    ////////////////////////////////////////////////////
    ///         Performance Fee Functions
    ////////////////////////////////////////////////////

    /// @notice Owner sets the performance fee on increased assets
    /// @param _fee The performance fee measured in basis points (1/100th of a percent)
    /// 10,000 = 100% performance fee
    /// 500 = 5% performance fee
    /// The max allowed performance fee is 50% (5000)
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    /// @notice Owner sets the account/contract that receives the performance fee
    function setFeeCollector(address _feeCollector) external onlyOwner {
        _setFeeCollector(_feeCollector);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee <= FEE_SCALE / 2, "ARM: fee too high");

        // Collect any performance fees up to this point using the old fee
        collectFees();

        fee = SafeCast.toUint16(_fee);

        emit FeeUpdated(_fee);
    }

    function _setFeeCollector(address _feeCollector) internal {
        require(_feeCollector != address(0), "ARM: invalid fee collector");

        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(_feeCollector);
    }

    /// @notice Transfer accrued performance fees to the fee collector
    /// This requires enough liquidity assets (WETH) in the ARM that are not reserved
    /// for the withdrawal queue to cover the accrued fees.
    function collectFees() public returns (uint256 fees) {
        uint256 newAvailableAssets;
        // Accrue any performance fees up to this point
        (fees, newAvailableAssets) = _feesAccrued();

        // Save the new available assets back to storage less the collected fees.
        // This needs to be done before the fees == 0 check to cover the scenario where the performance fee is zero
        // and there has been an increase in assets since the last time fees were collected.
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));

        if (fees == 0) return 0;

        // Check there is enough liquidity assets (WETH) that are not reserved for the withdrawal queue
        // to cover the fee being collected.
        _requireLiquidityAvailable(fees);
        // _requireLiquidityAvailable() is optimized for swaps so will not revert if there are no outstanding withdrawals.
        // We need to check there is enough liquidity assets to cover the fees being collect from this ARM contract.
        // We could try the transfer and let it revert if there are not enough assets, but there is no error message with
        // a failed WETH transfer so we spend the extra gas to check and give a meaningful error message.
        require(fees <= IERC20(liquidityAsset).balanceOf(address(this)), "ARM: insufficient liquidity");

        IERC20(liquidityAsset).transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

    /// @notice Calculates the performance fees accrued since the last time fees were collected
    function feesAccrued() external view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function _feesAccrued() internal view returns (uint256 fees, uint256 newAvailableAssets) {
        newAvailableAssets = _availableAssets();

        // Calculate the increase in assets since the last time fees were calculated
        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;

        // Do not accrued a performance fee if the available assets has decreased
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
    }
}
