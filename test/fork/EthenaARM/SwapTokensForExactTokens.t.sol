/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EthenaARM/shared/Shared.sol";

// Contracts
import {EthenaARM} from "contracts/EthenaARM.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

contract Fork_Concrete_EthenaARM_swapTokensForExactTokens_Test_ is Fork_Shared_Test {
    uint256 public AMOUNT_OUT = 100 ether;

    //////////////////////////////////////////////////////
    /// --- TESTS
    //////////////////////////////////////////////////////
    function test_swapTokensForExactTokens_USDE_To_SUSDE_Sig1() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate0();
        uint256 expectedAmountIn = ((susde.convertToAssets(AMOUNT_OUT) * 1e36) / traderate) + 3;

        // Expected events
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), expectedAmountIn);
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), AMOUNT_OUT);

        // Perform the swap
        uint256[] memory obtained = ethenaARM.swapTokensForExactTokens(
            usde, IERC20(address(susde)), AMOUNT_OUT, type(uint256).max, address(this)
        );

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], expectedAmountIn, "Obtained USDe amount should match expected input");
        assertEq(obtained[1], AMOUNT_OUT, "Obtained SUSDe amount should match expected output");
        assertEq(usdeBalanceBefore, usdeBalanceAfter + expectedAmountIn, "USDe balance should have decreased");
        assertEq(susdeBalanceAfter, susdeBalanceBefore + AMOUNT_OUT, "SUSDe balance should have increased");
    }

    function test_swapTokensForExactTokens_USDE_To_SUSDE_Sig2() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate0();
        uint256 expectedAmountIn = ((susde.convertToAssets(AMOUNT_OUT) * 1e36) / traderate) + 3;

        address[] memory path = new address[](2);
        path[0] = address(usde);
        path[1] = address(susde);

        // Expected events
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), expectedAmountIn);
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), AMOUNT_OUT);

        // Perform the swap
        uint256[] memory obtained = ethenaARM.swapTokensForExactTokens(
            AMOUNT_OUT, type(uint256).max, path, address(this), block.timestamp + 1 hours
        );

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], expectedAmountIn, "Obtained USDe amount should match expected input");
        assertEq(obtained[1], AMOUNT_OUT, "Obtained SUSDe amount should match expected output");
        assertEq(usdeBalanceBefore, usdeBalanceAfter + expectedAmountIn, "USDe balance should have decreased");
        assertEq(susdeBalanceAfter, susdeBalanceBefore + AMOUNT_OUT, "SUSDe balance should have increased");
    }

    function test_swapTokensForExactTokens_SUSDE_To_USDE_NoOutstandingWithdrawals_Sig1() public {
        // Record balances before swap
        uint256 usdeBalanceBefore = usde.balanceOf(address(this));
        uint256 susdeBalanceBefore = susde.balanceOf(address(this));

        // Precompute expected amount out
        uint256 traderate = ethenaARM.traderate1();
        uint256 expectedAmountIn = (susde.convertToShares(AMOUNT_OUT) * 1e36) / traderate + 3;

        // Expected events
        vm.expectEmit({emitter: address(susde)});
        emit IERC20.Transfer(address(this), address(ethenaARM), expectedAmountIn);
        vm.expectEmit({emitter: address(usde)});
        emit IERC20.Transfer(address(ethenaARM), address(this), AMOUNT_OUT);

        // Perform the swap
        uint256[] memory obtained = ethenaARM.swapTokensForExactTokens(
            IERC20(address(susde)), usde, AMOUNT_OUT, type(uint256).max, address(this)
        );

        // Record balances after swap
        uint256 usdeBalanceAfter = usde.balanceOf(address(this));
        uint256 susdeBalanceAfter = susde.balanceOf(address(this));

        // Assertions
        assertEq(obtained[0], expectedAmountIn, "Obtained USDe amount should match expected input");
        assertEq(obtained[1], AMOUNT_OUT, "Obtained SUSDe amount should match expected output");
        assertEq(susdeBalanceBefore, susdeBalanceAfter + expectedAmountIn, "SUSDe balance should have decreased");
        assertEq(usdeBalanceAfter, usdeBalanceBefore + AMOUNT_OUT, "USDe balance should have increased");
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidInToken() public {
        vm.expectRevert(bytes("ARM: Invalid in token"));
        ethenaARM.swapTokensForExactTokens(badToken, usde, AMOUNT_OUT, 0, address(this));
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidOutToken() public {
        vm.expectRevert(bytes("EthenaARM: Invalid token"));
        ethenaARM.swapTokensForExactTokens(usde, badToken, AMOUNT_OUT, 0, address(this));

        vm.expectRevert(bytes("EthenaARM: Invalid token"));
        ethenaARM.swapTokensForExactTokens(IERC20(address(susde)), badToken, AMOUNT_OUT, 0, address(this));
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_InsufficientOutputAmount() public {
        uint256 lowMaxAmountIn = 10 ether;

        vm.expectRevert(bytes("ARM: Excess input amount"));
        ethenaARM.swapTokensForExactTokens(IERC20(address(susde)), usde, AMOUNT_OUT, lowMaxAmountIn, address(this));

        vm.expectRevert(bytes("ARM: Excess input amount"));
        ethenaARM.swapTokensForExactTokens(usde, IERC20(address(susde)), AMOUNT_OUT, lowMaxAmountIn, address(this));

        address[] memory path = new address[](2);
        path[0] = address(usde);
        path[1] = address(susde);

        vm.expectRevert(bytes("ARM: Excess input amount"));
        ethenaARM.swapTokensForExactTokens(AMOUNT_OUT, lowMaxAmountIn, path, address(this), block.timestamp + 1 hours);
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_DeadlineExpired() public {
        uint256 pastDeadline = block.timestamp - 1;
        address[] memory path = new address[](2);
        path[0] = address(susde);
        path[1] = address(usde);

        vm.expectRevert(bytes("ARM: Deadline expired"));
        ethenaARM.swapTokensForExactTokens(AMOUNT_OUT, type(uint256).max, path, address(this), pastDeadline);
    }

    function test_RevertWhen_swapTokensForExactTokens_Because_InvalidePathLength() public {
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(susde);

        vm.expectRevert(bytes("ARM: Invalid path length"));
        ethenaARM.swapTokensForExactTokens(AMOUNT_OUT, 0, shortPath, address(this), block.timestamp + 1 hours);

        address[] memory longPath = new address[](3);
        longPath[0] = address(susde);
        longPath[1] = address(usde);
        longPath[2] = address(susde);

        vm.expectRevert(bytes("ARM: Invalid path length"));
        ethenaARM.swapTokensForExactTokens(AMOUNT_OUT, 0, longPath, address(this), block.timestamp + 1 hours);
    }
}
