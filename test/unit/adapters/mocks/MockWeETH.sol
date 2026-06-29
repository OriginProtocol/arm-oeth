// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

/// @notice Test double for Ether.fi's wrapped eETH (weETH). Implements the subset used by
///         `WeETHAssetAdapter`: `getEETHByWeETH`, `getWeETHByeETH`, and `unwrap`. A configurable
///         `rate` (eETH per weETH, scaled to 1e18) exercises non 1:1 conversion paths. `unwrap`
///         burns the caller's weETH and mints the equivalent eETH to the caller.
contract MockWeETH is ERC20 {
    /// @notice Underlying eETH minted on unwrap.
    MockERC20 public immutable eeth;
    /// @notice eETH per weETH scaled to 1e18. 1e18 = 1:1.
    uint256 public rate = 1e18;

    constructor(address _eeth) ERC20("Wrapped eETH", "weETH", 18) {
        eeth = MockERC20(_eeth);
    }

    /// @notice Test helper to mint weETH shares.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Test helper to set the eETH-per-weETH exchange rate (1e18 = 1:1).
    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function getEETHByWeETH(uint256 weETHAmount) public view returns (uint256) {
        return weETHAmount * rate / 1e18;
    }

    function getWeETHByeETH(uint256 eETHAmount) public view returns (uint256) {
        return eETHAmount * 1e18 / rate;
    }

    /// @dev Burns the caller's weETH and mints the equivalent eETH to the caller.
    function unwrap(uint256 weETHAmount) external returns (uint256 eETHAmount) {
        _burn(msg.sender, weETHAmount);
        eETHAmount = getEETHByWeETH(weETHAmount);
        eeth.mint(msg.sender, eETHAmount);
    }
}
