// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);

    event Transfer(address indexed from, address indexed to, uint256 value);
}

interface ILiquidityProviderARM is IERC20 {
    function previewDeposit(uint256 assets) external returns (uint256 shares);
    function deposit(uint256 assets) external returns (uint256 shares);
    function deposit(uint256 assets, address liquidityProvider) external returns (uint256 shares);

    function previewRedeem(uint256 shares) external returns (uint256 assets);
    function requestRedeem(uint256 shares) external returns (uint256 requestId, uint256 assets);
    function claimRedeem(uint256 requestId) external returns (uint256 assets);

    function totalAssets() external returns (uint256 assets);
    function convertToShares(uint256 assets) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external returns (uint256 assets);
    function lastTotalAssets() external returns (uint256 assets);
}

interface ICapManager {
    function postDepositHook(address liquidityProvider, uint256 assets) external;
}

/**
 * @title Async Redeem Adapter interface
 * @notice Minimal ARM-facing async redeem interface for supported base assets.
 * @dev Implementations may be true vaults or vault-shaped adapters. In this interface, `shares`
 * refer to the configured base-asset redeemable unit, not ARM LP shares. `asset()` is the ARM's
 * liquidity asset and redeemed assets are always returned to `msg.sender`.
 */
interface IAsyncRedeemAdapter {
    /// @notice Returns the liquidity asset address used by the ARM.
    function asset() external view returns (address);

    /// @notice Converts base-asset shares into liquidity assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assetsOut);

    /// @notice Converts liquidity assets into base-asset shares.
    function convertToShares(uint256 assetsIn) external view returns (uint256 sharesOut);

    /**
     * @notice Request asynchronous redemption of adapter shares owned by the ARM.
     * @param shares Amount of adapter shares to redeem asynchronously.
     * @return requestedShares Amount of shares accepted for redemption.
     */
    function requestRedeem(uint256 shares) external returns (uint256 requestedShares);

    /**
     * @notice Returns the aggregate amount of adapter shares currently claimable.
     * @return claimableShares Amount of adapter shares that can currently be redeemed.
     */
    function claimableRedeem() external view returns (uint256 claimableShares);

    /**
     * @notice Claims previously requested redemptions into the liquidity asset for `msg.sender`.
     * @param shares Amount of previously requested shares to claim.
     * @return assetsOut Amount of liquidity assets returned to `msg.sender`.
     */
    function redeem(uint256 shares) external returns (uint256 assetsOut);
}

/**
 * @title Lido async redeem adapter interface
 * @notice Extension used by `LidoARM` to interoperate with Lido queue request IDs directly.
 */
interface ILidoAsyncRedeemAdapter is IAsyncRedeemAdapter {
    function requestWithdrawal(uint256 shares) external returns (uint256 requestId);
    function claimWithdrawal(uint256[] calldata requestIds, uint256[] calldata hintIds)
        external
        returns (uint256 assetsOut, uint256 sharesClaimed);
    function requestAssets(uint256 requestId) external view returns (uint256 assets);
}

interface LegacyAMM {
    function transferToken(address tokenOut, address to, uint256 amount) external;
}

interface IOriginVault {
    function mint(address _asset, uint256 _amount, uint256 _minimumOusdAmount) external;

    function redeem(uint256 _amount, uint256 _minimumUnitAmount) external;

    function requestWithdrawal(uint256 amount) external returns (uint256 requestId, uint256 queued);

    function claimWithdrawal(uint256 requestId) external returns (uint256 amount);

    function claimWithdrawals(uint256[] memory requestIds)
        external
        returns (uint256[] memory amounts, uint256 totalAmount);

    function addWithdrawalQueueLiquidity() external;

    function setMaxSupplyDiff(uint256 _maxSupplyDiff) external;

    function governor() external view returns (address);

    function dripper() external view returns (address);

    function withdrawalQueueMetadata()
        external
        view
        returns (uint128 queued, uint128 claimable, uint128 claimed, uint128 nextWithdrawalIndex);

    function withdrawalRequests(uint256 requestId)
        external
        view
        returns (address withdrawer, bool claimed, uint40 timestamp, uint128 amount, uint128 queued);

    function withdrawalClaimDelay() external view returns (uint256);
}

interface IGovernance {
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function state(uint256 proposalId) external view returns (ProposalState);

    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    function proposalEta(uint256 proposalId) external view returns (uint256);

    function votingDelay() external view returns (uint256);

    function castVote(uint256 proposalId, uint8 support) external returns (uint256 balance);

