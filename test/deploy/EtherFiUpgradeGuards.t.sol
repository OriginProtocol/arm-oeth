// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {$029_UpgradeEtherFiARMSwapFeeScript} from "script/deploy/mainnet/029_UpgradeEtherFiARMSwapFeeScript.s.sol";
import {EtherFiARM} from "contracts/EtherFiARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract ExposedUpgradeEtherFiARMSwapFeeScript is $029_UpgradeEtherFiARMSwapFeeScript {
    function checkNoLegacyEtherFiWithdrawalsData() external pure returns (bytes memory) {
        return _checkNoLegacyEtherFiWithdrawalsData();
    }
}

contract EtherFiUpgradeGuardsTest is Test {
    uint256 internal constant ETHERFI_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT = 100;

    ExposedUpgradeEtherFiARMSwapFeeScript internal script;

    function setUp() external {
        script = new ExposedUpgradeEtherFiARMSwapFeeScript();
    }

    function test_UpgradeCheckDataCallsNoLegacyEtherFiWithdrawalsCheck() external view {
        assertEq(
            script.checkNoLegacyEtherFiWithdrawalsData(),
            abi.encodeWithSelector(EtherFiARM.checkNoLegacyEtherFiWithdrawals.selector)
        );
    }

    function test_UpgradeToAndCallChecksNoLegacyEtherFiWithdrawals() external {
        (Proxy proxy, EtherFiARM newImpl) = _deployInitializedEtherFiARMProxy();

        proxy.upgradeToAndCall(address(newImpl), script.checkNoLegacyEtherFiWithdrawalsData());
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyEtherFiWithdrawalsPending() external {
        (Proxy proxy, EtherFiARM newImpl) = _deployInitializedEtherFiARMProxy();
        bytes memory data = script.checkNoLegacyEtherFiWithdrawalsData();
        vm.store(address(proxy), bytes32(ETHERFI_LEGACY_WITHDRAWAL_QUEUE_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function _deployInitializedEtherFiARMProxy() internal returns (Proxy proxy, EtherFiARM newImpl) {
        MockERC20 eeth = new MockERC20("EtherFi ETH", "eETH", 18);
        MockERC20 weth = new MockERC20("Wrapped ETH", "WETH", 18);

        EtherFiARM oldImpl = new EtherFiARM(address(eeth), address(weth), 10 minutes, 1e7, 1e18);
        newImpl = new EtherFiARM(address(eeth), address(weth), 10 minutes, 1e7, 1e18);
        proxy = new Proxy();

        weth.mint(address(this), 1e12);
        weth.approve(address(proxy), 1e12);

        bytes memory data = abi.encodeWithSelector(
            EtherFiARM.initialize.selector,
            "EtherFi ARM",
            "ARM-WETH-eETH",
            address(this),
            2000,
            address(this),
            address(0)
        );
        proxy.initialize(address(oldImpl), address(this), data);
    }
}
