// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "test/Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {SiloMarket} from "contracts/markets/SiloMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IOriginVault} from "contracts/Interfaces.sol";

// Mocks
import {MockVault} from "test/unit/mocks/MockVault.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626Market} from "test/unit/mocks/MockERC4626Market.sol";

/// @notice Shared invariant test contract
/// @dev This contract should be used for deploying all contracts and mocks needed for the test.
abstract contract Setup is Base_Test_ {
    uint256 private constant NUM_LPS = 4;
    uint256 private constant NUM_SWAPS = 3;

    uint256 public constant CLAIM_DELAY = 1 days;
    uint256 public constant DEFAULT_FEE = 2000; // 20%
    uint256 public constant PRICE_SCALE = 1e36;
    uint256 public constant MIN_BUY_PRICE = 0.8 * 1e36;
    uint256 public constant MAX_SELL_PRICE = 1e36 + 2e30;
    uint256 public constant INITIAL_AMOUNT_LPS = 100 * 1_000_000_000 ether; // 100B WS
    uint256 public constant INITIAL_AMOUNT_SWAPS = 1_000_000_000 ether; // 1B WS and OS

    bool public constant DONATE = false;
    bool public constant CONSOLE_LOG = false;

    address[] public users;
    address[] public lps;
    address[] public swaps;
    address[] public markets;

    // Use name with same length for easier displaying in logs
    address public bobby;
    address public clark;
    address public david;
    address public elsie;
    address public glenn;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        // 1. Setup a realistic test environnement
        _setUpRealisticEnvironnement();

        // 2. Create user
        _createUsers();

        // To increase performance, we will not use fork., mocking contract instead.
        // 3. Deploy mocks.
        _deployMocks();

        // 4. Deploy contracts.
        _deployContracts();

        // 5. Initialize users and contracts.
        _initiliaze();
    }

    //////////////////////////////////////////////////////
    /// --- ENVIRONMENT
    //////////////////////////////////////////////////////
    function _setUpRealisticEnvironnement() private {
        vm.warp(1740000000);
        vm.roll(21760000);
    }

    //////////////////////////////////////////////////////
    /// --- USERS
    //////////////////////////////////////////////////////
    function _createUsers() private {
        // Users with role
        deployer = makeAddr("Deployer");
        governor = makeAddr("Governor");
        operator = makeAddr("Operator");
        feeCollector = makeAddr("Fee Collector");

        // Random users
        alice = makeAddr("Alice");
        bobby = makeAddr("Bobby");
        clark = makeAddr("Clark");
        david = makeAddr("David");
        elsie = makeAddr("Elsie");
        frank = makeAddr("Frank");
        glenn = makeAddr("Glenn");
        harry = makeAddr("Harry");

        // Add users to the list
        users.push(alice);
        users.push(bobby);
        users.push(clark);
        users.push(david);
        users.push(elsie);
        users.push(frank);
        users.push(glenn);
        users.push(harry);
    }

    //////////////////////////////////////////////////////
    /// --- MOCKS
    //////////////////////////////////////////////////////
    function _deployMocks() private {
        os = IERC20(address(new MockERC20("Origin Sonic", "OS", 18)));
        ws = IERC20(address(new MockERC20("Wrapped Sonic", "WS", 18)));
        vault = IOriginVault(address(new MockVault(os, ws)));
        market = IERC4626(address(new MockERC4626Market(ws)));
        market2 = IERC4626(address(new MockERC4626Market(ws)));

        // Label mocks
        vm.label(address(os), "OS");
        vm.label(address(ws), "WS");
        vm.label(address(vault), "VAULT");
        vm.label(address(market), "MOCK SILO MARKET 1");
        vm.label(address(market2), "MOCK SILO MARKET 2");
    }

    //////////////////////////////////////////////////////
    /// --- CONTRACTS
    //////////////////////////////////////////////////////
    function _deployContracts() private {
        vm.startPrank(deployer);

        // ---
        // --- 1. Deploy all proxies. ---
        originARMProxy = new Proxy();
        Proxy siloMarketProxy = new Proxy();

        // ---
        // --- 2. Deploy all implementations. ---
        // Deploy OriginARM implementation
        originARM = new OriginARM(address(os), address(ws), address(vault), CLAIM_DELAY, 1e7, 1e18);

        // Deploy SiloMarket implementation
        siloMarket = new SiloMarket(address(originARMProxy), address(market2), makeAddr("fake gauge"));

        /// ---
        /// --- 3. Initialize all proxies. ---
        // Initialization requires 1e12 liquid assets to mint to dead address.
        // Deployer approve the proxy to transfer 1e12 liquid assets.
        ws.approve(address(originARMProxy), 1e12);
        // Mint 1e12 liquid assets to the deployer.
        deal(address(ws), deployer, 1e12);

        // Initialize the proxy
        originARMProxy.initialize(
            address(originARM),
            governor,
            abi.encodeWithSelector(
                OriginARM.initialize.selector,
                "Origin ARM",
                "ARM-WS-OS",
                operator,
                DEFAULT_FEE,
                feeCollector,
                address(0)
            )
        );

        // Initialize the SiloMarket proxy
        siloMarketProxy.initialize(
            address(siloMarket),
            governor,
            abi.encodeWithSelector(Abstract4626MarketWrapper.initialize.selector, operator)
        );

        vm.stopPrank();

        // ---
        // --- 4. Set the proxy as the OriginARM ---
        originARM = OriginARM(address(originARMProxy));
        siloMarket = SiloMarket(address(siloMarketProxy));

        // ---
        // --- 5. Label all contracts ---
        vm.label(address(originARM), "Origin ARM");
        vm.label(address(originARMProxy), "Origin ARM Proxy");
        vm.label(address(siloMarket), "Silo Market");
        vm.label(address(siloMarketProxy), "Silo Market Proxy");
    }

    function _initiliaze() private {
        // --- Assigns to Categories ---
        // In this configuration, an user is either a LP or a Swap, but not both.
        require(NUM_LPS + NUM_SWAPS <= users.length, "IBT: NOT_ENOUGH_USERS");

        // LPs
        for (uint256 i; i < NUM_LPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            lps.push(user);

            // Give them a lot of WS
            deal(address(ws), user, INITIAL_AMOUNT_LPS);

            // Approve ARM for WS
            vm.prank(user);
            ws.approve(address(originARM), type(uint256).max);
        }

        // Swappers
        for (uint256 i = NUM_LPS; i < NUM_LPS + NUM_SWAPS; i++) {
            address user = users[i];
            require(user != address(0), "IBT: INVALID_USER");
            swaps.push(user);

            // Give them a lot of WS and OS
            deal(address(ws), user, INITIAL_AMOUNT_SWAPS);
            deal(address(os), user, INITIAL_AMOUNT_SWAPS);

            // Approve ARM for WS and OS
            vm.startPrank(user);
            os.approve(address(originARM), type(uint256).max);
            ws.approve(address(originARM), type(uint256).max);
            vm.stopPrank();
        }

        // Distribute a lot of WS to the vault, this will help for redeeming OS
        deal(address(ws), address(vault), type(uint128).max);

        // --- Setup ARM ---
        // Set cross price
        vm.prank(governor);
        originARM.setCrossPrice(0.9999 * 1e36);
        // Set prices
        vm.prank(operator);
        originARM.setPrices(MIN_BUY_PRICE, MAX_SELL_PRICE);

        // --- Setup Markets ---
        markets = new address[](2);
        markets[0] = address(market);
        markets[1] = address(siloMarket);
        vm.prank(governor);
        originARM.addMarkets(markets);

        // Fund the markets
        deal(address(ws), address(this), 2 * 1 ether);
        ws.approve(address(market), type(uint256).max);
        ws.approve(address(market2), type(uint256).max);
        market.deposit(1 ether, address(this));
        market2.deposit(1 ether, address(this));
    }
}
