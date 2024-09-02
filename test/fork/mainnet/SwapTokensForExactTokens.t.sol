// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Interfaces
import {IERC20} from "contracts/Interfaces.sol";

/// @notice The purpose of this contract is to test the `swapTokensForExactTokens` function in the `OethARM` contract.
contract Fork_Concrete_OethARM_SwapTokensForExactTokens_Test_ is Fork_Shared_Test_ {
    address[] path;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        path = new address[](2);
        path[0] = address(oeth);
        path[1] = address(weth);

        // Deal tokens
        deal(address(oeth), address(this), 100 ether);
        deal(address(weth), address(oethARM), 100 ether);
        deal(address(oeth), address(oethARM), 100 ether);

        // Approve tokens
        oeth.approve(address(oethARM), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////

    function test_RevertWhen_SwapTokensForExactTokens_Simple_Because_InsufficientOutputAmount() public {
        vm.expectRevert("ARM: Excess input amount");
        oethARM.swapTokensForExactTokens(oeth, weth, 10 ether, 9 ether, address(this));
    }

    function test_RevertWhen_SwapTokensForExactTokens_Simple_Because_InvalidSwap_TokenIn() public {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(weth, weth, 10 ether, 10 ether, address(this));
    }

    function test_RevertWhen_SwapTokensForExactTokens_Simple_Because_InvalidSwap_TokenOut() public {
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(oeth, oeth, 10 ether, 10 ether, address(this));
    }

    function test_RevertWhen_SwapTokensForExactTokens_Complex_Because_InsufficientOutputAmount() public {
        vm.expectRevert("ARM: Excess input amount");
        oethARM.swapTokensForExactTokens(10 ether, 9 ether, path, address(this), block.timestamp + 10);
    }

    function test_RevertWhen_SwapTokensForExactTokens_Complex_Because_InvalidPathLength() public {
        vm.expectRevert("ARM: Invalid path length");
        oethARM.swapTokensForExactTokens(10 ether, 10 ether, new address[](3), address(this), block.timestamp + 10);
    }

    function test_RevertWhen_SwapTokensForExactTokens_Complex_Because_DeadlineExpired() public {
        vm.expectRevert("ARM: Deadline expired");
        oethARM.swapTokensForExactTokens(10 ether, 10 ether, path, address(this), block.timestamp - 1);
    }

    function test_RevertWhen_SwapTokensForExactTokens_Complex_Because_InvalidSwap_TokenIn() public {
        path[0] = address(weth);
        path[1] = address(weth);
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(10 ether, 10 ether, path, address(this), block.timestamp + 10);
    }

    function test_RevertWhen_SwapTokensForExactTokens_Complex_Because_InvalidSwap_TokenOut() public {
        path[0] = address(oeth);
        path[1] = address(oeth);
        vm.expectRevert("ARM: Invalid swap");
        oethARM.swapTokensForExactTokens(10 ether, 10 ether, path, address(this), block.timestamp + 10);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_SwapTokensForExactTokens_Simple() public {
        // Assertions before
        assertEq(weth.balanceOf(address(this)), 0 ether, "WETH balance user");
        assertEq(oeth.balanceOf(address(this)), 100 ether, "OETH balance user");
        assertEq(weth.balanceOf(address(oethARM)), 100 ether, "OETH balance ARM");
        assertEq(weth.balanceOf(address(oethARM)), 100 ether, "WETH balance ARM");

        // Expected events
        vm.expectEmit({emitter: address(oeth)});
        emit IERC20.Transfer(address(this), address(oethARM), 10 ether);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(oethARM), address(this), 10 ether);
        // Main call
        oethARM.swapTokensForExactTokens(oeth, weth, 10 ether, 10 ether, address(this));

        // Assertions after
        assertEq(weth.balanceOf(address(this)), 10 ether, "WETH balance user");
        assertEq(oeth.balanceOf(address(this)), 90 ether, "OETH balance");
        assertEq(weth.balanceOf(address(oethARM)), 90 ether, "WETH balance ARM");
        assertEq(oeth.balanceOf(address(oethARM)), 110 ether, "OETH balance ARM");
    }

    function test_SwapTokensForExactTokens_Complex() public {
        // Assertions before
        assertEq(weth.balanceOf(address(this)), 0 ether, "WETH balance user");
        assertEq(oeth.balanceOf(address(this)), 100 ether, "OETH balance user");
        assertEq(weth.balanceOf(address(oethARM)), 100 ether, "OETH balance ARM");
        assertEq(weth.balanceOf(address(oethARM)), 100 ether, "WETH balance ARM");

        path[0] = address(oeth);
        path[1] = address(weth);
        // Expected events
        vm.expectEmit({emitter: address(oeth)});
        emit IERC20.Transfer(address(this), address(oethARM), 10 ether);
        vm.expectEmit({emitter: address(weth)});
        emit IERC20.Transfer(address(oethARM), address(this), 10 ether);
        // Main call
        uint256[] memory amounts =
            oethARM.swapTokensForExactTokens(10 ether, 10 ether, path, address(this), block.timestamp + 1000);

        // Assertions after
        assertEq(amounts[0], 10 ether, "Amounts[0]");
        assertEq(amounts[1], 10 ether, "Amounts[1]");
        assertEq(weth.balanceOf(address(this)), 10 ether, "WETH balance user");
        assertEq(oeth.balanceOf(address(this)), 90 ether, "OETH balance");
        assertEq(weth.balanceOf(address(oethARM)), 90 ether, "WETH balance ARM");
        assertEq(oeth.balanceOf(address(oethARM)), 110 ether, "OETH balance ARM");
    }
}
