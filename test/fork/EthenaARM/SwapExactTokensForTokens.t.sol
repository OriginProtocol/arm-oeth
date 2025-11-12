/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {EthenaARM} from "contracts/EthenaARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_EthenaARM_swapExactTokensForTokens_Test_ is Fork_Shared_Test {
    uint256 public AMOUNT_IN = 100 ether;

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function test_swapExactTokensForTokens_USDE_To_SUSDE_Sig1() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate0();
        uint256 expectedAmountOut = (susde.convertToShares(AMOUNT_IN) * 1e36) / traderate;

        // Expected events
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), AMOUNT_IN);
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), expectedAmountOut);

        // Perform the swap
        uint256[] memory obtained =
            ethenaARM.swapExactTokensForTokens(usde, IERC20(address(susde)), AMOUNT_IN, 0, address(this));

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], AMOUNT_IN, "Obtained USDe amount should match input");
        assertEq(obtained[1], expectedAmountOut, "Obtained SUSDe amount should match expected output");
        assertEq(usdeBalanceBefore, usdeBalanceAfter + AMOUNT_IN, "USDe balance should have decreased");
        assertEq(susdeBalanceAfter, susdeBalanceBefore + expectedAmountOut, "SUSDe balance should have increased");
    }

    function test_swapExactTokensForTokens_SUSDE_To_USDE_NoOutstandingWithdrawals_Sig1() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate1();
        uint256 expectedAmountOut = (susde.convertToAssets(AMOUNT_IN) * traderate) / 1e36;

        // Expected events
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), AMOUNT_IN);
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), expectedAmountOut);

        // Perform the swap
        uint256[] memory obtained =
            ethenaARM.swapExactTokensForTokens(IERC20(address(susde)), usde, AMOUNT_IN, 0, address(this));

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], AMOUNT_IN, "Obtained SUSDe amount should match input");
        assertEq(obtained[1], expectedAmountOut, "Obtained USDe amount should match expected output");
        assertEq(usdeBalanceAfter, usdeBalanceBefore + expectedAmountOut, "USDe balance should have increased");
        assertEq(susdeBalanceBefore, susdeBalanceAfter + AMOUNT_IN, "SUSDe balance should have decreased");
    }

    function test_swapExactTokensForTokens_USDE_To_SUSDE_Sig2() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate0();
        uint256 expectedAmountOut = (susde.convertToShares(AMOUNT_IN) * 1e36) / traderate;

        // Expected events
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), AMOUNT_IN);
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), expectedAmountOut);

        // Perform the swap
        address[] memory path = new address[](2);
        path[0] = address(usde);
        path[1] = address(susde);

        uint256[] memory obtained =
            ethenaARM.swapExactTokensForTokens(AMOUNT_IN, 0, path, address(this), block.timestamp + 1 hours);

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], AMOUNT_IN, "Obtained USDe amount should match input");
        assertEq(obtained[1], expectedAmountOut, "Obtained SUSDe amount should match expected output");
        assertEq(usdeBalanceBefore, usdeBalanceAfter + AMOUNT_IN, "USDe balance should have decreased");
        assertEq(susdeBalanceAfter, susdeBalanceBefore + expectedAmountOut, "SUSDe balance should have increased");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidInToken() public {
        vm.expectRevert(bytes("EthenaARM: Invalid token"));
        ethenaARM.swapExactTokensForTokens(badToken, usde, AMOUNT_IN, 0, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidOutToken() public {
        vm.expectRevert(bytes("ARM: Invalid out token"));
        ethenaARM.swapExactTokensForTokens(usde, badToken, AMOUNT_IN, 0, address(this));

        vm.expectRevert(bytes("ARM: Invalid out token"));
        ethenaARM.swapExactTokensForTokens(IERC20(address(susde)), badToken, AMOUNT_IN, 0, address(this));
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InsufficientOutputAmount() public {
        uint256 highMinAmountOut = 1_000_000 ether;

        vm.expectRevert(bytes("ARM: Insufficient output amount"));
        ethenaARM.swapExactTokensForTokens(IERC20(address(susde)), usde, AMOUNT_IN, highMinAmountOut, address(this));

        vm.expectRevert(bytes("ARM: Insufficient output amount"));
        ethenaARM.swapExactTokensForTokens(usde, IERC20(address(susde)), AMOUNT_IN, highMinAmountOut, address(this));

        address[] memory path = new address[](2);
        path[0] = address(usde);
        path[1] = address(susde);

        vm.expectRevert(bytes("ARM: Insufficient output amount"));
        ethenaARM.swapExactTokensForTokens(AMOUNT_IN, highMinAmountOut, path, address(this), block.timestamp + 1 hours);
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_DeadlineExpired() public {
        uint256 pastDeadline = block.timestamp - 1;
        address[] memory path = new address[](2);
        path[0] = address(susde);
        path[1] = address(usde);

        vm.expectRevert(bytes("ARM: Deadline expired"));
        ethenaARM.swapExactTokensForTokens(AMOUNT_IN, 0, path, address(this), pastDeadline);
    }

    function test_RevertWhen_swapExactTokensForTokens_Because_InvalidePathLength() public {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(susde);

        vm.expectRevert(bytes("ARM: Invalid path length"));
        ethenaARM.swapExactTokensForTokens(AMOUNT_IN, 0, shortPath, address(this), block.timestamp + 1 hours);

        address[] memory longPath = new address[](3);
        longPath[0] = address(susde);
        longPath[1] = address(usde);
        longPath[2] = address(susde);

        vm.expectRevert(bytes("ARM: Invalid path length"));
        ethenaARM.swapExactTokensForTokens(AMOUNT_IN, 0, longPath, address(this), block.timestamp + 1 hours);
    }
}
