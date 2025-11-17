// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "./Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {MorphoMarket} from "src/contracts/markets/MorphoMarket.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Mocks
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockSUSDE} from "test/invariants/EthenaARM/mocks/MockSUSDE.sol";
import {MockERC4626} from "@solmate/test/utils/mocks/MockERC4626.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IStakedUSDe} from "contracts/Interfaces.sol";

/// @notice Shared invariant test contract.
/// @dev This contract should be used for deploying all contracts and mocks needed for the test.
abstract contract Setup is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual {
        // 1. Setup a realistic test environnement.
        _setUpRealisticEnvironnement();

        // 2. Create user.
        _createUsers();

        // 3. Deploy mocks.
        _deployMocks();

        // 4. Deploy contracts.
        _deployContracts();

        // 5. Label addresses
        _labelAll();

        // 6. Ignite contracts
        _ignite();
    }

    function _setUpRealisticEnvironnement() internal virtual {
        vm.warp(1_800_000_000); // Warp to a future timestamp
        vm.roll(24_000_000); // Warp to a future block number
    }

    function _createUsers() internal virtual {
        // --- Users with roles ---
        deployer = generateAddr("deployer");
        governor = generateAddr("governor");
        operator = generateAddr("operator");
        treasury = generateAddr("treasury");

        // --- Regular users ---
        alice = generateAddr("alice");
        bobby = generateAddr("bobby");
        carol = generateAddr("carol");
        david = generateAddr("david");
        elise = generateAddr("elise");
        frank = generateAddr("frank");
        dead = generateAddr("dead");

        // --- Group of users ---
        makers = new address[](MAKERS_COUNT);
        makers[0] = alice;
        makers[1] = bobby;
        makers[2] = carol;

        traders = new address[](TRADERS_COUNT);
        traders[0] = david;
        traders[1] = elise;
        traders[2] = frank;
    }

    function _deployMocks() internal virtual {
        // Deploy mock USDe.
        usde = IERC20(address(new MockERC20("USDe", "USDe", 18)));

        // Deploy mock sUSDe.
        susde = IStakedUSDe(address(new MockSUSDE(address(usde), governor)));

        // Deploy mock Morpho Market.
        morpho = address(new MockERC4626(ERC20(address(usde)), "Morpho USDe Market", "morpho-USDe"));
    }

    function _deployContracts() internal virtual {
        vm.startPrank(deployer);

        // Deploy Ethena ARM proxy.
        armProxy = new Proxy();

        // Deploy Ethena ARM implementation.
        arm = new EthenaARM({
            _usde: address(usde),
            _susde: address(susde),
            _claimDelay: DEFAULT_CLAIM_DELAY,
            _minSharesToRedeem: DEFAULT_MIN_SHARES_TO_REDEEM,
            _allocateThreshold: int256(DEFAULT_ALLOCATE_THRESHOLD)
        });

        // Initialization requires to transfer some USDe to the proxy from the deployer.
        MockERC20(address(usde)).mint(deployer, DEFAULT_MIN_TOTAL_SUPPLY);
        usde.approve(address(armProxy), DEFAULT_MIN_TOTAL_SUPPLY);

        // Initialize Ethena ARM proxy.
        bytes memory data = abi.encodeWithSelector(
            EthenaARM.initialize.selector,
            "Ethena ARM",
            "ARM-USDe-sUSDe",
            operator,
            2000, // 20% performance fee
            treasury,
            address(0) // CapManager address
        );
        armProxy.initialize(address(arm), governor, data);

        // Cast proxy address to EthenaARM type for easier interaction.
        arm = EthenaARM(address(armProxy));

        // Deploy Morpho Market Proxy.
        morphoMarketProxy = new Proxy();

        // Deploy Morpho Market implementation.
        market = new MorphoMarket(address(arm), morpho);

        // Initialize Morpho Market proxy.
        data = abi.encodeWithSelector(Abstract4626MarketWrapper.initialize.selector, address(0x1), address(0x1));
        morphoMarketProxy.initialize(address(market), governor, data);

        // Cast proxy address to MorphoMarket type for easier interaction.
        market = MorphoMarket(address(morphoMarketProxy));

        vm.stopPrank();
    }

    function _labelAll() internal virtual {
        // This only works with Foundry's Vm.label feature.
        if (!this.isLabelAvailable()) return;

        // --- Proxies ---
        vm.label(address(armProxy), "Proxy EthenaARM");
        vm.label(address(morphoMarketProxy), "Proxy MorphoMarket");

        // --- Implementations ---
        vm.label(address(arm), "Ethena ARM");
        vm.label(address(market), "Morpho Market");
        vm.label(address(morpho), "Morpho Blue");

        // --- Tokens ---
        vm.label(address(usde), "USDe");
        vm.label(address(susde), "sUSDe");

        // --- Users with roles ---
        vm.label(deployer, "Deployer");
        vm.label(governor, "Governor");
        vm.label(operator, "Operator");
        vm.label(treasury, "Treasury");

        // --- Regular users ---
        vm.label(alice, "Alice");
        vm.label(bobby, "Bobby");
        vm.label(carol, "Carol");
        vm.label(david, "David");
        vm.label(elise, "Elise");
        vm.label(frank, "Frank");
        vm.label(dead, "Dead");
    }

    function _ignite() internal virtual {
        // As sUSDe is an ERC4626, we want to avoid small total supply issues.
        // So we mint some sUSDe to the dead address, to replicate a realistic scenario.
        MockERC20(address(usde)).mint(address(dead), 2_000_000 ether);

        vm.startPrank(dead);
        usde.approve(address(susde), 1_000_000 ether);
        susde.deposit(1_000_000 ether, dead);

        // Same for morpho contract.
        usde.approve(morpho, 1_000_000 ether);
        MockERC4626(morpho).deposit(1_000_000 ether, dead);
        vm.stopPrank();
    }

    function generateAddr(string memory name) internal returns (address) {
        return vm.addr(uint256(keccak256(abi.encodePacked(name))));
    }
}
