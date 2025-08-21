// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@pendle-sy/interfaces/IERC4626.sol";
import "@pendle-sy/core/StandardizedYield/v2/SYBaseV2.sol";

interface IARM {
    function liquidityAsset() external view returns (address);
}

/// @title PendleOriginARMSY
/// @notice This is exactly the same as PendleERC4626NotRedeemableToAssetSYV2, but uses IARM on the constructor instead
///         of IERC4626 because `asset` variable in ERC4626 is denominated `liquidityAsset`, in ARM.
contract PendleOriginARMSY is SYBaseV2 {
    using PMath for uint256;

    address public immutable asset;

    constructor(string memory _name, string memory _symbol, address _erc4626) SYBaseV2(_name, _symbol, _erc4626) {
        asset = IARM(_erc4626).liquidityAsset();
        _safeApproveInf(asset, _erc4626);
    }

    function _deposit(address tokenIn, uint256 amountDeposited)
        internal
        virtual
        override
        returns (uint256 /*amountSharesOut*/ )
    {
        if (tokenIn == yieldToken) {
            return amountDeposited;
        } else {
            return IERC4626(yieldToken).deposit(amountDeposited, address(this));
        }
    }

    function _redeem(address receiver, address, /*tokenOut*/ uint256 amountSharesToRedeem)
        internal
        override
        returns (uint256)
    {
        _transferOut(yieldToken, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return IERC4626(yieldToken).convertToAssets(PMath.ONE);
    }

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        internal
        view
        virtual
        override
        returns (uint256 /*amountSharesOut*/ )
    {
        if (tokenIn == yieldToken) return amountTokenToDeposit;
        else return IERC4626(yieldToken).previewDeposit(amountTokenToDeposit);
    }

    function _previewRedeem(address, /*tokenOut*/ uint256 amountSharesToRedeem)
        internal
        pure
        override
        returns (uint256 /*amountTokenOut*/ )
    {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = asset;
        res[1] = yieldToken;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = yieldToken;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == yieldToken || token == asset;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == yieldToken;
    }

    function assetInfo()
        external
        view
        virtual
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, asset, IERC20Metadata(asset).decimals());
    }
}
