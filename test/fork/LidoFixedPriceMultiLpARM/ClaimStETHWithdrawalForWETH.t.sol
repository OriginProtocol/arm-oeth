// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

// Contracts
import {IERC20} from "contracts/Interfaces.sol";
import {IStETHWithdrawal} from "contracts/Interfaces.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoFixedPriceMultiLpARM_RequestStETHWithdrawalForETH_Test_ is Fork_Shared_Test_ {
    uint256[] amounts0;
    uint256[] amounts1;
    uint256[] amounts2;

    IStETHWithdrawal public stETHWithdrawal = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL);
    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////

    function setUp() public override {
        super.setUp();

        deal(address(steth), address(lidoFixedPriceMultiLpARM), 10_000 ether);

        amounts0 = new uint256[](0);

        amounts1 = new uint256[](1);
        amounts1[0] = DEFAULT_AMOUNT;

        amounts2 = new uint256[](2);
        amounts2[0] = DEFAULT_AMOUNT;
        amounts2[1] = DEFAULT_AMOUNT;
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_ClaimStETHWithdrawalForWETH_EmptyList()
        public
        asLidoFixedPriceMulltiLpARMOperator
        requestStETHWithdrawalForETHOnLidoFixedPriceMultiLpARM(new uint256[](0))
    {
        assertEq(address(lidoFixedPriceMultiLpARM).balance, 0);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);

        // Main call
        lidoFixedPriceMultiLpARM.claimStETHWithdrawalForWETH(new uint256[](0));

        assertEq(address(lidoFixedPriceMultiLpARM).balance, 0);
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
    }

    function test_ClaimStETHWithdrawalForWETH_SingleRequest()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoFixedPriceMultiLpARM
        requestStETHWithdrawalForETHOnLidoFixedPriceMultiLpARM(amounts1)
        mockFunctionClaimWithdrawOnLidoFixedPriceMultiLpARM(DEFAULT_AMOUNT)
    {
        // Assertions before
        uint256 balanceBefore = weth.balanceOf(address(lidoFixedPriceMultiLpARM));
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), DEFAULT_AMOUNT);

        stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](1);
        requests[0] = stETHWithdrawal.getLastRequestId();
        // Main call
        lidoFixedPriceMultiLpARM.claimStETHWithdrawalForWETH(requests);

        // Assertions after
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), balanceBefore + DEFAULT_AMOUNT);
    }

    function test_ClaimStETHWithdrawalForWETH_MultiRequest()
        public
        asLidoFixedPriceMulltiLpARMOperator
        approveStETHOnLidoFixedPriceMultiLpARM
        requestStETHWithdrawalForETHOnLidoFixedPriceMultiLpARM(amounts2)
        mockCallLidoFindCheckpointHints
        mockFunctionClaimWithdrawOnLidoFixedPriceMultiLpARM(amounts2[0] + amounts2[1])
    {
        // Assertions before
        uint256 balanceBefore = weth.balanceOf(address(lidoFixedPriceMultiLpARM));
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), amounts2[0] + amounts2[1]);

        stETHWithdrawal.getLastRequestId();
        uint256[] memory requests = new uint256[](2);
        requests[0] = stETHWithdrawal.getLastRequestId() - 1;
        requests[1] = stETHWithdrawal.getLastRequestId();
        // Main call
        lidoFixedPriceMultiLpARM.claimStETHWithdrawalForWETH(requests);

        // Assertions after
        assertEq(lidoFixedPriceMultiLpARM.outstandingEther(), 0);
        assertEq(weth.balanceOf(address(lidoFixedPriceMultiLpARM)), balanceBefore + amounts2[0] + amounts2[1]);
    }
}