    function queue(uint256 proposalId) external;

    function execute(uint256 proposalId) external;
}

interface IWETH is IERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface ISTETH is IERC20 {
    event Submitted(address indexed sender, uint256 amount, address referral);

    // function() external payable;
    function submit(address _referral) external payable returns (uint256);
}

interface IWstETH is IERC20 {
    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount);
    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount);
    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256 stETHAmount);
    function getWstETHByStETH(uint256 stETHAmount) external view returns (uint256 wstETHAmount);
}

interface IStETHWithdrawal {
    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed requestor,
        address indexed owner,
        uint256 amountOfStETH,
        uint256 amountOfShares
    );
    event WithdrawalsFinalized(
        uint256 indexed from, uint256 indexed to, uint256 amountOfETHLocked, uint256 sharesToBurn, uint256 timestamp
    );
    event WithdrawalClaimed(
        uint256 indexed requestId, address indexed owner, address indexed receiver, uint256 amountOfETH
    );

    struct WithdrawalRequestStatus {
        /// @notice stETH token amount that was locked on withdrawal queue for this request
        uint256 amountOfStETH;
        /// @notice amount of stETH shares locked on withdrawal queue for this request
        uint256 amountOfShares;
        /// @notice address that can claim or transfer this request
        address owner;
        /// @notice timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice true, if request is finalized
        bool isFinalized;
        /// @notice true, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    function transferFrom(address _from, address _to, uint256 _requestId) external;
    function ownerOf(uint256 _requestId) external returns (address);
    function requestWithdrawals(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);
    function getLastCheckpointIndex() external view returns (uint256);
    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds);
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function getWithdrawalRequests(address _owner) external view returns (uint256[] memory requestsIds);
    function getLastRequestId() external view returns (uint256);
}

interface IOracle {
    function price(address asset) external view returns (uint256 price);
}

interface IHarvestable {
    function collectRewards() external returns (address[] memory tokens, uint256[] memory rewards);
}

interface IMagpieRouter {
    function swapWithMagpieSignature(bytes calldata) external payable returns (uint256 amountOut);
}

library DistributionTypes {
    struct IncentivesProgramCreationInput {
        string name;
        address rewardToken;
        uint104 emissionPerSecond;
        uint40 distributionEnd;
    }
}

library IDistributionManager {
    struct AccruedRewards {
        uint256 amount;
        bytes32 programId;
        address rewardToken;
    }
}

interface SiloIncentivesControllerGaugeLike {
    function claimRewards(address _to) external returns (IDistributionManager.AccruedRewards[] memory accruedRewards);
    function createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput)
        external;
    function getAllProgramsNames() external view returns (string[] memory programsNames);
    function getRewardsBalance(address _user, string memory _programName)
        external
        view
        returns (uint256 unclaimedRewards);
    function incentivesPrograms(bytes32)
        external
        view
        returns (
            uint256 index,
            address rewardToken,
            uint104 emissionPerSecond,
            uint40 lastUpdateTimestamp,
            uint40 distributionEnd
        );
    function owner() external view returns (address);
}

interface IEETHWithdrawal {
    function requestWithdraw(address receipient, uint256 amount) external returns (uint256 requestId);
}

interface IEETHWithdrawalNFT {
    function finalizeRequests(uint256 requestId) external;
    function claimWithdraw(uint256 requestId) external;
    function batchClaimWithdraw(uint256[] calldata requestIds) external;
}

interface IEETHRedemptionManager {
    function redeemEEth(uint256 amount, address receiver) external;
    function redeemWeEth(uint256 amount, address receiver) external;
    function canRedeem(uint256 amount) external view returns (bool);
}

interface IDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}

// Ethena Interfaces

struct UserCooldown {
    uint104 cooldownEnd;
    uint152 underlyingAmount;
}

interface IStakedUSDe is IERC4626 {
    // Errors //
    /// @notice Error emitted when the shares amount to redeem is greater than the shares balance of the owner
    error ExcessiveRedeemAmount();
    /// @notice Error emitted when the shares amount to withdraw is greater than the shares balance of the owner
    error ExcessiveWithdrawAmount();

    function cooldownAssets(uint256 assets) external returns (uint256 shares);

    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function unstake(address receiver) external;

    function cooldowns(address receiver) external view returns (UserCooldown memory);

    function getUnvestedAmount() external view returns (uint256);

    function lastDistributionTimestamp() external view returns (uint256);

    function transferInRewards(uint256 amount) external;
}
