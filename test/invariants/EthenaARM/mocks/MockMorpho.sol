// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ERC4626} from "@solmate/mixins/ERC4626.sol";

contract MockMorpho is ERC4626 {
    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////
    uint256 public utilizationRate;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////
    event UtilizationRateChanged(uint256 oldUtilizationRate, uint256 newUtilizationRate);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address _underlying) ERC4626(ERC20(_underlying), "Mock Morpho Blue", "Mock Morpho Blue") {}

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 remainingLiquidity = totalAssets() * (1e18 - utilizationRate) / 1e18;
        uint256 userLiquidity = convertToAssets(balanceOf[owner]);
        return userLiquidity > remainingLiquidity ? remainingLiquidity : userLiquidity;
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    function setUtilizationRate(uint256 _utilizationRate) external {
        emit UtilizationRateChanged(utilizationRate, _utilizationRate);
        utilizationRate = _utilizationRate;
    }
}
