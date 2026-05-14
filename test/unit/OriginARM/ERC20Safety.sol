// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {OriginARM} from "contracts/OriginARM.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {IERC20} from "contracts/Interfaces.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {MockFalseReturnERC20} from "test/unit/mocks/MockFalseReturnERC20.sol";

contract Unit_Concrete_OriginARM_ERC20Safety_Test_ is Unit_Shared_Test {
    function test_RevertWhen_Deposit_TransferFromReturnsFalse() public {
        deal(address(weth), alice, DEFAULT_AMOUNT);

        vm.prank(alice);
        weth.approve(address(originARM), DEFAULT_AMOUNT);

        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(originARM), DEFAULT_AMOUNT),
            abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.deposit(DEFAULT_AMOUNT);

        assertEq(originARM.balanceOf(alice), 0, "shares minted");
    }

    function test_RevertWhen_SwapExactTokensForTokens_InputTransferFromReturnsFalse() public {
        uint256 amountIn = DEFAULT_AMOUNT;
        deal(address(oeth), alice, amountIn);
        deal(address(weth), address(originARM), DEFAULT_AMOUNT);

        vm.prank(alice);
        oeth.approve(address(originARM), amountIn);

        vm.mockCall(
            address(oeth),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(originARM), amountIn),
            abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(oeth)));
        originARM.swapExactTokensForTokens(oeth, weth, amountIn, 0, alice);
    }

    function test_RevertWhen_SwapExactTokensForTokens_OutputTransferReturnsFalse() public {
        uint256 amountIn = DEFAULT_AMOUNT;
        uint256 amountOut = amountIn * _buyPrice(address(oeth)) / originARM.PRICE_SCALE();
        deal(address(oeth), alice, amountIn);
        deal(address(weth), address(originARM), amountOut);

        vm.prank(alice);
        oeth.approve(address(originARM), amountIn);

        vm.mockCall(
            address(weth), abi.encodeWithSelector(IERC20.transfer.selector, alice, amountOut), abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.swapExactTokensForTokens(oeth, weth, amountIn, 0, alice);
    }

    function test_RevertWhen_SwapTokensForExactTokens_InputTransferFromReturnsFalse() public {
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        uint256 amountIn = amountOut * originARM.PRICE_SCALE() / _buyPrice(address(oeth)) + 3;
        deal(address(oeth), alice, amountIn);
        deal(address(weth), address(originARM), amountOut);

        vm.prank(alice);
        oeth.approve(address(originARM), amountIn);

        vm.mockCall(
            address(oeth),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(originARM), amountIn),
            abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(oeth)));
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, alice);
    }

    function test_RevertWhen_SwapTokensForExactTokens_OutputTransferReturnsFalse() public {
        uint256 amountOut = DEFAULT_AMOUNT / 2;
        uint256 amountIn = amountOut * originARM.PRICE_SCALE() / _buyPrice(address(oeth)) + 3;
        deal(address(oeth), alice, amountIn);
        deal(address(weth), address(originARM), amountOut);

        vm.prank(alice);
        oeth.approve(address(originARM), amountIn);

        vm.mockCall(
            address(weth), abi.encodeWithSelector(IERC20.transfer.selector, alice, amountOut), abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.swapTokensForExactTokens(oeth, weth, amountOut, type(uint256).max, alice);
    }

    function test_RevertWhen_ClaimRedeem_TransferReturnsFalse() public deposit(alice, DEFAULT_AMOUNT) {
        uint256 shares = originARM.balanceOf(alice);

        vm.prank(alice);
        (uint256 requestId,) = originARM.requestRedeem(shares);

        vm.warp(block.timestamp + CLAIM_DELAY);
        vm.mockCall(
            address(weth), abi.encodeWithSelector(IERC20.transfer.selector, alice, DEFAULT_AMOUNT), abi.encode(false)
        );

        vm.prank(alice);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.claimRedeem(requestId);
    }

    function test_RevertWhen_CollectFees_TransferReturnsFalse() public {
        deal(address(weth), address(originARM), DEFAULT_AMOUNT);
        deal(address(oeth), bob, DEFAULT_AMOUNT);

        vm.startPrank(bob);
        oeth.approve(address(originARM), DEFAULT_AMOUNT);
        originARM.swapExactTokensForTokens(oeth, weth, DEFAULT_AMOUNT, 0, bob);
        vm.stopPrank();

        uint256 fees = originARM.feesAccrued();
        vm.mockCall(
            address(weth), abi.encodeWithSelector(IERC20.transfer.selector, feeCollector, fees), abi.encode(false)
        );

        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.collectFees();
    }

    function test_RevertWhen_AddBaseAsset_ApproveReturnsFalse() public {
        MockERC20 newBaseAsset = new MockERC20("New Base", "NEW", 18);
        OriginAssetAdapter adapter =
            new OriginAssetAdapter(address(originARM), address(newBaseAsset), address(weth), address(vault));

        vm.mockCall(
            address(newBaseAsset),
            abi.encodeWithSelector(IERC20.approve.selector, address(adapter), type(uint256).max),
            abi.encode(false)
        );

        vm.prank(governor);
        vm.expectRevert(_safeERC20FailedOperation(address(newBaseAsset)));
        originARM.addBaseAsset(
            address(newBaseAsset),
            address(adapter),
            992 * 1e33,
            1001 * 1e33,
            type(uint128).max,
            type(uint128).max,
            1e36,
            true
        );
    }

    function test_RevertWhen_Allocate_ApproveReturnsFalse() public {
        uint256 depositAmount = 2 ether;
        address[] memory markets = new address[](1);
        markets[0] = address(market);

        vm.prank(governor);
        originARM.addMarkets(markets);

        deal(address(weth), address(originARM), depositAmount);
        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(IERC20.approve.selector, address(market), depositAmount),
            abi.encode(false)
        );

        vm.prank(governor);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.setActiveMarket(address(market));
    }

    function test_RevertWhen_AdapterRequestRedeem_TransferFromReturnsFalse() public {
        uint256 shares = DEFAULT_AMOUNT;
        deal(address(oeth), address(originARM), shares);

        vm.mockCall(
            address(oeth),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(originARM), address(originAssetAdapter), shares),
            abi.encode(false)
        );

        vm.prank(governor);
        vm.expectRevert(_safeERC20FailedOperation(address(oeth)));
        originARM.requestBaseAssetRedeem(address(oeth), shares);
    }

    function test_RevertWhen_AdapterRedeem_TransferReturnsFalse() public {
        uint256 shares = DEFAULT_AMOUNT;
        deal(address(oeth), address(originARM), shares);

        vm.prank(governor);
        originARM.requestBaseAssetRedeem(address(oeth), shares);

        deal(address(weth), address(vault), shares);
        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(IERC20.transfer.selector, address(originARM), shares),
            abi.encode(false)
        );

        vm.prank(governor);
        vm.expectRevert(_safeERC20FailedOperation(address(weth)));
        originARM.claimBaseAssetRedeem(address(oeth), shares);
    }

    function test_RevertWhen_AdapterConstructor_ApproveReturnsFalse() public {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20("False", "FALSE", 18);
        falseToken.setApproveReturnsFalse(true);

        vm.expectRevert(_safeERC20FailedOperation(address(falseToken)));
        new OriginAssetAdapter(address(originARM), address(falseToken), address(weth), address(vault));
    }

    function test_RevertWhen_AdapterInitialize_ApproveReturnsFalse() public {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20("False", "FALSE", 18);
        OriginAssetAdapter adapter =
            new OriginAssetAdapter(address(originARM), address(falseToken), address(weth), address(vault));
        falseToken.setApproveReturnsFalse(true);

        vm.expectRevert(_safeERC20FailedOperation(address(falseToken)));
        adapter.initialize();
    }

    function _buyPrice(address asset) internal view returns (uint256 buyPrice) {
        (uint128 buyPriceMem,,,,,,,) = originARM.baseAssetConfigs(asset);
        buyPrice = buyPriceMem;
    }

    function _safeERC20FailedOperation(address token) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, token);
    }
}
