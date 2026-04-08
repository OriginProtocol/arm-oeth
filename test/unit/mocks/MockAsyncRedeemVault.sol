// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "contracts/Interfaces.sol";
import {MockERC20} from "dependencies/solmate-6.7.0/src/test/utils/mocks/MockERC20.sol";

contract MockAsyncRedeemVault is MockERC20 {
    IERC20 public immutable asset;
    uint256 public pricePerShare;

    mapping(address controller => uint256 shares) public pendingRedeemShares;
    mapping(address controller => uint256 shares) public claimableRedeemShares;

    constructor(IERC20 _asset, string memory _name, string memory _symbol, uint8 _decimals)
        MockERC20(_name, _symbol, _decimals)
    {
        asset = _asset;
        pricePerShare = 10 ** _decimals;
    }

    function setPricePerShare(uint256 _pricePerShare) external {
        pricePerShare = _pricePerShare;
    }

    function setClaimableRedeemShares(address controller, uint256 shares) external {
        require(shares <= pendingRedeemShares[controller], "claimable > pending");
        claimableRedeemShares[controller] = shares;
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assetsOut) {
        assetsOut = shares * pricePerShare / (10 ** decimals);
    }

    function convertToShares(uint256 assetsIn) public view returns (uint256 shares) {
        shares = assetsIn * (10 ** decimals) / pricePerShare;
    }

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId) {
        require(controller == owner, "controller != owner");
        require(msg.sender == controller, "not controller");

        burn(owner, shares);
        pendingRedeemShares[controller] += shares;
        requestId = pendingRedeemShares[controller];
    }

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assetsOut) {
        require(msg.sender == controller, "not controller");
        require(claimableRedeemShares[controller] >= shares, "insufficient claimable");

        claimableRedeemShares[controller] -= shares;
        pendingRedeemShares[controller] -= shares;

        assetsOut = convertToAssets(shares);
        asset.transfer(receiver, assetsOut);
    }
}
