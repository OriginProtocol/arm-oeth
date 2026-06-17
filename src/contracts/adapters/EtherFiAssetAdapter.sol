// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IAssetAdapter, IERC20, IEETHWithdrawal, IEETHWithdrawalNFT, IWETH} from "../Interfaces.sol";

/**
 * @title Ether.fi eETH asset adapter
 * @notice Adapter for redeeming eETH through Ether.fi's withdrawal queue into WETH.
 * @dev eETH shares and expected ETH assets are treated as 1:1 for accounting.
 * @author Origin Protocol Inc
 */
contract EtherFiAssetAdapter is Initializable, IAssetAdapter, IERC721Receiver {
    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice eETH token submitted to Ether.fi withdrawals.
    IERC20 public immutable eeth;
    /// @notice WETH liquidity asset returned to the ARM.
    IWETH public immutable weth;
    /// @notice Ether.fi withdrawal queue used to open withdrawal requests.
    IEETHWithdrawal public immutable etherfiWithdrawalQueue;
    /// @notice Ether.fi withdrawal NFT contract used to claim finalized requests.
    IEETHWithdrawalNFT public immutable etherfiWithdrawalNFT;

    /// @notice eETH share amount represented by each Ether.fi withdrawal request id.
    mapping(uint256 requestId => uint256 shares) public requestShares;
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
    /// @param _eeth eETH token to redeem.
    /// @param _weth WETH token received after claims.
    /// @param _etherfiWithdrawalQueue Ether.fi withdrawal queue contract.
    /// @param _etherfiWithdrawalNFT Ether.fi withdrawal NFT contract.
    constructor(
        address _arm,
        address _eeth,
        address _weth,
        address _etherfiWithdrawalQueue,
        address _etherfiWithdrawalNFT
    ) {
        arm = _arm;
        eeth = IERC20(_eeth);
        weth = IWETH(_weth);
        etherfiWithdrawalQueue = IEETHWithdrawal(_etherfiWithdrawalQueue);
        etherfiWithdrawalNFT = IEETHWithdrawalNFT(_etherfiWithdrawalNFT);
    }

    /// @notice Re-approves eETH for Ether.fi's withdrawal queue when called through a proxy.
    function initialize() external initializer {
        eeth.approve(address(etherfiWithdrawalQueue), type(uint256).max);
    }

    /// @notice Returns WETH as the liquidity asset produced by Ether.fi claims.
    function asset() external view returns (address) {
        return address(weth);
    }

    /// @notice Converts eETH shares to expected WETH assets at a 1:1 rate.
    /// @param shares Amount of eETH shares.
    /// @return assets Expected WETH assets.
    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    /// @notice Converts WETH assets to expected eETH shares at a 1:1 rate.
    /// @param assets Amount of WETH assets.
    /// @return shares Expected eETH shares.
    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    /// @notice Pulls eETH from the ARM and opens an Ether.fi withdrawal request.
    /// @param shares Amount of eETH to request for redemption.
    /// @return sharesRequested Amount of eETH accepted into the withdrawal request.
    /// @return assetsExpected Expected WETH assets from the request.
    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        eeth.transferFrom(arm, address(this), shares);
        uint256 requestId = etherfiWithdrawalQueue.requestWithdraw(address(this), shares);
        requestShares[requestId] = shares;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
        assetsExpected = shares;
    }

    /// @notice Claims queued Ether.fi withdrawal requests and sweeps WETH to the ARM.
    /// @dev Claims pending requests in FIFO order, wraps the full ETH balance into WETH, and transfers
    /// all adapter-held WETH to the ARM. `assetsReceived` may include previously donated ETH or WETH.
    /// @param shares Exact amount of eETH represented by pending requests to claim.
    /// @return sharesClaimed Amount of eETH represented by claimed requests.
    /// @return assetsExpected Expected WETH amount from the claimed requests.
    /// @return assetsReceived Total WETH amount swept to the ARM.
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

        etherfiWithdrawalNFT.batchClaimWithdraw(requestIds);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) weth.deposit{value: ethBalance}();

        assetsReceived = weth.balanceOf(address(this));
        IERC20(address(weth)).transfer(arm, assetsReceived);
    }

    /// @notice Returns the total number of Ether.fi request ids ever stored by the adapter.
    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    /// @notice Returns a stored Ether.fi request id by array index.
    /// @param index Index in the pending request id array.
    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    receive() external payable {}

    /// @notice Accepts Ether.fi withdrawal NFTs minted to this adapter.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
