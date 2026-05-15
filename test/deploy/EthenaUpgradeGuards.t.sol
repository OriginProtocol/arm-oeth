// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {$028_UpgradeEthenaARMScript} from "script/deploy/mainnet/028_UpgradeEthenaARMScript.s.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract ExposedUpgradeEthenaARMScript is $028_UpgradeEthenaARMScript {
    function checkNoLegacyEthenaCooldownData() external pure returns (bytes memory) {
        return _checkNoLegacyEthenaCooldownData();
    }
}

contract EthenaUpgradeGuardsTest is Test {
    uint256 internal constant ETHENA_LEGACY_COOLDOWN_AMOUNT_SLOT = 100;

    ExposedUpgradeEthenaARMScript internal script;

    function setUp() external {
        script = new ExposedUpgradeEthenaARMScript();
    }

    function test_UpgradeCheckDataCallsNoLegacyEthenaCooldownCheck() external view {
        assertEq(
            script.checkNoLegacyEthenaCooldownData(),
            abi.encodeWithSelector(EthenaARM.checkNoLegacyEthenaCooldown.selector)
        );
    }

    function test_UpgradeToAndCallChecksNoLegacyEthenaCooldown() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();

        proxy.upgradeToAndCall(address(newImpl), script.checkNoLegacyEthenaCooldownData());
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyEthenaCooldownPending() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        bytes memory data = script.checkNoLegacyEthenaCooldownData();
        vm.store(address(proxy), bytes32(ETHENA_LEGACY_COOLDOWN_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function _deployInitializedEthenaARMProxy() internal returns (Proxy proxy, EthenaARM newImpl) {
        MockERC20 usde = new MockERC20("USDe", "USDe", 18);

        EthenaARM oldImpl = new EthenaARM(address(usde), 10 minutes, 1e18, 100e18);
        newImpl = new EthenaARM(address(usde), 10 minutes, 1e18, 100e18);
        proxy = new Proxy();

        usde.mint(address(this), 1e12);
        usde.approve(address(proxy), 1e12);

        bytes memory data = abi.encodeWithSelector(
            EthenaARM.initialize.selector,
            "Ethena ARM",
            "ARM-sUSDe-USDe",
            address(this),
            2000,
            address(this),
            address(0)
        );
        proxy.initialize(address(oldImpl), address(this), data);
    }
}
