// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {LidoARM} from "contracts/LidoARM.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockWstETH} from "../mocks/MockWstETH.sol";
import {MockMorpho} from "../mocks/MockMorpho.sol";
import {MockLidoWithdraw} from "../mocks/MockLidoWithdraw.sol";

abstract contract Base_Test_ is Test {
    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    // Main contracts
    LidoARM public lidoARM;
    StETHAssetAdapter public stETHAssetAdapter;
    WstETHAssetAdapter public wstETHAssetAdapter;

    // Interfaces
    IERC20 public weth;
    IERC20 public steth;
    IERC20 public wsteth;

    // Mocks
    MockWstETH public mockWstETH;
    MockLidoWithdraw public lidoWithdrawalQueue;
    MockMorpho public mockERC4626Market_A;
    MockMorpho public mockERC4626Market_B;

    //////////////////////////////////////////////////////
    /// --- Governance, multisigs and EOAs
    //////////////////////////////////////////////////////
    // LPs
    address public alice = makeAddr("alice");
    address public bobby = makeAddr("bobby");
    address public carol = makeAddr("carol");
    address public david = makeAddr("david");
    address public elise = makeAddr("elise");
    address public frank = makeAddr("frank");
    // Swapper
    address public grace = makeAddr("grace");
    // Morpho supplier
    address public hanna = makeAddr("hanna");

    // Privileged roles
    address public deployer = makeAddr("deployer");
    address public governor = makeAddr("governor");
    address public operator = makeAddr("operator");
    address public feeCollector = makeAddr("feeCollector");

    address[] public lps = [alice, bobby, carol, david, elise];
    address[] public users = [alice, bobby, carol, david, elise, frank, grace, hanna];

    //////////////////////////////////////////////////////
    /// --- DEFAULT VALUES
    //////////////////////////////////////////////////////
    uint256 public constant FEE_SCALE = 10_000;
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 public constant DEFAULT_FEE = 2_000;
    uint256 public constant CLAIM_DELAY = 10 minutes;
    uint256 public constant DELAY_REQUEST = 30 minutes;
    uint256 public constant DEFAULT_AMOUNT = 1 ether;
    uint256 public constant MIN_TOTAL_SUPPLY = 1e12;
    uint256 public constant MIN_SHARES_TO_REDEEM = 1e7;
    uint256 public constant MAX_CROSS_PRICE_DEVIATION = 20e32;

    uint256 public constant LP_COUNT = 5;
    uint256 public constant SWAPPER_COUNT = 1;
    uint256 public constant MINIMUM_DEPOSIT = 0 wei;
    uint256 public constant INITIAL_LP_LIQUIDITY = 20_000 ether;
    uint256 public constant MIN_SHARES_TO_REQUEST = 1 wei;
    uint256 public constant MINIMUM_BUY_PRICE = 0.8e36;
    uint256 public constant MINUMUM_SELL_PRICE = 1.2e36;

    bool internal consoleLogs;
    bool internal foundryFuzzer;

    //////////////////////////////////////////////////////
    /// --- GHOST VARIABLES
    //////////////////////////////////////////////////////
    uint256[] internal _pendingRequestIds;
    uint256[] internal _pendingBaseRedeemShares_stETH;
    uint256[] internal _pendingBaseRedeemShares_wstETH;

    // LP tracking
    uint256 internal ghost_requestCounter;
    uint256 internal sum_shares_requested;
    uint256 internal sum_shares_claimed;

    // WETH flows
    uint256 internal sum_weth_deposit;
    uint256 internal sum_weth_swapIn;
    uint256 internal sum_weth_swapOut;
    uint256 internal sum_weth_baseRedeemClaimed;
    uint256 internal sum_weth_donated;
    uint256 internal sum_weth_userClaimed;
    uint256 internal sum_weth_feesCollected;

    // stETH flows
    uint256 internal sum_steth_swapIn;
    uint256 internal sum_steth_swapOut;
    uint256 internal sum_steth_donated;
    uint256 internal sum_steth_baseRedeemRequested;
    uint256 internal sum_steth_rebased;

    // wstETH flows
    uint256 internal sum_wsteth_swapIn;
    uint256 internal sum_wsteth_swapOut;
    uint256 internal sum_wsteth_donated;
    uint256 internal sum_wsteth_baseRedeemRequested;

    // Fee tracking
    uint256 internal sum_fees_accrued;
    uint256 internal sum_fees_collected;
    uint256 internal sum_weth_buyside_out;

    // Market yield accrued to ARM
    uint256 internal sum_weth_marketYield;

    // Share price tracking
    uint256 internal ghost_lastSharePrice;
    bool internal ghost_crossPriceChanged;

    // Per-LP tracking
    mapping(address => uint256) internal ghost_userDeposited;
    mapping(address => uint256) internal ghost_userClaimed;
    mapping(address => uint256) internal ghost_userTransferInValue;
    mapping(address => uint256) internal ghost_userTransferOutValue;
}
