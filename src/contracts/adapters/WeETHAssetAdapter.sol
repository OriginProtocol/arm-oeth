// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IAssetAdapter, IERC20, IEETHWithdrawal, IEETHWithdrawalNFT, IWeETH, IWETH} from "../Interfaces.sol";

contract WeETHAssetAdapter is Initializable, IAssetAdapter, IERC721Receiver {
    address public immutable arm;
    IWeETH public immutable weeth;
    IERC20 public immutable eeth;
    IWETH public immutable weth;
    IEETHWithdrawal public immutable etherfiWithdrawalQueue;
    IEETHWithdrawalNFT public immutable etherfiWithdrawalNFT;

    mapping(uint256 requestId => uint256 shares) public requestShares;
    mapping(uint256 requestId => uint256 assets) public requestAssets;
    uint256[] internal pendingRequestIds;
    uint256 internal nextPendingIndex;

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

        eeth.approve(_etherfiWithdrawalQueue, type(uint256).max);
    }

    function initialize() external initializer {
        eeth.approve(address(etherfiWithdrawalQueue), type(uint256).max);
    }

    function asset() external view returns (address) {
        return address(weth);
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return weeth.getEETHByWeETH(shares);
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return weeth.getWeETHByeETH(assets);
    }

    function requestRedeem(uint256 shares) external returns (uint256 sharesRequested, uint256 assetsExpected) {
        _onlyARM();
        require(shares > 0, "Adapter: zero shares");

        IERC20(address(weeth)).transferFrom(arm, address(this), shares);
        assetsExpected = weeth.unwrap(shares);
        uint256 requestId = etherfiWithdrawalQueue.requestWithdraw(address(this), assetsExpected);

        requestShares[requestId] = shares;
        requestAssets[requestId] = assetsExpected;
        pendingRequestIds.push(requestId);

        sharesRequested = shares;
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

    function pendingRequestIdsLength() external view returns (uint256) {
        return pendingRequestIds.length;
    }

    function pendingRequestId(uint256 index) external view returns (uint256) {
        return pendingRequestIds[index];
    }

    function _onlyARM() internal view {
        require(msg.sender == arm, "Adapter: only ARM");
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
