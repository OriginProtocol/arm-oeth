// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";

import {IERC20} from "contracts/Interfaces.sol";
import {OriginARM} from "contracts/OriginARM.sol";
import {OriginAssetAdapter} from "contracts/adapters/OriginAssetAdapter.sol";
import {Unit_Shared_Test} from "test/unit/shared/Shared.sol";
import {MockVault} from "test/unit/mocks/MockVault.sol";

contract Unit_Concrete_OriginARM_Reentrancy_Test_ is Unit_Shared_Test {
    function test_RevertWhen_BuySideTransferFromReentersSwap() public deposit(alice, 4 * DEFAULT_AMOUNT) {
        ReentrantBaseToken reentrantBase = new ReentrantBaseToken();
        OriginAssetAdapter adapter = new OriginAssetAdapter(
            address(originARM),
            address(reentrantBase),
            address(weth),
            address(new MockVault(IERC20(address(reentrantBase)), weth))
        );

        vm.prank(governor);
        originARM.addBaseAsset(
            address(reentrantBase),
            address(adapter),
            992 * 1e33,
            1001 * 1e33,
            type(uint128).max,
            type(uint128).max,
            1e36,
            true
        );

        uint256 sharesToRedeem = originARM.balanceOf(alice) / 2;
        vm.prank(alice);
        originARM.requestRedeem(sharesToRedeem);

        address swapper = makeAddr("reentrant swapper");
        reentrantBase.mint(swapper, DEFAULT_AMOUNT);
        reentrantBase.mint(address(reentrantBase), DEFAULT_AMOUNT);
        reentrantBase.configure(originARM, weth, swapper, DEFAULT_AMOUNT);

        vm.startPrank(swapper);
        reentrantBase.approve(address(originARM), type(uint256).max);

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        originARM.swapTokensForExactTokens(
            IERC20(address(reentrantBase)), weth, DEFAULT_AMOUNT, type(uint256).max, swapper
        );

        vm.stopPrank();
    }
}

contract ReentrantBaseToken is MockERC20 {
    OriginARM public arm;
    IERC20 public outToken;
    address public recipient;
    uint256 public amountOut;
    bool public reenter;

    constructor() MockERC20("Reentrant OETH", "rOETH", 18) {}

    function configure(OriginARM _arm, IERC20 _outToken, address _recipient, uint256 _amountOut) external {
        arm = _arm;
        outToken = _outToken;
        recipient = _recipient;
        amountOut = _amountOut;
        reenter = true;
        allowance[address(this)][address(_arm)] = type(uint256).max;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (reenter) {
            reenter = false;
            arm.swapTokensForExactTokens(IERC20(address(this)), outToken, amountOut, type(uint256).max, recipient);
        }

        return super.transferFrom(from, to, amount);
    }
}
