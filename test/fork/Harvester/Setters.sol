/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Harvester} from "contracts/Harvester.sol";

import {Fork_Shared_Test} from "test/fork/Harvester/shared/Shared.sol";

contract Fork_Concrete_Harvester_Setters_Test_ is Fork_Shared_Test {
    ////////////////////////////////////////////////////
    /// --- REVERTS
    ////////////////////////////////////////////////////
    function test_RevertWhen_SetAllowedSlippage_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        harvester.setAllowedSlippage(1000);
    }

    function test_RevertWhen_SetAllowedSlippage_Because_InvalidAllowedSlippage() public {
        vm.expectRevert(abi.encodeWithSelector(Harvester.InvalidAllowedSlippage.selector, 1001));
        vm.prank(governor);
        harvester.setAllowedSlippage(1001);
    }

    function test_RevertWhen_SetPriceProvider_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        harvester.setPriceProvider(address(0));
    }

    function test_RevertWhen_SetRewardRecipient_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        harvester.setRewardRecipient(address(0x1));
    }

    function test_RevertWhen_SetRewardRecipient_Because_EmptyRewardRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(Harvester.EmptyRewardRecipient.selector));
        vm.prank(governor);
        harvester.setRewardRecipient(address(0));
    }

    function test_RevertWhen_SetSupportedStrategy_Because_NotOwner() public {
        vm.expectRevert("ARM: Only owner can call this function.");
        vm.prank(operator);
        harvester.setSupportedStrategy(address(0x1234), true);
    }

    ////////////////////////////////////////////////////
    /// --- TESTS
    ////////////////////////////////////////////////////

    function test_SetAllowedSlippage() public {
        uint256 newSlippage = 987;
        assertNotEq(harvester.allowedSlippageBps(), newSlippage);

        vm.expectEmit(address(harvester));
        emit Harvester.AllowedSlippageUpdated(newSlippage);

        vm.prank(governor);
        harvester.setAllowedSlippage(newSlippage);
        assertEq(harvester.allowedSlippageBps(), newSlippage);
    }

    function test_SetPriceProvider() public {
        assertNotEq(harvester.priceProvider(), address(0x1));

        // To address 0x1
        vm.expectEmit(address(harvester));
        emit Harvester.PriceProviderUpdated(address(0x1));

        vm.prank(governor);
        harvester.setPriceProvider(address(0x1));
        assertEq(harvester.priceProvider(), address(0x1));

        // To address null
        vm.expectEmit(address(harvester));
        emit Harvester.PriceProviderUpdated(address(0));

        vm.prank(governor);
        harvester.setPriceProvider(address(0));
        assertEq(harvester.priceProvider(), address(0));
    }

    function test_SetRewardRecipient() public {
        address newRecipient = address(0x1234);
        assertNotEq(harvester.rewardRecipient(), newRecipient);

        vm.expectEmit(address(harvester));
        emit Harvester.RewardRecipientUpdated(newRecipient);

        vm.prank(governor);
        harvester.setRewardRecipient(newRecipient);
        assertEq(harvester.rewardRecipient(), newRecipient);
    }

    function test_SetSupportedStrategy_AddStrategy() public {
        address strategy = address(0x1234);
        assertFalse(harvester.supportedStrategies(strategy));

        vm.expectEmit(address(harvester));
        emit Harvester.SupportedStrategyUpdate(strategy, true);

        vm.prank(governor);
        harvester.setSupportedStrategy(strategy, true);
        assertTrue(harvester.supportedStrategies(strategy));
    }

    function test_SetSupportedStrategy_RemoveStrategy() public {
        address strategy = address(0x1234);

        // Add the strategy first
        vm.prank(governor);
        harvester.setSupportedStrategy(strategy, true);
        assertTrue(harvester.supportedStrategies(strategy));

        // Now remove the strategy
        vm.expectEmit(address(harvester));
        emit Harvester.SupportedStrategyUpdate(strategy, false);

        vm.prank(governor);
        harvester.setSupportedStrategy(strategy, false);
        assertFalse(harvester.supportedStrategies(strategy));
    }
}
