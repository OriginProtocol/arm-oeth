// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockAssetAdapter} from "./mocks/MockAssetAdapter.sol";
import {MockERC4626Market} from "./mocks/MockERC4626Market.sol";

/// @notice Base harness for the MultiAssetARM unit suite. The liquidity-asset decimals are parameterized via
///         the virtual {liquidityDecimals} hook (default 18); decimal-sensitive test files subclass with both
///         18 and 6 decimals so the same logic runs against both. Base assets cover the full matrix:
///         peg6/peg18 (pegged 1:1) and adp6/adp18 (adapter-backed), in 6 and 18 decimals.
abstract contract Base_MultiAssetARM_Test is Test {
    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    MultiAssetARM public arm;
    CapManager public capManager;
    MockERC4626Market public market;
    MockERC4626Market public market2;

    // One adapter per base asset (asset() == liquidity asset).
    MockAssetAdapter public adapterPeg6;
    MockAssetAdapter public adapterPeg18;
    MockAssetAdapter public adapterAdp6;
    MockAssetAdapter public adapterAdp18;

    //////////////////////////////////////////////////////
    /// --- TOKENS
    //////////////////////////////////////////////////////
    IERC20 public liquidity; // 6 or 18 decimals (parameterized)
    IERC20 public peg6; // pegged base, 6 decimals
    IERC20 public peg18; // pegged base, 18 decimals
    IERC20 public adp6; // adapter-backed base, 6 decimals
    IERC20 public adp18; // adapter-backed base, 18 decimals

    //////////////////////////////////////////////////////
    /// --- ACCOUNTS
    //////////////////////////////////////////////////////
    address public alice = makeAddr("alice");
    address public bobby = makeAddr("bobby");
    address public deployer = makeAddr("deployer");
    address public governor = makeAddr("governor");
    address public operator = makeAddr("operator");
    address public feeCollector = makeAddr("feeCollector");

    //////////////////////////////////////////////////////
    /// --- DECIMAL-INDEPENDENT CONSTANTS
    //////////////////////////////////////////////////////
    uint256 public constant FEE_SCALE = 10_000;
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 public constant DEFAULT_FEE = 2_000;
    uint256 public constant CLAIM_DELAY = 10 minutes;
    uint256 public constant DELAY_REQUEST = 30 minutes;
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12; // LP shares are always 18-decimal
    uint256 public constant MIN_SHARES_TO_REDEEM = 1e7;
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;
    uint256 public constant SCALE_1E12 = 1e12; // factor between 6 and 18 decimals

    // sell == cross == 1e36 so the sell leg carries no price factor (isolates decimal scaling);
    // buy = 0.998e36 is a small discount that also accrues the swap fee.
    uint256 public constant BUY_PRICE = 0.998e36;
    uint256 public constant SELL_PRICE = 1e36;
    uint256 public constant CROSS_PRICE = 1e36;

    //////////////////////////////////////////////////////
    /// --- DECIMAL PARAMETERIZATION
    //////////////////////////////////////////////////////
    /// @dev Liquidity-asset decimals (6 or 18). Override in subclasses; default 18.
    function liquidityDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    function LIQUIDITY_UNIT() internal pure returns (uint256) {
        return 10 ** liquidityDecimals();
    }

    /// @dev Mirrors AbstractARM.MIN_LIQUIDITY: 1e12 for an 18-decimal liquidity asset, 1 for a 6-decimal one.
    function MIN_LIQUIDITY() internal pure returns (uint256) {
        return liquidityDecimals() == 18 ? 1e12 : 1;
    }

    function DEFAULT_AMOUNT() internal pure returns (uint256) {
        return 100 * LIQUIDITY_UNIT();
    }

    //////////////////////////////////////////////////////
    /// --- SCALING HELPERS (mirror AbstractARM, base decimals vs liquidity decimals)
    //////////////////////////////////////////////////////
    function _scaleBaseToLiquidity(IERC20 base, uint256 amount) internal view returns (uint256) {
        uint8 bd = base.decimals();
        uint8 ld = liquidityDecimals();
        if (bd == ld) return amount;
        return ld > bd ? amount * SCALE_1E12 : amount / SCALE_1E12;
    }

    function _scaleLiquidityToBase(IERC20 base, uint256 amount) internal view returns (uint256) {
        uint8 bd = base.decimals();
        uint8 ld = liquidityDecimals();
        if (bd == ld) return amount;
        return bd > ld ? amount * SCALE_1E12 : amount / SCALE_1E12;
    }
}
