// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoOwnerLpARM_TransferToken_Test_ is Fork_Shared_Test_ {
    uint256 public constant ROUNDING = STETH_ERROR_ROUNDING;

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(weth), address(lidoOwnerLpARM), 1_000 ether);
        deal(address(steth), address(lidoOwnerLpARM), 1_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_TransferToken_WETH() public asLidoOwnerLpARMOwner {
        uint256 balanceARMBeforeWETH = weth.balanceOf(address(lidoOwnerLpARM));
        uint256 balanceThisBeforeWETH = weth.balanceOf(address(this));
        lidoOwnerLpARM.transferToken(address(weth), address(this), balanceARMBeforeWETH);

        assertEq(weth.balanceOf(address(this)), balanceThisBeforeWETH + balanceARMBeforeWETH);
        assertEq(weth.balanceOf(address(lidoOwnerLpARM)), 0);
    }

    function test_TransferToken_STETH() public asLidoOwnerLpARMOwner {
        uint256 balanceARMBeforeSTETH = steth.balanceOf(address(lidoOwnerLpARM));
        uint256 balanceThisBeforeSTETH = steth.balanceOf(address(this));
        lidoOwnerLpARM.transferToken(address(steth), address(this), balanceARMBeforeSTETH);

        assertApproxEqAbs(steth.balanceOf(address(this)), balanceThisBeforeSTETH + balanceARMBeforeSTETH, ROUNDING);
        assertApproxEqAbs(steth.balanceOf(address(lidoOwnerLpARM)), 0, ROUNDING);
    }
}
