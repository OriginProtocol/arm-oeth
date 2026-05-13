/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EtherFiARM/shared/Shared.sol";

// Interfaces
import {IWeETH} from "contracts/Interfaces.sol";

contract Fork_Concrete_EtherFiARM_RequestWithdraw_Test_ is Fork_Shared_Test {
    function test_DelayWithdraw() public {
        // Fund the ARM with eETH from weETH
        vm.prank(address(weeth));
        eeth.transfer(address(etherfiARM), 10 ether);

        // Request a withdrawal
        vm.prank(operator);
        etherfiARM.requestRedeem(address(eeth), 1 ether);
        uint256 requestId = etherfiAssetAdapter.pendingRequestId(0);

        // Process finalization on withdrawal queue
        // We cheat a bit here, because we don't follow the full finalization process it could fail
        // if there is not enough liquidity, but since the amount to claim is low, it should be fine
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705);
        etherfiWithdrawalNFT.finalizeRequests(requestId);

        // Claim the withdrawal
        vm.prank(operator);
        etherfiARM.claimRedeem(address(eeth), 1 ether);
    }

    function test_WeETH_ConvertToAssets_And_ConvertToShares() public view {
        uint256 weethAmount = 1 ether;
        uint256 eethAmount = IWeETH(address(weeth)).getEETHByWeETH(weethAmount);

        assertEq(weethAssetAdapter.convertToAssets(weethAmount), eethAmount, "convertToAssets");
        assertEq(
            weethAssetAdapter.convertToShares(eethAmount),
            IWeETH(address(weeth)).getWeETHByeETH(eethAmount),
            "convertToShares"
        );
    }

    function test_WeETH_RequestAndClaimRedeem() public {
        uint256 weethAmount = 1 ether;
        uint256 eethExpected = IWeETH(address(weeth)).getEETHByWeETH(weethAmount);

        deal(address(weeth), address(etherfiARM), weethAmount);

        vm.prank(operator);
        (uint256 sharesRequested, uint256 assetsExpected) = etherfiARM.requestRedeem(address(weeth), weethAmount);

        assertEq(sharesRequested, weethAmount, "shares requested");
        assertEq(assetsExpected, eethExpected, "assets expected");
        assertEq(weeth.balanceOf(address(etherfiARM)), 0, "ARM weETH balance");

        (,,,,, uint120 pendingRedeemAssets,,) = etherfiARM.baseAssetConfigs(address(weeth));
        assertEq(pendingRedeemAssets, eethExpected, "pending redeem assets");

        uint256 requestId = weethAssetAdapter.pendingRequestId(0);
        assertEq(weethAssetAdapter.requestShares(requestId), weethAmount, "request shares");
        assertEq(weethAssetAdapter.requestAssets(requestId), eethExpected, "request assets");

        // Process finalization on withdrawal queue. This follows the existing EtherFi fork-test shortcut.
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705);
        etherfiWithdrawalNFT.finalizeRequests(requestId);

        uint256 wethBefore = weth.balanceOf(address(etherfiARM));

        vm.prank(operator);
        (uint256 sharesClaimed, uint256 claimAssetsExpected, uint256 assetsReceived) =
            etherfiARM.claimRedeem(address(weeth), weethAmount);

        assertEq(sharesClaimed, weethAmount, "shares claimed");
        assertEq(claimAssetsExpected, eethExpected, "claim assets expected");
        assertEq(assetsReceived, weth.balanceOf(address(etherfiARM)) - wethBefore, "assets received");

        (,,,,, pendingRedeemAssets,,) = etherfiARM.baseAssetConfigs(address(weeth));
        assertEq(pendingRedeemAssets, 0, "pending redeem assets after claim");
    }
}
