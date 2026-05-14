// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20 as OZIERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EthenaUnstaker} from "../EthenaUnstaker.sol";
import {IAssetAdapter, IERC20, IStakedUSDe, UserCooldown} from "../Interfaces.sol";
import {Ownable} from "../Ownable.sol";

contract EthenaAssetAdapter is IAssetAdapter, Ownable {
    using SafeERC20 for OZIERC20;

    uint256 public constant DELAY_REQUEST = 30 minutes;
    uint8 public constant MAX_UNSTAKERS = 42;

    address public immutable arm;
    IERC20 public immutable usde;
    IStakedUSDe public immutable susde;

    address[MAX_UNSTAKERS] public unstakers;
    uint8 public nextUnstakerIndex;
    uint32 public lastRequestTimestamp;

    mapping(address unstaker => uint256 shares) public requestShares;
    mapping(address unstaker => uint256 assets) public requestAssets;
    uint8[] internal pendingUnstakerIndexes;
    uint256 internal nextPendingIndex;

    constructor(address _arm, address _usde, address _susde) {
        arm = _arm;
        usde = IERC20(_usde);
        susde = IStakedUSDe(_susde);

        _setOwner(address(0));
    }

    function asset() external view returns (address) {
        return address(usde);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return susde.convertToAssets(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return susde.convertToShares(assets);
    }

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

        pendingUnstakerIndexes.push(nextUnstakerIndex);
        nextUnstakerIndex = uint8((nextUnstakerIndex + 1) % MAX_UNSTAKERS);

        OZIERC20(address(susde)).safeTransferFrom(arm, unstaker, shares);
        assetsExpected = EthenaUnstaker(unstaker).requestUnstake(shares);
        requestShares[unstaker] = shares;
        requestAssets[unstaker] = assetsExpected;
        sharesRequested = shares;
    }

    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 length = pendingUnstakerIndexes.length;
        uint256 cursor = nextPendingIndex;
        uint256 claimCount;

        while (cursor + claimCount < length && sharesClaimed < shares) {
            address unstaker = unstakers[pendingUnstakerIndexes[cursor + claimCount]];
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
            address unstaker = unstakers[pendingUnstakerIndexes[cursor + i]];
            delete requestShares[unstaker];
            delete requestAssets[unstaker];
            EthenaUnstaker(unstaker).claimUnstake();
        }
        nextPendingIndex = cursor + claimCount;

        assetsReceived = usde.balanceOf(address(this)) - balanceBefore;
        OZIERC20(address(usde)).safeTransfer(arm, assetsReceived);
    }

    function deployUnstakers() external onlyOwner {
        for (uint256 i = 0; i < MAX_UNSTAKERS; ++i) {
            if (unstakers[i] == address(0)) unstakers[i] = address(new EthenaUnstaker(address(this), susde));
        }
    }

    function setUnstakers(address[MAX_UNSTAKERS] calldata _unstakers) external onlyOwner {
        unstakers = _unstakers;
    }

    function pendingUnstakerIndexesLength() external view returns (uint256) {
        return pendingUnstakerIndexes.length;
    }

    function pendingUnstakerIndex(uint256 index) external view returns (uint8) {
        return pendingUnstakerIndexes[index];
    }

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }
}
