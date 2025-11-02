// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Base_Test_} from "test/Base.sol";

// Contracts
import {WETH} from "@solmate/tokens/WETH.sol";
import {Proxy} from "contracts/Proxy.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {ARMRouter} from "contracts/ARMRouter.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

// Mocks
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockWrapper} from "test/unit/Router/shared/mocks/MockWrapper.sol";

abstract contract Unit_Shared_ARMRouter_Test is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        // Deploy Mock contracts
        _deployMockContracts();

        // Deploy contracts
        _deployContracts();

        // Fund wrappers with tokens
        _fundWrappers();

        // Label contracts
        labelAll();
    }

    function _deployMockContracts() internal {
        // Tokens
        weth = IERC20(address(new WETH()));
        eeth = IERC20(address(new MockERC20("EtherFi ETH", "EETH", 18)));
        steth = IERC20(address(new MockERC20("Lido Staked ETH", "STETH", 18)));
        weeth = IERC20(address(new MockWrapper(address(eeth))));
        wsteth = IERC20(address(new MockWrapper(address(steth))));

        // Deploy ARM proxies
        lidoProxy = new Proxy();
        etherfiProxy = new Proxy();

        // Deploy ARM contracts
        lidoARM = new LidoARM(address(steth), address(weth), address(0), 0, 0, 0);
        etherfiARM = new EtherFiARM(address(eeth), address(weth), address(0), 0, 0, 0, address(0), address(0));

        // Deal x2 1e12 eth to this contract, wrap them in WETH and approve ARMs
        deal(address(this), 2e12);
        WETH(payable(address(weth))).deposit{value: 2e12}();
        weth.approve(address(lidoProxy), type(uint256).max);
        weth.approve(address(etherfiProxy), type(uint256).max);

        // Initialize proxies
        // Lido ARM
        bytes memory data = abi.encodeWithSelector(
            LidoARM.initialize.selector, "Lido ARM", "LIDO_ARM", address(this), 0, address(this), address(0)
        );
        lidoProxy.initialize(address(lidoARM), address(this), data);
        lidoARM = LidoARM(payable(address(lidoProxy)));

        // EtherFi ARM
        data = abi.encodeWithSelector(
            EtherFiARM.initialize.selector, "EtherFi ARM", "ETHERFI_ARM", address(this), 0, address(this), address(0)
        );
        etherfiProxy.initialize(address(etherfiARM), address(this), data);
        etherfiARM = EtherFiARM(payable(address(etherfiProxy)));
    }

    function _deployContracts() public {
        // Deploy Router
        router = new ARMRouter(address(weth));

        bytes4 getWstETHByStETH = bytes4(keccak256("getWstETHByStETH(uint256)"));
        bytes4 getStETHByWstETH = bytes4(keccak256("getStETHByWstETH(uint256)"));
        bytes4 getWeETHByeETH = bytes4(keccak256("getWeETHByeETH(uint256)"));
        bytes4 getEETHByWeETH = bytes4(keccak256("getEETHByWeETH(uint256)"));

        // Register ARMs in the Router
        router.registerConfig(
            address(steth), address(weth), ARMRouter.SwapType.ARM, address(lidoARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(weth), address(steth), ARMRouter.SwapType.ARM, address(lidoARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(eeth), address(weth), ARMRouter.SwapType.ARM, address(etherfiARM), bytes4(0), bytes4(0)
        );
        router.registerConfig(
            address(weth), address(eeth), ARMRouter.SwapType.ARM, address(etherfiARM), bytes4(0), bytes4(0)
        );

        // Register wrappers in the Router
        router.registerConfig(
            address(steth),
            address(wsteth),
            ARMRouter.SwapType.WRAPPER,
            address(wsteth),
            MockWrapper.wrap.selector,
            getWstETHByStETH
        );
        router.registerConfig(
            address(wsteth),
            address(steth),
            ARMRouter.SwapType.WRAPPER,
            address(wsteth),
            MockWrapper.unwrap.selector,
            getStETHByWstETH
        );
        router.registerConfig(
            address(eeth),
            address(weeth),
            ARMRouter.SwapType.WRAPPER,
            address(weeth),
            MockWrapper.wrap.selector,
            getWeETHByeETH
        );
        router.registerConfig(
            address(weeth),
            address(eeth),
            ARMRouter.SwapType.WRAPPER,
            address(weeth),
            MockWrapper.unwrap.selector,
            getEETHByWeETH
        );
    }

    function _fundWrappers() internal {
        // Fund wrappers with tokens
        MockERC20(address(steth)).mint(address(wsteth), 1_000 ether);
        MockERC20(address(eeth)).mint(address(weeth), 1_000 ether);

        // Approve wrappers
        steth.approve(address(wsteth), type(uint256).max);
        eeth.approve(address(weeth), type(uint256).max);
    }
}
