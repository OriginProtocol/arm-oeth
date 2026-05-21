// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IAssetAdapter, IERC20, IEETHWithdrawal, IEETHWithdrawalNFT, IWeETH, IWETH} from "../Interfaces.sol";

/**
 * @title Ether.fi weETH asset adapter
 * @notice Adapter for redeeming weETH through Ether.fi's withdrawal queue into WETH.
 * @dev weETH is first unwrapped into eETH before opening an Ether.fi withdrawal request.
 * @author Origin Protocol Inc
 */
contract WeETHAssetAdapter is Initializable, IAssetAdapter, IERC721Receiver {
    /// @notice ARM contract authorized to request and claim redemptions.
    address public immutable arm;
    /// @notice weETH token supplied by the ARM.
    IWeETH public immutable weeth;
    /// @notice eETH token submitted to Ether.fi withdrawals after unwrapping.
    IERC20 public immutable eeth;
    /// @notice WETH liquidity asset returned to the ARM.
    IWETH public immutable weth;
    /// @notice Ether.fi withdrawal queue used to open withdrawal requests.
    IEETHWithdrawal public immutable etherfiWithdrawalQueue;
    /// @notice Ether.fi withdrawal NFT contract used to claim finalized requests.
    IEETHWithdrawalNFT public immutable etherfiWithdrawalNFT;

    /// @notice weETH share amount represented by each Ether.fi withdrawal request id.
    mapping(uint256 requestId => uint256 shares) public requestShares;
    /// @notice Expected WETH amount represented by each Ether.fi withdrawal request id.
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
    /// @param _weeth weETH token to redeem.
    /// @param _eeth eETH token submitted to Ether.fi withdrawals.
    /// @param _weth WETH token received after claims.
    /// @param _etherfiWithdrawalQueue Ether.fi withdrawal queue contract.
    /// @param _etherfiWithdrawalNFT Ether.fi withdrawal NFT contract.
    constructor(
        address _arm,
        address _weeth,
        address _eeth,
        address _weth,
        address _etherfiWithdrawalQueue,
        address _etherfiWithdrawalNFT
    ) {
        arm = _arm;
        weeth = IWeETH(_weeth);
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

    /// @notice Converts weETH shares into expected WETH assets.
    /// @param shares Amount of weETH shares.
    /// @return assets Expected WETH assets.
    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return weeth.getEETHByWeETH(shares);
    }

    /// @notice Converts WETH assets into expected weETH shares.
    /// @param assets Amount of WETH assets.
    /// @return shares Expected weETH shares.
    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return weeth.getWeETHByeETH(assets);
    }

    /// @notice Pulls weETH from the ARM, unwraps to eETH, and opens an Ether.fi withdrawal request.
    /// @param shares Amount of weETH to request for redemption.
    /// @return sharesRequested Amount of weETH accepted into the withdrawal request.
    /// @return assetsExpected Expected WETH assets after unwrapping.
    function requestRedeem(uint256 shares)
        external
        onlyARM
        nonZeroShares(shares)
        returns (uint256 sharesRequested, uint256 assetsExpected)
    {
        IERC20(address(weeth)).transferFrom(arm, address(this), shares);
        assetsExpected = weeth.unwrap(shares);
        uint256 requestId = etherfiWithdrawalQueue.requestWithdraw(address(this), assetsExpected);

        requestShares[requestId] = shares;
        requestAssets[requestId] = assetsExpected;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
    }

    /// @notice Claims queued Ether.fi withdrawal requests and transfers received WETH to the ARM.
    /// @dev Claims pending requests in FIFO order and wraps any received ETH into WETH.
    /// @param shares Exact amount of weETH represented by pending requests to claim.
    /// @return sharesClaimed Amount of weETH represented by claimed requests.
    /// @return assetsExpected Expected WETH amount recorded when requests were opened.
    /// @return assetsReceived Actual WETH amount received and transferred to the ARM.
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

        uint256 wethBefore = weth.balanceOf(address(this));
        etherfiWithdrawalNFT.batchClaimWithdraw(requestIds);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) weth.deposit{value: ethBalance}();

        assetsReceived = weth.balanceOf(address(this)) - wethBefore;
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
