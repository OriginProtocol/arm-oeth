// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {EthenaUnstaker} from "../EthenaUnstaker.sol";
import {IAssetAdapter, IERC20, IStakedUSDe, UserCooldown} from "../Interfaces.sol";
import {Ownable} from "../Ownable.sol";

/**
 * @title Ethena sUSDe asset adapter
 * @notice Adapter for redeeming sUSDe through Ethena cooldown unstakers into USDe.
 * @dev Redemption requests rotate across unstaker helper contracts because sUSDe cooldowns are per account.
 * @author Origin Protocol Inc
 */
contract EthenaAssetAdapter is IAssetAdapter, Ownable {
    /// @notice Minimum delay between new cooldown requests.
    uint256 public constant DELAY_REQUEST = 30 minutes;
    /// @notice Maximum number of rotating unstaker helper contracts.
    uint8 public constant MAX_UNSTAKERS = 42;

    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice USDe liquidity asset returned to the ARM.
    IERC20 public immutable usde;
    /// @notice sUSDe token redeemed through Ethena cooldowns.
    IStakedUSDe public immutable susde;

    /// @notice Rotating helper contracts that hold and cool down sUSDe.
    address[MAX_UNSTAKERS] public unstakers;
    /// @notice Index of the next unstaker helper to use for a new request.
    uint8 public nextUnstakerIndex;
    /// @notice Timestamp of the most recent cooldown request.
    uint32 public lastRequestTimestamp;

    /// @notice sUSDe share amount pending for each unstaker helper.
    mapping(address unstaker => uint256 shares) public requestShares;
    /// @notice Expected USDe amount pending for each unstaker helper.
    mapping(address unstaker => uint256 assets) public requestAssets;
    /// @notice Total number of unstaker cooldown requests queued by the adapter.
    uint256 public totalRequests;
    uint256 internal nextPendingIndex;

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }

    /// @param _arm ARM contract authorized to use the adapter.
    /// @param _usde USDe token received after cooldown claims.
    /// @param _susde sUSDe token to redeem.
    constructor(address _arm, address _usde, address _susde) {
        arm = _arm;
        usde = IERC20(_usde);
        susde = IStakedUSDe(_susde);

        _setOwner(address(0));
    }

    /// @notice Returns USDe as the liquidity asset produced by Ethena claims.
    function asset() external view returns (address) {
        return address(usde);
    }

    /// @notice Converts sUSDe shares into expected USDe assets.
    /// @param shares Amount of sUSDe shares.
    /// @return assets Expected USDe assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return susde.convertToAssets(shares);
    }

    /// @notice Converts USDe assets into expected sUSDe shares.
    /// @param assets Amount of USDe assets.
    /// @return shares Expected sUSDe shares.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return susde.convertToShares(assets);
    }

    /// @notice Transfers sUSDe to the next available unstaker and starts an Ethena cooldown.
    /// @dev Requires the per-request delay to have passed and the selected unstaker to have no pending cooldown.
    /// @param shares Amount of sUSDe shares to request for redemption.
    /// @return sharesRequested Amount of sUSDe shares accepted into the cooldown request.
    /// @return assetsExpected Expected USDe assets after cooldown.
    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        require(block.timestamp >= lastRequestTimestamp + DELAY_REQUEST, "Adapter: delay not passed");
        lastRequestTimestamp = uint32(block.timestamp);

        address unstaker = unstakers[nextUnstakerIndex];
        require(unstaker != address(0), "Adapter: invalid unstaker");

        UserCooldown memory cooldown = susde.cooldowns(unstaker);
        require(cooldown.underlyingAmount == 0, "Adapter: unstaker in cooldown");
        require(requestShares[unstaker] == 0, "Adapter: unstaker pending");

        totalRequests++;
        nextUnstakerIndex = uint8((nextUnstakerIndex + 1) % MAX_UNSTAKERS);

        susde.transferFrom(arm, unstaker, shares);
        assetsExpected = EthenaUnstaker(unstaker).requestUnstake(shares);
        requestShares[unstaker] = shares;
        requestAssets[unstaker] = assetsExpected;
        sharesRequested = shares;
    }

    /// @notice Claims completed Ethena cooldowns and transfers received USDe to the ARM.
    /// @dev Claims pending unstakers in FIFO order and requires `shares` to match complete request sizes.
    /// @param shares Exact amount of sUSDe shares represented by pending unstakers to claim.
    /// @return sharesClaimed Amount of sUSDe shares represented by claimed unstakers.
    /// @return assetsExpected Expected USDe amount recorded when cooldowns were opened.
    /// @return assetsReceived Actual USDe amount received and transferred to the ARM.
    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 length = totalRequests;
        uint256 cursor = nextPendingIndex;
        uint256 claimCount;

        while (cursor + claimCount < length && sharesClaimed < shares) {
            address unstaker = unstakers[unstakerIndexAt(cursor + claimCount)];
            uint256 requestShareAmount = requestShares[unstaker];
            require(requestShareAmount > 0, "Adapter: invalid request");
            require(sharesClaimed + requestShareAmount <= shares, "Adapter: invalid redeem amount");

            sharesClaimed += requestShareAmount;
            assetsExpected += requestAssets[unstaker];
            claimCount++;
        }

        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");

        uint256 balanceBefore = usde.balanceOf(address(this));
        for (uint256 i = 0; i < claimCount; ++i) {
            address unstaker = unstakers[unstakerIndexAt(cursor + i)];
            delete requestShares[unstaker];
            delete requestAssets[unstaker];
            EthenaUnstaker(unstaker).claimUnstake();
        }
        nextPendingIndex = cursor + claimCount;

        assetsReceived = usde.balanceOf(address(this)) - balanceBefore;
        usde.transfer(arm, assetsReceived);
    }

    /// @notice Deploys missing unstaker helper contracts.
    /// @dev Only the owner can seed helper contracts after ownership is assigned during deployment.
    function deployUnstakers() external onlyOwner {
        for (uint256 i = 0; i < MAX_UNSTAKERS; ++i) {
            if (unstakers[i] == address(0)) unstakers[i] = address(new EthenaUnstaker(address(this), susde));
        }
    }

    /// @notice Replaces the unstaker helper set.
    /// @dev Existing helpers can only be replaced when they have no pending shares and no active cooldown.
    /// @param _unstakers New fixed-size unstaker helper list.
    function setUnstakers(address[MAX_UNSTAKERS] calldata _unstakers) external onlyOwner {
        for (uint256 i = 0; i < MAX_UNSTAKERS; ++i) {
            address oldUnstaker = unstakers[i];
            if (oldUnstaker != _unstakers[i]) {
                require(requestShares[oldUnstaker] == 0, "Adapter: unstaker pending");
                require(susde.cooldowns(oldUnstaker).underlyingAmount == 0, "Adapter: unstaker in cooldown");
            }
        }

        unstakers = _unstakers;
    }

    /// @notice Returns the unstaker helper index used by a queued request.
    /// @param requestIndex Index in the request queue.
    function unstakerIndexAt(uint256 requestIndex) public pure returns (uint8) {
        return uint8(requestIndex % MAX_UNSTAKERS);
    }
}
