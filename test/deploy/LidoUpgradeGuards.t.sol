// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {$030_UpgradeLidoARMSwapFeeScript} from "script/deploy/mainnet/030_UpgradeLidoARMSwapFeeScript.s.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {StETHAssetAdapter} from "contracts/adapters/StETHAssetAdapter.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract ExposedUpgradeLidoARMSwapFeeScript is $030_UpgradeLidoARMSwapFeeScript {
    function checkNoLegacyLidoWithdrawalRequestsData() external pure returns (bytes memory) {
        return _checkNoLegacyLidoWithdrawalRequestsData();
    }
}

contract LidoUpgradeGuardsTest is Test {
    uint256 internal constant LIDO_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT = 100;

    ExposedUpgradeLidoARMSwapFeeScript internal script;

    function setUp() external {
        script = new ExposedUpgradeLidoARMSwapFeeScript();
    }

    function test_UpgradeCheckDataCallsNoLegacyLidoWithdrawalRequestsCheck() external view {
        assertEq(
            script.checkNoLegacyLidoWithdrawalRequestsData(),
            abi.encodeWithSelector(LidoARM.checkNoLegacyLidoWithdrawalRequests.selector)
        );
    }

    function test_UpgradeToAndCallChecksNoLegacyLidoWithdrawalRequests() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();

        proxy.upgradeToAndCall(address(newImpl), script.checkNoLegacyLidoWithdrawalRequestsData());
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyLidoWithdrawalRequestsPending() external {
        (Proxy proxy, LidoARM newImpl) = _deployInitializedLidoARMProxy();
        bytes memory data = script.checkNoLegacyLidoWithdrawalRequestsData();
        vm.store(address(proxy), bytes32(LIDO_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function test_StETHAdapterInitializeCallsLegacyQueueCheck() external {
        address upgradedArm = makeAddr("upgradedArm");
        address lidoWithdrawalQueue = makeAddr("lidoWithdrawalQueue");
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 steth = new MockERC20("Lido Staked Ether", "stETH", 18);
        StETHAssetAdapter adapterImpl =
            new StETHAssetAdapter(upgradedArm, address(weth), address(steth), lidoWithdrawalQueue);
        Proxy adapterProxy = new Proxy();

        vm.mockCall(upgradedArm, abi.encodeWithSelector(LidoARM.checkNoLegacyLidoWithdrawalRequests.selector), "");

        adapterProxy.initialize(address(adapterImpl), address(this), abi.encodeWithSignature("initialize()"));

        assertEq(steth.allowance(address(adapterProxy), lidoWithdrawalQueue), type(uint256).max);
    }

    function test_RevertWhen_StETHAdapterInitialize_LegacyQueueCheckReverts() external {
        address upgradedArm = makeAddr("upgradedArm");
        address lidoWithdrawalQueue = makeAddr("lidoWithdrawalQueue");
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 steth = new MockERC20("Lido Staked Ether", "stETH", 18);
        StETHAssetAdapter adapterImpl =
            new StETHAssetAdapter(upgradedArm, address(weth), address(steth), lidoWithdrawalQueue);
        Proxy adapterProxy = new Proxy();

        vm.mockCallRevert(
            upgradedArm,
            abi.encodeWithSelector(LidoARM.checkNoLegacyLidoWithdrawalRequests.selector),
            "LidoARM: legacy requests pending"
        );

        vm.expectRevert();
        adapterProxy.initialize(address(adapterImpl), address(this), abi.encodeWithSignature("initialize()"));
    }

    function _deployInitializedLidoARMProxy() internal returns (Proxy proxy, LidoARM newImpl) {
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);
        MockERC20 steth = new MockERC20("Lido Staked Ether", "stETH", 18);
        address lidoWithdrawalQueue = makeAddr("lidoWithdrawalQueue");

        LidoARM oldImpl = new LidoARM(address(steth), address(weth), lidoWithdrawalQueue, 10 minutes, 0, 0);
        newImpl = new LidoARM(address(steth), address(weth), lidoWithdrawalQueue, 10 minutes, 0, 0);
        proxy = new Proxy();

        weth.mint(address(this), 1e12);
        weth.approve(address(proxy), 1e12);

        bytes memory data = abi.encodeWithSelector(
            LidoARM.initialize.selector, "Lido ARM", "ARM-WETH-stETH", address(this), 2000, address(this), address(0)
        );
        proxy.initialize(address(oldImpl), address(this), data);
    }
}
