// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

interface IOethARM {
    function token0() external returns (address);
    function token1() external returns (address);
    function owner() external returns (address);

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param to Recipient of the output tokens.
     */
    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external;

    /**
     * @notice Uniswap V2 Router compatible interface. Swaps an exact amount of
     * input tokens for as many output tokens as possible.
     * msg.sender should have already given the ARM contract an allowance of
     * at least amountIn on the input token.
     *
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens that must be received for the transaction not to revert.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param inToken Input token.
     * @param outToken Output token.
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param to Recipient of the output tokens.
     */
    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external;

    /**
     * @notice Uniswap V2 Router compatible interface. Receive an exact amount of
     * output tokens for as few input tokens as possible.
     * msg.sender should have already given the router an allowance of
     * at least amountInMax on the input token.
     *
     * @param amountOut The amount of output tokens to receive.
     * @param amountInMax The maximum amount of input tokens that can be required before the transaction reverts.
     * @param path The input and output token addresses.
     * @param to Recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert.
     * @return amounts The input and output token amounts.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function setOwner(address newOwner) external;
    function transferToken(address token, address to, uint256 amount) external;

    // From OethLiquidityManager
    function requestWithdrawal(uint256 amount) external returns (uint256 requestId, uint256 queued);
    function claimWithdrawal(uint256 requestId) external;
    function claimWithdrawals(uint256[] calldata requestIds) external;
}

interface ILiquidityProviderARM is IERC20 {
    function previewDeposit(uint256 assets) external returns (uint256 shares);
    function deposit(uint256 assets) external returns (uint256 shares);

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

interface LegacyAMM {
    function transferToken(address tokenOut, address to, uint256 amount) external;
}

interface IOETHVault {
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

    function claimDelay() external view returns (uint256);
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
