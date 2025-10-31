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

abstract contract Unit_ARMRouter_Shared_Test is Base_Test_ {
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public virtual override {
        // Deploy Mock contracts
        _deployMockContracts();

        // Deploy contracts
        _deployContracts();

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
        weth.approve(address(lidoARM), type(uint256).max);
        weth.approve(address(etherfiARM), type(uint256).max);

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

        // Register ARMs in the Router
        router.registerConfig(address(steth), address(weth), bytes4(0), address(lidoARM));
        router.registerConfig(address(weth), address(steth), bytes4(0), address(lidoARM));
        router.registerConfig(address(eeth), address(weth), bytes4(0), address(etherfiARM));
        router.registerConfig(address(weth), address(eeth), bytes4(0), address(etherfiARM));

        // Register wrappers in the Router
        router.registerConfig(address(steth), address(wsteth), MockWrapper.wrap.selector, address(wsteth));
        router.registerConfig(address(wsteth), address(steth), MockWrapper.unwrap.selector, address(wsteth));
        router.registerConfig(address(eeth), address(weeth), MockWrapper.wrap.selector, address(weeth));
        router.registerConfig(address(weeth), address(eeth), MockWrapper.unwrap.selector, address(weeth));
    }
}
