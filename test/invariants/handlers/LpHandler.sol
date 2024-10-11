// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {console} from "forge-std/console.sol";

// Handlers
import {BaseHandler} from "./BaseHandler.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {LidoARM} from "contracts/LidoARM.sol";

/// @notice LpHandler contract
/// @dev This contract is used to handle all functionnalities related to providing liquidity in the ARM.
contract LpHandler is BaseHandler {
    ////////////////////////////////////////////////////
    /// --- CONSTANTS && IMMUTABLES
    ////////////////////////////////////////////////////
    IERC20 public immutable weth;
    LidoARM public immutable arm;

    ////////////////////////////////////////////////////
    /// --- VARIABLES
    ////////////////////////////////////////////////////
    address[] public lps; // Users that provide liquidity
    mapping(address user => uint256[] ids) public requests;

    ////////////////////////////////////////////////////
    /// --- VARIABLES FOR INVARIANT ASSERTIONS
    ////////////////////////////////////////////////////
    uint256 public sum_of_deposits;
    uint256 public sum_of_requests;
    uint256 public sum_of_withdraws;

    ////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////
    constructor(address _arm, address _weth, address[] memory _lps) {
        arm = LidoARM(payable(_arm));
        weth = IERC20(_weth);

        require(_lps.length > 0, "LH: EMPTY_LPS");
        lps = _lps;
    }

    ////////////////////////////////////////////////////
    /// --- ACTIONS
    ////////////////////////////////////////////////////
    /// @notice Provide liquidity to the ARM with a given amount of WETH
    /// @dev This assumes that lps have unlimited capacity to provide liquidity on LPC contracts.
    function deposit(uint256 _seed) external {
        numberOfCalls["lpHandler.deposit"]++;

        // Get a user
        address user = lps[_seed % lps.length];

        // Amount of WETH to deposit should be between 0 and total WETH balance
        uint256 amount = _bound(_seed, 0, weth.balanceOf(user));
        console.log("LpHandler.deposit(%18e), %s", amount, names[user]);

        // Prank user
        vm.startPrank(user);

        // Approve WETH to ARM
        weth.approve(address(arm), amount);

        // Deposit WETH
        uint256 expectedShares = arm.previewDeposit(amount);
        uint256 shares = arm.deposit(amount);

        // This is an invariant check. The shares should be equal to the expected shares
        require(shares == expectedShares, "LH: DEPOSIT - INVALID_SHARES");

        // End prank
        vm.stopPrank();

        // Update sum of deposits
        sum_of_deposits += amount;
    }

    /// @notice Request to redeem a given amount of shares from the ARM
    /// @dev This is allowed to redeem 0 shares.
    function requestRedeem(uint256 _seed) external {
        numberOfCalls["lpHandler.requestRedeem"]++;

        // Try to get a user that have shares, i.e. that have deposited and not redeemed all
        // If there is not such user, get a random user and 0redeem
        address user;
        uint256 len = lps.length;
        uint256 __seed = _bound(_seed, 0, type(uint256).max - len);
        for (uint256 i; i < len; i++) {
            user = lps[(__seed + i) % len];
            if (arm.balanceOf(user) > 0) break;
        }
        require(user != address(0), "LH: REDEEM_REQUEST - NO_USER"); // Should not happen, but just in case

        // Amount of shares to redeem should be between 0 and user total shares balance
        uint256 shares = _bound(_seed, 0, arm.balanceOf(user));
        console.log("LpHandler.requestRedeem(%18e -- id: %d), %s", shares, arm.nextWithdrawalIndex(), names[user]);

        // Prank user
        vm.startPrank(user);

        // Redeem shares
        uint256 expectedAmount = arm.previewRedeem(shares);
        (uint256 id, uint256 amount) = arm.requestRedeem(shares);

        // This is an invariant check. The amount should be equal to the expected amount
        require(amount == expectedAmount, "LH: REDEEM_REQUEST - INVALID_AMOUNT");

        // End prank
        vm.stopPrank();

        // Add request to user
        requests[user].push(id);

        // Update sum of requests
        sum_of_requests += amount;
    }

    event UserFound(address user, uint256 requestId, uint256 requestIndex);
    /// @notice Claim redeem request for a user on the ARM
    /// @dev This call will be skipped if there is no request to claim at all. However, claiming zero is allowed.
    /// @dev A jump in time is done to the request deadline, but the time is rewinded back to the current time.
    function claimRedeem(uint256 _seed) external {
        numberOfCalls["lpHandler.claimRedeem"]++;

        // Get a user that have a request to claim
        // If no user have a request, skip this call
        address user;
        uint256 requestId; // on the ARM
        uint256 requestIndex; // local
        uint256 requestAmount;
        uint256 len = lps.length;
        uint256 __seed = _bound(_seed, 0, type(uint256).max - len);
        uint256 withdrawsClaimed = arm.withdrawsClaimed();

        // 1. Loop to find a user with a request
        for (uint256 i; i < len; i++) {
            // Take a random user
            address user_ = lps[(__seed + i) % len];
            // Check if user have a request
            if (requests[user_].length > 0) {
                // Cache user requests length
                uint256 requestLen = requests[user_].length;

                // 2. Loop to find a request that can be claimed
                for (uint256 j; j < requestLen; j++) {
                    uint256 ___seed = _bound(_seed, 0, type(uint256).max - requestLen);
                    // Take a random request among user requests
                    uint256 requestIndex_ = (___seed + j) % requestLen;

                    // Get data about the request (in ARM contract)
                    (,,, uint120 amount_, uint120 queued) = arm.withdrawalRequests(requests[user_][requestIndex_]);

                    // 3. Check if the request can be claimed
                    if (queued < withdrawsClaimed + weth.balanceOf(address(arm))) {
                        user = user_;
                        requestId = requests[user_][requestIndex_];
                        requestIndex = requestIndex_;
                        requestAmount = amount_;
                        emit UserFound(user, requestId, requestIndex);
                        break;
                    }
                }
            }

            // If we found a user with a request, break the loop
            if (user != address(0)) break;
        }

        // If no user have a request, skip this call
        if (user == address(0)) {
            console.log("LpHandler.claimRedeem - No user have a request");
            numberOfCalls["lpHandler.claimRedeem.skip"]++;
            return;
        }

        console.log("LpHandler.claimRedeem(%18e -- id: %d), %s", requestAmount, requestId, names[user]);

        // Timejump to request deadline
        skip(arm.claimDelay());

        // Prank user
        vm.startPrank(user);

        // Claim redeem
        (uint256 amount) = arm.claimRedeem(requestId);
        require(amount == requestAmount, "LH: CLAIM_REDEEM - INVALID_AMOUNT");

        // End prank
        vm.stopPrank();

        // Jump back to current time, to avoid issues with other tests
        rewind(arm.claimDelay());

        // Remove request
        uint256[] storage userRequests = requests[user];
        userRequests[requestIndex] = userRequests[userRequests.length - 1];
        userRequests.pop();

        // Update sum of withdraws
        sum_of_withdraws += amount;
    }
}
