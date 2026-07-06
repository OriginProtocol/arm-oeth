// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {MultiAssetARM} from "contracts/MultiAssetARM.sol";
import {PaxosAssetAdapter} from "contracts/adapters/PaxosAssetAdapter.sol";

// Interfaces
import {Mainnet} from "src/contracts/utils/Addresses.sol";
import {IERC20} from "contracts/Interfaces.sol";

/// @notice Shared fork setup for the PaxosARM suite. Deploys a single MultiAssetARM (USDC
///         liquidity) with two Paxos-issued base stablecoins (PYUSD and USDG) wired to
///         `PaxosAssetAdapter`s. The Paxos redemption queue is fully off-chain, so it is mocked:
///         `paxosRecipient` is a plain test address and Paxos settlement is simulated by dealing
///         USDC 1:1 to the adapter (see {_settle}). Mirrors the structure of
///         test/fork/MultiAssetARM/shared/Shared.sol.
abstract contract Fork_Shared_Test is Base_Test_ {
    /// @notice Price the ARM pays when buying PYUSD/USDG from traders. 0.998 USDC per base asset.
    uint256 public constant BUY_PRICE = 0.998e36;
    /// @notice Price the ARM charges when selling PYUSD/USDG to traders. 1 USDC per base asset.
    uint256 public constant SELL_PRICE = 1e36;
    /// @notice totalAssets() valuation price for PYUSD/USDG. 0.999 USDC per base asset.
    uint256 public constant CROSS_PRICE = 0.999e36;

    /// @notice USDC liquidity deposited into the ARM by the test contract. 100k USDC (6 decimals).
    uint256 public constant INITIAL_DEPOSIT = 100_000e6;
    /// @notice PYUSD/USDG inventory seeded on the ARM and the test contract. 50k tokens (6 decimals).
    uint256 public constant BASE_INVENTORY = 50_000e6;

    MultiAssetARM public arm;
    PaxosAssetAdapter public pyusdAdapter;
    PaxosAssetAdapter public usdgAdapter;

    IERC20 public usdc;
    IERC20 public pyusd;
    IERC20 public usdg;

    /// @notice Mocked Paxos on-chain deposit address. The real redemption queue is off-chain.
    address public paxosRecipient;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        super.setUp();

        _createAndSelectFork();
        _deployMockContracts();
        _generateAddresses();
        _deployContracts();
        _ignite();
        labelAll();
        _labelPaxos();
    }

    function _createAndSelectFork() internal {
        require(vm.envExists("MAINNET_URL"), "MAINNET_URL not set");

        if (vm.envExists("FORK_BLOCK_NUMBER_MAINNET")) {
            vm.createSelectFork("mainnet", vm.envUint("FORK_BLOCK_NUMBER_MAINNET"));
        } else {
            vm.createSelectFork("mainnet");
        }
    }

    function _deployMockContracts() internal {
        usdc = IERC20(Mainnet.USDC);
        pyusd = IERC20(Mainnet.PYUSD);
        usdg = IERC20(Mainnet.USDG);
        badToken = IERC20(address(0xDEADBEEF));
    }

    function _generateAddresses() internal {
        governor = makeAddr("governor");
        deployer = makeAddr("deployer");
        operator = makeAddr("operator");
        feeCollector = makeAddr("feeCollector");
        paxosRecipient = makeAddr("paxosRecipient");
    }

    function _deployContracts() internal {
        vm.startPrank(deployer);

        // 1. Deploy the MultiAssetARM behind a proxy (USDC liquidity asset, 6 decimals).
        MultiAssetARM armImpl = new MultiAssetARM({
            _liquidityAsset: Mainnet.USDC, _claimDelay: 10 minutes, _minSharesToRedeem: 1e6, _allocateThreshold: 100e6
        });
        Proxy armProxy = new Proxy();

        // Initialization mints MIN_TOTAL_SUPPLY to the dead address against MIN_LIQUIDITY (1) USDC.
        deal(address(usdc), deployer, 1);
        usdc.approve(address(armProxy), 1);

        armProxy.initialize(
            address(armImpl),
            governor,
            abi.encodeWithSelector(
                MultiAssetARM.initialize.selector,
                "Paxos ARM",
                "ARM-USDC",
                operator,
                2000, // 20% performance fee
                feeCollector,
                address(0) // no cap manager
            )
        );
        arm = MultiAssetARM(payable(address(armProxy)));
        vm.stopPrank();

        // 2. Deploy the two Paxos adapters, each behind a proxy. Initialize through the proxy so
        //    the operator and paxosRecipient are set on the proxy's storage.
        pyusdAdapter = PaxosAssetAdapter(
            _deployAdapter(address(new PaxosAssetAdapter(address(arm), Mainnet.PYUSD, Mainnet.USDC)))
        );
        usdgAdapter =
            PaxosAssetAdapter(_deployAdapter(address(new PaxosAssetAdapter(address(arm), Mainnet.USDG, Mainnet.USDC))));
    }

    /// @notice Deploys a PaxosAssetAdapter proxy and initializes it with the operator and the
    ///         mocked Paxos deposit address.
    function _deployAdapter(address impl) internal returns (address proxy) {
        vm.startPrank(deployer);
        Proxy adapterProxy = new Proxy();
        adapterProxy.initialize(
            impl, governor, abi.encodeWithSelector(PaxosAssetAdapter.initialize.selector, operator, paxosRecipient)
        );
        vm.stopPrank();
        proxy = address(adapterProxy);
    }

    function _ignite() internal virtual {
        // Fund the test contract with USDC and deposit liquidity into the ARM.
        deal(address(usdc), address(this), 1_000_000e6);
        usdc.approve(address(arm), type(uint256).max);
        arm.deposit(INITIAL_DEPOSIT);

        // Register the two Paxos base assets. A 0.998 buy / 1.0 sell band around a 0.999 cross;
        // both are pegged 1:1 to USDC so swaps skip the adapter conversion calls.
        vm.startPrank(arm.owner());
        arm.addBaseAsset(
            address(pyusd),
            address(pyusdAdapter),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );
        arm.addBaseAsset(
            address(usdg),
            address(usdgAdapter),
            BUY_PRICE,
            SELL_PRICE,
            type(uint128).max,
            type(uint128).max,
            CROSS_PRICE,
            true
        );
        vm.stopPrank();

        // Seed base-asset inventory on the ARM (so it can sell base assets to traders) and on the
        // test contract (so it can sell base assets back to the ARM).
        _seedAsset(pyusd);
        _seedAsset(usdg);
    }

    function _seedAsset(IERC20 token) internal {
        deal(address(token), address(arm), BASE_INVENTORY);
        deal(address(token), address(this), BASE_INVENTORY);
        token.approve(address(arm), type(uint256).max);
    }

    function _labelPaxos() internal {
        vm.label(address(arm), "PAXOS ARM");
        vm.label(address(pyusdAdapter), "PYUSD ADAPTER");
        vm.label(address(usdgAdapter), "USDG ADAPTER");
        vm.label(address(usdc), "USDC");
        vm.label(address(pyusd), "PYUSD");
        vm.label(address(usdg), "USDG");
        vm.label(paxosRecipient, "Paxos Recipient");
    }

    //////////////////////////////////////////////////////
    /// --- PAXOS SETTLEMENT MOCK
    //////////////////////////////////////////////////////
    /// @notice Simulates Paxos off-chain settlement by increasing the adapter's USDC balance by
    ///         `amount` (deal sets an absolute balance, so read the current one first).
    function _settle(PaxosAssetAdapter adapter, uint256 amount) internal {
        deal(address(usdc), address(adapter), usdc.balanceOf(address(adapter)) + amount);
    }

    //////////////////////////////////////////////////////
    /// --- PRICE / CONFIG HELPERS
    //////////////////////////////////////////////////////
    function _buyPrice(IERC20 token) internal view returns (uint256 buyPrice) {
        (uint128 _buy,,,,,,,,) = arm.baseAssetConfigs(address(token));
        buyPrice = _buy;
    }

    function _sellPrice(IERC20 token) internal view returns (uint256 sellPrice) {
        (, uint128 _sell,,,,,,,) = arm.baseAssetConfigs(address(token));
        sellPrice = _sell;
    }

    function _crossPrice(IERC20 token) internal view returns (uint256 crossPrice) {
        (,,,, uint128 _cross,,,,) = arm.baseAssetConfigs(address(token));
        crossPrice = _cross;
    }

    function _pendingRedeemAssets(IERC20 token) internal view returns (uint256 pending) {
        (,,,,, uint128 _pending,,,) = arm.baseAssetConfigs(address(token));
        pending = _pending;
    }

    function _adapter(IERC20 token) internal view returns (PaxosAssetAdapter) {
        (,,,,,,,, address adapter) = arm.baseAssetConfigs(address(token));
        return PaxosAssetAdapter(adapter);
    }

    function _swapFeeMultiplier(uint256 buyPrice, uint256 crossPrice, uint256 fee) internal pure returns (uint256) {
        if (buyPrice == 0 || fee == 0) return 0;
        return (crossPrice - buyPrice) * fee * PRICE_SCALE / (buyPrice * FEE_SCALE);
    }
}
