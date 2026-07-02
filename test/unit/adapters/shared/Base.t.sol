// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Foundry
import {Test} from "forge-std/Test.sol";

// Contracts
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {CapManager} from "contracts/CapManager.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {WstETHAssetAdapter} from "contracts/adapters/WstETHAssetAdapter.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockWstETH} from "../mocks/MockWstETH.sol";
import {MockERC4626Market} from "../mocks/MockERC4626Market.sol";
import {MockLidoWithdraw} from "../mocks/MockLidoWithdraw.sol";

/// @notice Base harness for the Lido asset-adapter unit tests. Deploys a generic {MultiAssetARM} (WETH
///         liquidity) with stETH/wstETH base assets wired to the real Lido adapters, so the adapters can be
///         exercised in isolation by pranking the ARM.
abstract contract Base_Lido_Test is Test {
    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    MultiAssetARM public arm;
    CapManager public capManager;
    StETHAssetAdapter public stETHAssetAdapter;
    WstETHAssetAdapter public wstETHAssetAdapter;

    // Interfaces
    IERC20 public weth;
    IERC20 public steth;
    IERC20 public wsteth;

    // Mocks
    MockWstETH public mockWstETH;
    MockLidoWithdraw public lidoWithdrawalQueue;
    MockERC4626Market public mockERC4626Market;
    MockERC4626Market public mockERC4626Market2;

    //////////////////////////////////////////////////////
    /// --- Governance, multisigs and EOAs
    //////////////////////////////////////////////////////
    // Users
    address public alice = makeAddr("alice");
    address public bobby = makeAddr("bobby");

    // Privileged roles
    address public deployer = makeAddr("deployer");
    address public governor = makeAddr("governor");
    address public operator = makeAddr("operator");
    address public feeCollector = makeAddr("feeCollector");

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
}
