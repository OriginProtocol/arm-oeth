// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IOethARM {
    function token0() external returns (address);
    function token1() external returns (address);
    function owner() external returns (address);
    function swapExactTokensForTokens(
        IERC20,
        IERC20,
        uint256,
        uint256,
        address
    ) external;
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external returns (uint256[] memory);
    function swapTokensForExactTokens(
        IERC20,
        IERC20,
        uint256,
        uint256,
        address
    ) external;
    function swapTokensForExactTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external returns (uint256[] memory);
    function setOwner(address newOwner) external;
    function transferToken(address token, address to, uint256 amount) external;

    // From OethLiquidityManager
    function requestWithdrawal(
        uint256 amount
    ) external returns (uint256 requestId, uint256 queued);
    function claimWithdrawal(uint256 requestId) external;
    function claimWithdrawals(uint256[] calldata requestIds) external;
}

interface IOETHVault {
    function requestWithdrawal(
        uint256 amount
    ) external returns (uint256 requestId, uint256 queued);

    function claimWithdrawal(
        uint256 requestId
    ) external returns (uint256 amount);

    function claimWithdrawals(
        uint256[] memory requestIds
    ) external returns (uint256[] memory amounts, uint256 totalAmount);

    function addWithdrawalQueueLiquidity() external;
}
