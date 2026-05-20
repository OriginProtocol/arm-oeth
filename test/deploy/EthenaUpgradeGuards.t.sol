// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {$028_UpgradeEthenaARMScript} from "script/deploy/mainnet/028_UpgradeEthenaARMScript.s.sol";
import {AbstractARM} from "contracts/AbstractARM.sol";
import {EthenaARM} from "contracts/EthenaARM.sol";
import {Proxy} from "contracts/Proxy.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

contract ExposedUpgradeEthenaARMScript is $028_UpgradeEthenaARMScript {
    function migrateLegacyWithdrawQueueData() external pure returns (bytes memory) {
        return _migrateLegacyWithdrawQueueData();
    }
}

contract EthenaUpgradeGuardsTest is Test {
    uint256 internal constant LEGACY_PACKED_WITHDRAW_QUEUE_SLOT = 53;
    uint256 internal constant ETHENA_LEGACY_COOLDOWN_AMOUNT_SLOT = 100;

    ExposedUpgradeEthenaARMScript internal script;

    function setUp() external {
        script = new ExposedUpgradeEthenaARMScript();
    }

    function test_UpgradeDataCallsLegacyWithdrawQueueMigration() external view {
        assertEq(
            script.migrateLegacyWithdrawQueueData(),
            abi.encodeWithSelector(AbstractARM.migrateLegacyWithdrawQueue.selector)
        );
    }

    function test_UpgradeToAndCallMigratesLegacyWithdrawQueue() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        vm.store(
            address(proxy),
            bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT),
            bytes32(_packLegacyWithdrawQueue(1 ether, 1 ether))
        );

        proxy.upgradeToAndCall(address(newImpl), script.migrateLegacyWithdrawQueueData());

        assertEq(EthenaARM(address(proxy)).reservedWithdrawLiquidity(), 0);
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyEthenaCooldownPending() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        bytes memory data = script.migrateLegacyWithdrawQueueData();
        vm.store(address(proxy), bytes32(ETHENA_LEGACY_COOLDOWN_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_LegacyEthenaCooldownPending() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        proxy.upgradeTo(address(newImpl));
        vm.store(address(proxy), bytes32(ETHENA_LEGACY_COOLDOWN_AMOUNT_SLOT), bytes32(uint256(1 ether)));

        vm.expectRevert(EthenaARM.LegacyEthenaCooldownPending.selector);
        EthenaARM(address(proxy)).migrateLegacyWithdrawQueue();
    }

    function test_RevertWhen_UpgradeToAndCall_LegacyWithdrawQueuePending() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        bytes memory data = script.migrateLegacyWithdrawQueueData();
        vm.store(
            address(proxy), bytes32(LEGACY_PACKED_WITHDRAW_QUEUE_SLOT), bytes32(_packLegacyWithdrawQueue(1 ether, 0))
        );

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImpl), data);
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_CalledTwice() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();

        proxy.upgradeToAndCall(address(newImpl), script.migrateLegacyWithdrawQueueData());

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        EthenaARM(address(proxy)).migrateLegacyWithdrawQueue();
    }

    function test_RevertWhen_MigrateLegacyWithdrawQueue_CalledByNonOwner() external {
        (Proxy proxy, EthenaARM newImpl) = _deployInitializedEthenaARMProxy();
        proxy.upgradeTo(address(newImpl));

        vm.prank(makeAddr("not owner"));
        vm.expectRevert(bytes4(keccak256("OnlyOwner()")));
        EthenaARM(address(proxy)).migrateLegacyWithdrawQueue();
    }

    function _packLegacyWithdrawQueue(uint128 queued, uint128 claimed) internal pure returns (uint256) {
        return uint256(queued) | (uint256(claimed) << 128);
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
