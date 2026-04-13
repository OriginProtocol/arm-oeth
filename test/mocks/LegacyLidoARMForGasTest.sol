// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IERC20} from "contracts/Interfaces.sol";

/// @dev Test-only harness that preserves the old pre-upgrade Lido ARM fee model:
/// performance fees accrue on increases in available assets and are collected in WETH.
contract LegacyLidoARMForGasTest is Initializable {
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 public constant FEE_SCALE = 10000;
    uint256 internal constant MIN_TOTAL_SUPPLY = 1e12;

    IERC20 public immutable weth;
    IERC20 public immutable steth;

    uint256 public traderate0;
    uint256 public traderate1;
    uint256 public crossPrice;

    uint16 public fee;
    int128 public lastAvailableAssets;
    address public feeCollector;

    event TraderateChanged(uint256 traderate0, uint256 traderate1);
    event FeeCollected(address indexed feeCollector, uint256 fee);

    constructor(address _steth, address _weth) {
        steth = IERC20(_steth);
        weth = IERC20(_weth);
        _disableInitializers();
    }

    function initialize(string calldata, string calldata, address, uint256 _fee, address _feeCollector, address)
        external
        initializer
    {
        weth.transferFrom(msg.sender, address(this), MIN_TOTAL_SUPPLY);

        traderate0 = PRICE_SCALE;
        traderate1 = PRICE_SCALE - MAX_CROSS_PRICE_DEVIATION;
        crossPrice = PRICE_SCALE;

        fee = SafeCast.toUint16(_fee);
        feeCollector = _feeCollector;
        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(_availableAssets()));
    }

    function setPrices(uint256 buyT1, uint256 sellT1) external {
        traderate0 = PRICE_SCALE * PRICE_SCALE / sellT1;
        traderate1 = buyT1;
        emit TraderateChanged(traderate0, traderate1);
    }

    function swapExactTokensForTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external returns (uint256[] memory amounts) {
        uint256 amountOut = _swapExactTokensForTokens(inToken, outToken, amountIn, to);
        require(amountOut >= amountOutMin, "ARM: Insufficient output amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function swapTokensForExactTokens(
        IERC20 inToken,
        IERC20 outToken,
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external returns (uint256[] memory amounts) {
        uint256 amountIn = _swapTokensForExactTokens(inToken, outToken, amountOut, to);
        require(amountIn <= amountInMax, "ARM: Excess input amount");

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function collectFees() public returns (uint256 fees) {
        uint256 newAvailableAssets;
        (fees, newAvailableAssets) = _feesAccrued();

        lastAvailableAssets = SafeCast.toInt128(SafeCast.toInt256(newAvailableAssets) - SafeCast.toInt256(fees));
        if (fees == 0) return 0;

        require(fees <= weth.balanceOf(address(this)), "ARM: insufficient liquidity");
        weth.transfer(feeCollector, fees);

        emit FeeCollected(feeCollector, fees);
    }

    function feesAccrued() external view returns (uint256 fees) {
        (fees,) = _feesAccrued();
    }

    function setLastAvailableAssetsForGasTest(int128 value) external {
        lastAvailableAssets = value;
    }

    function _feesAccrued() internal view returns (uint256 fees, uint256 newAvailableAssets) {
        newAvailableAssets = _availableAssets();

        int256 assetIncrease = SafeCast.toInt256(newAvailableAssets) - lastAvailableAssets;
        if (assetIncrease <= 0) return (0, newAvailableAssets);

        fees = SafeCast.toUint256(assetIncrease) * fee / FEE_SCALE;
    }

    function _availableAssets() internal view returns (uint256) {
        return weth.balanceOf(address(this)) + steth.balanceOf(address(this)) * crossPrice / PRICE_SCALE;
    }

    function _swapExactTokensForTokens(IERC20 inToken, IERC20 outToken, uint256 amountIn, address to)
        internal
        returns (uint256 amountOut)
    {
        uint256 price = _price(inToken, outToken);
        amountOut = amountIn * price / PRICE_SCALE;

        inToken.transferFrom(msg.sender, address(this), amountIn);
        outToken.transfer(to, amountOut);
    }

    function _swapTokensForExactTokens(IERC20 inToken, IERC20 outToken, uint256 amountOut, address to)
        internal
        returns (uint256 amountIn)
    {
        uint256 price = _price(inToken, outToken);
        amountIn = ((amountOut * PRICE_SCALE) / price) + 3;

        inToken.transferFrom(msg.sender, address(this), amountIn);
        outToken.transfer(to, amountOut);
    }

    function _price(IERC20 inToken, IERC20 outToken) internal view returns (uint256 price) {
        if (inToken == weth) {
            require(outToken == steth, "ARM: Invalid out token");
            return traderate0;
        }
        if (inToken == steth) {
            require(outToken == weth, "ARM: Invalid out token");
            return traderate1;
        }
        revert("ARM: Invalid in token");
    }
}
