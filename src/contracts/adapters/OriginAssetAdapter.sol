// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IAssetAdapter, IERC20, IOriginVault} from "../Interfaces.sol";

contract OriginAssetAdapter is IAssetAdapter {
    address public immutable arm;
    IERC20 public immutable otoken;
    IERC20 public immutable liquidityAsset;
    IOriginVault public immutable vault;

    mapping(uint256 requestId => uint256 shares) public requestShares;
    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    constructor(address _arm, address _otoken, address _liquidityAsset, address _vault) {
        arm = _arm;
        otoken = IERC20(_otoken);
        liquidityAsset = IERC20(_liquidityAsset);
        vault = IOriginVault(_vault);
        otoken.approve(_vault, type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function requestRedeem(uint256 shares) external returns (uint256 sharesRequested, uint256 assetsExpected) {
        _onlyARM();
        require(shares > 0, "Adapter: zero shares");

        otoken.transferFrom(arm, address(this), shares);
        (uint256 requestId,) = vault.requestWithdrawal(shares);
        requestShares[requestId] = shares;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
        assetsExpected = shares;
    }

    function redeem(uint256 shares)
        external
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        _onlyARM();
        require(shares > 0, "Adapter: zero shares");

        uint256 length = pendingRequestIds.length;
        uint256 cursor = nextPendingIndex;
        uint256 claimCount;

        while (cursor + claimCount < length && sharesClaimed < shares) {
            uint256 requestId = pendingRequestIds[cursor + claimCount];
            uint256 requestShareAmount = requestShares[requestId];
            require(requestShareAmount > 0, "Adapter: invalid request");
            require(sharesClaimed + requestShareAmount <= shares, "Adapter: invalid redeem amount");

            sharesClaimed += requestShareAmount;
            assetsExpected += requestShareAmount;
            claimCount++;
        }

        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");

        uint256[] memory requestIds = new uint256[](claimCount);
        for (uint256 i = 0; i < claimCount; ++i) {
            requestIds[i] = pendingRequestIds[cursor + i];
            delete requestShares[requestIds[i]];
        }
        nextPendingIndex = cursor + claimCount;

        uint256 balanceBefore = liquidityAsset.balanceOf(address(this));
        (, uint256 amountClaimed) = vault.claimWithdrawals(requestIds);
        uint256 balanceDelta = liquidityAsset.balanceOf(address(this)) - balanceBefore;
        assetsReceived = balanceDelta > amountClaimed ? balanceDelta : amountClaimed;
        liquidityAsset.transfer(arm, balanceDelta);
    }

    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    function _onlyARM() internal view {
        require(msg.sender == arm, "Adapter: only ARM");
    }
}
