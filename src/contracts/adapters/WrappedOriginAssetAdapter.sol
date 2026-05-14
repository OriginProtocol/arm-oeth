// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAssetAdapter, IERC20, IOriginVault} from "../Interfaces.sol";

contract WrappedOriginAssetAdapter is Initializable, IAssetAdapter {
    address public immutable arm;
    IERC4626 public immutable wrappedOToken;
    IERC20 public immutable otoken;
    IERC20 public immutable liquidityAsset;
    IOriginVault public immutable vault;

    mapping(uint256 requestId => uint256 shares) public requestShares;
    mapping(uint256 requestId => uint256 assets) public requestAssets;
    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

    constructor(address _arm, address _wrappedOToken, address _otoken, address _liquidityAsset, address _vault) {
        arm = _arm;
        wrappedOToken = IERC4626(_wrappedOToken);
        otoken = IERC20(_otoken);
        liquidityAsset = IERC20(_liquidityAsset);
        vault = IOriginVault(_vault);
        otoken.approve(_vault, type(uint256).max);
    }

    function initialize() external initializer {
        otoken.approve(address(vault), type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return wrappedOToken.convertToAssets(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return wrappedOToken.convertToShares(assets);
    }

    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        IERC20(address(wrappedOToken)).transferFrom(arm, address(this), shares);
        assetsExpected = wrappedOToken.redeem(shares, address(this), address(this));
        (uint256 requestId,) = vault.requestWithdrawal(assetsExpected);

        requestShares[requestId] = shares;
        requestAssets[requestId] = assetsExpected;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
    }

    function redeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesClaimed, uint256 assetsExpected, uint256 assetsReceived)
    {
        uint256 length = pendingRequestIds.length;
        uint256 cursor = nextPendingIndex;
        uint256 claimCount;

        while (cursor + claimCount < length && sharesClaimed < shares) {
            uint256 requestId = pendingRequestIds[cursor + claimCount];
            uint256 requestShareAmount = requestShares[requestId];
            require(requestShareAmount > 0, "Adapter: invalid request");
            require(sharesClaimed + requestShareAmount <= shares, "Adapter: invalid redeem amount");

            sharesClaimed += requestShareAmount;
            assetsExpected += requestAssets[requestId];
            claimCount++;
        }

        require(sharesClaimed == shares, "Adapter: redeem exceeds claimable");

        uint256[] memory requestIds = new uint256[](claimCount);
        for (uint256 i = 0; i < claimCount; ++i) {
            requestIds[i] = pendingRequestIds[cursor + i];
            delete requestShares[requestIds[i]];
            delete requestAssets[requestIds[i]];
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

    modifier onlyARM() {
        require(msg.sender == arm, "Adapter: only ARM");
        _;
    }

    modifier nonZeroShares(uint256 shares) {
        require(shares > 0, "Adapter: zero shares");
        _;
    }
}
