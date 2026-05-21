// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IAssetAdapter, IERC20, IOriginVault} from "../Interfaces.sol";

/**
 * @title Wrapped Origin OToken asset adapter
 * @notice Adapter for redeeming wrapped Origin OTokens through the Origin Vault withdrawal queue.
 * @dev Wrapped OTokens are first unwrapped into rebasing OTokens, then requested from the vault.
 * @author Origin Protocol Inc
 */
contract WrappedOriginAssetAdapter is Initializable, IAssetAdapter {
    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice Wrapped Origin token supplied by the ARM.
    IERC4626 public immutable wrappedOToken;
    /// @notice Underlying rebasing Origin token submitted to the vault.
    IERC20 public immutable otoken;
    /// @notice Liquidity asset received from vault claims.
    IERC20 public immutable liquidityAsset;
    /// @notice Origin Vault used for withdrawal requests and claims.
    IOriginVault public immutable vault;

    /// @notice Wrapped share amount represented by each vault withdrawal request id.
    mapping(uint256 requestId => uint256 shares) public requestShares;
    /// @notice Expected liquidity asset amount represented by each vault withdrawal request id.
    mapping(uint256 requestId => uint256 assets) public requestAssets;
    uint256[] internal pendingRequestIds;
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
    /// @param _wrappedOToken Wrapped Origin token to redeem.
    /// @param _otoken Underlying rebasing Origin token submitted to the vault.
    /// @param _liquidityAsset Asset received when vault withdrawals are claimed.
    /// @param _vault Origin Vault withdrawal queue.
    constructor(address _arm, address _wrappedOToken, address _otoken, address _liquidityAsset, address _vault) {
        arm = _arm;
        wrappedOToken = IERC4626(_wrappedOToken);
        otoken = IERC20(_otoken);
        liquidityAsset = IERC20(_liquidityAsset);
        vault = IOriginVault(_vault);
    }

    /// @notice Re-approves the Origin Vault when called through a proxy.
    function initialize() external initializer {
        otoken.approve(address(vault), type(uint256).max);
    }

    /// @notice Returns the liquidity asset received from vault withdrawal claims.
    function asset() external view returns (address) {
        return address(liquidityAsset);
    }

    /// @notice Converts wrapped Origin shares into expected underlying liquidity assets.
    /// @param shares Amount of wrapped Origin shares.
    /// @return assets Expected liquidity assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return wrappedOToken.convertToAssets(shares);
    }

    /// @notice Converts liquidity assets into expected wrapped Origin shares.
    /// @param assets Amount of liquidity assets.
    /// @return shares Expected wrapped Origin shares.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return wrappedOToken.convertToShares(assets);
    }

    /// @notice Pulls wrapped OTokens from the ARM, unwraps them, and opens an Origin Vault withdrawal request.
    /// @param shares Amount of wrapped OToken shares to request for redemption.
    /// @return sharesRequested Amount of wrapped OToken shares accepted into the withdrawal request.
    /// @return assetsExpected Expected liquidity assets after unwrapping.
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

    /// @notice Claims queued Origin Vault withdrawal requests and transfers received liquidity assets to the ARM.
    /// @dev Claims pending requests in FIFO order and requires `shares` to match complete request sizes.
    /// @param shares Exact amount of wrapped OToken shares represented by pending requests to claim.
    /// @return sharesClaimed Amount of wrapped OToken shares represented by claimed requests.
    /// @return assetsExpected Expected liquidity assets recorded when requests were opened.
    /// @return assetsReceived Amount reported by the vault or received by balance delta, whichever is greater.
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

    /// @notice Returns the total number of vault request ids ever stored by the adapter.
    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    /// @notice Returns a stored vault request id by array index.
    /// @param index Index in the pending request id array.
    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }
}
