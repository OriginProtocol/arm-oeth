// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Base_Test_} from "./Base.sol";

// Contracts
import {Proxy} from "contracts/Proxy.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {MorphoMarket} from "src/contracts/markets/MorphoMarket.sol";
import {EthenaUnstaker} from "contracts/EthenaUnstaker.sol";
import {Abstract4626MarketWrapper} from "contracts/markets/Abstract4626MarketWrapper.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockSUSDE} from "test/invariants/EthenaARM/mocks/MockSUSDE.sol";
import {MockMorpho} from "test/invariants/EthenaARM/mocks/MockMorpho.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";
import {IStakedUSDe} from "contracts/Interfaces.sol";

/// @notice Shared invariant test contract.
/// @dev This contract should be used for deploying all contracts and mocks needed for the test.
abstract contract Setup is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function _setup() internal virtual {
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
        grace = generateAddr("grace");
        harry = generateAddr("harry");
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
        morpho = new MockMorpho(address(usde));
    }

    function _deployContracts() internal virtual {
        vm.startPrank(deployer);

        // --- Ethena ARM ---
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
        armProxy.initialize(address(arm), deployer, data);

        // Cast proxy address to EthenaARM type for easier interaction.
        arm = EthenaARM(address(armProxy));

        // --- Ethena Unstakers ---
        // Deploy 42 Ethena Unstaker contracts
        address[UNSTAKERS_COUNT] memory _unstakers;
        for (uint256 i; i < UNSTAKERS_COUNT; i++) {
            unstakers.push(new EthenaUnstaker(address(arm), susde));
            _unstakers[i] = address(unstakers[i]);
        }
        // Set unstakers in the ARM
        arm.setUnstakers(_unstakers);

        // Transfer ownership of the ARM to the governor.
        arm.setOwner(governor);

        // --- Morpho Market ---
        // Deploy Morpho Market Proxy.
        morphoMarketProxy = new Proxy();

        // Deploy Morpho Market implementation.
        market = new MorphoMarket(address(arm), address(morpho));

        // Initialize Morpho Market proxy.
        data = abi.encodeWithSelector(Abstract4626MarketWrapper.initialize.selector, address(0x1), address(0x1));
        morphoMarketProxy.initialize(address(market), governor, data);

        // Cast proxy address to MorphoMarket type for easier interaction.
        market = MorphoMarket(address(morphoMarketProxy));

        vm.stopPrank();
    }

    function _labelAll() internal virtual {
        // This only works with Foundry's Vm.label feature.
        if (isLabelAvailable) return;

        // --- Proxies ---
        vm.label(address(armProxy), "Proxy EthenaARM");
        vm.label(address(morphoMarketProxy), "Proxy MorphoMarket");

        // --- Implementations ---
        vm.label(address(arm), "Ethena ARM");
        vm.label(address(market), "Morpho Market");
        vm.label(address(morpho), "Morpho Blue");
        vm.label(address(unstakers[0]), "Ethena Unstaker 0");
        vm.label(address(unstakers[1]), "Ethena Unstaker 1");
        vm.label(address(unstakers[2]), "Ethena Unstaker 2");
        vm.label(address(unstakers[3]), "Ethena Unstaker 3");
        vm.label(address(unstakers[4]), "Ethena Unstaker 4");
        vm.label(address(unstakers[5]), "Ethena Unstaker 5");
        vm.label(address(unstakers[6]), "Ethena Unstaker 6");
        vm.label(address(unstakers[7]), "Ethena Unstaker 7");
        vm.label(address(unstakers[8]), "Ethena Unstaker 8");
        vm.label(address(unstakers[9]), "Ethena Unstaker 9");
        vm.label(address(unstakers[10]), "Ethena Unstaker 10");
        vm.label(address(unstakers[11]), "Ethena Unstaker 11");
        vm.label(address(unstakers[12]), "Ethena Unstaker 12");
        vm.label(address(unstakers[13]), "Ethena Unstaker 13");
        vm.label(address(unstakers[14]), "Ethena Unstaker 14");
        vm.label(address(unstakers[15]), "Ethena Unstaker 15");
        vm.label(address(unstakers[16]), "Ethena Unstaker 16");
        vm.label(address(unstakers[17]), "Ethena Unstaker 17");
        vm.label(address(unstakers[18]), "Ethena Unstaker 18");
        vm.label(address(unstakers[19]), "Ethena Unstaker 19");
        vm.label(address(unstakers[20]), "Ethena Unstaker 20");
        vm.label(address(unstakers[21]), "Ethena Unstaker 21");
        vm.label(address(unstakers[22]), "Ethena Unstaker 22");
        vm.label(address(unstakers[23]), "Ethena Unstaker 23");
        vm.label(address(unstakers[24]), "Ethena Unstaker 24");
        vm.label(address(unstakers[25]), "Ethena Unstaker 25");
        vm.label(address(unstakers[26]), "Ethena Unstaker 26");
        vm.label(address(unstakers[27]), "Ethena Unstaker 27");
        vm.label(address(unstakers[28]), "Ethena Unstaker 28");
        vm.label(address(unstakers[29]), "Ethena Unstaker 29");
        vm.label(address(unstakers[30]), "Ethena Unstaker 30");
        vm.label(address(unstakers[31]), "Ethena Unstaker 31");
        vm.label(address(unstakers[32]), "Ethena Unstaker 32");
        vm.label(address(unstakers[33]), "Ethena Unstaker 33");
        vm.label(address(unstakers[34]), "Ethena Unstaker 34");
        vm.label(address(unstakers[35]), "Ethena Unstaker 35");
        vm.label(address(unstakers[36]), "Ethena Unstaker 36");
        vm.label(address(unstakers[37]), "Ethena Unstaker 37");
        vm.label(address(unstakers[38]), "Ethena Unstaker 38");
        vm.label(address(unstakers[39]), "Ethena Unstaker 39");
        vm.label(address(unstakers[40]), "Ethena Unstaker 40");
        vm.label(address(unstakers[41]), "Ethena Unstaker 41");
        // Using a loop here would be cleaner, but Vm.label doesn't support dynamic strings.

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
        vm.label(grace, "Grace");
        vm.label(harry, "Harry");
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
        usde.approve(address(morpho), 1_000_000 ether);
        morpho.deposit(1_000_000 ether, dead);
        vm.stopPrank();

        // Set initial prices in the ARM.
        vm.prank(governor);
        arm.setCrossPrice(0.9998e36);
        vm.prank(operator);
        arm.setPrices(0.9992e36, 0.9999e36);
        address[] memory markets = new address[](1);
        markets[0] = address(market);
        vm.prank(governor);
        arm.addMarkets(markets);

        // Grace will only deposit/withdraw USDe from/to sUSDe.
        vm.prank(grace);
        usde.approve(address(susde), type(uint256).max);

        // Harry will only deposit/withdraw USDe from/to Morpho.
        vm.prank(harry);
        usde.approve(address(morpho), type(uint256).max);

        // Governor will deposit usde rewards into sUSDe.
        vm.prank(governor);
        usde.approve(address(susde), type(uint256).max);

        // Makers and traders approve ARM to spend their USDe.
        for (uint256 i; i < MAKERS_COUNT; i++) {
            vm.prank(makers[i]);
            usde.approve(address(arm), type(uint256).max);
        }

        for (uint256 i; i < TRADERS_COUNT; i++) {
            vm.startPrank(traders[i]);
            usde.approve(address(arm), type(uint256).max);
            usde.approve(address(susde), type(uint256).max);
            susde.approve(address(arm), type(uint256).max);
            vm.stopPrank();
        }
    }

    function generateAddr(string memory name) internal returns (address) {
        return vm.addr(uint256(keccak256(abi.encodePacked(name))));
    }

    function assume(bool condition) internal returns (bool returnEarly) {
        if (!condition) {
            if (isAssumeAvailable) vm.assume(false);
            else returnEarly = true;
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    modifier ensureTimeIncrease() {
        uint256 oldTimestamp = block.timestamp;
        _;
        require(block.timestamp >= oldTimestamp, "TIME_DECREASED");
    }
}
