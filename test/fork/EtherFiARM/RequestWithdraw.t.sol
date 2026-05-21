/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test
import {Fork_Shared_Test} from "test/fork/EtherFiARM/shared/Shared.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Contracts
import {EtherFiAssetAdapter} from "contracts/adapters/EtherFiAssetAdapter.sol";
import {WeETHAssetAdapter} from "contracts/adapters/WeETHAssetAdapter.sol";

// Interfaces
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IWeETH} from "contracts/Interfaces.sol";

contract Fork_Concrete_EtherFiARM_RequestWithdraw_Test_ is Fork_Shared_Test {
    using stdStorage for StdStorage;

    event WithdrawalNFTRescued(uint256 indexed requestId, address indexed to);

    function test_DelayWithdraw() public {
        // Fund the ARM with eETH from weETH
        vm.prank(address(weeth));
        eeth.transfer(address(etherfiARM), 10 ether);

        // Request a withdrawal
        vm.prank(operator);
        etherfiARM.requestBaseAssetRedeem(address(eeth), 1 ether);
        uint256 requestId = etherfiAssetAdapter.pendingRequestId(0);

        // Process finalization on withdrawal queue
        // We cheat a bit here, because we don't follow the full finalization process it could fail
        // if there is not enough liquidity, but since the amount to claim is low, it should be fine
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705);
        etherfiWithdrawalNFT.finalizeRequests(requestId);

        // Claim the withdrawal
        vm.prank(operator);
        etherfiARM.claimBaseAssetRedeem(address(eeth), 1 ether);
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
        (uint256 sharesRequested, uint256 assetsExpected) =
            etherfiARM.requestBaseAssetRedeem(address(weeth), weethAmount);

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
            etherfiARM.claimBaseAssetRedeem(address(weeth), weethAmount);

        assertEq(sharesClaimed, weethAmount, "shares claimed");
        assertEq(claimAssetsExpected, eethExpected, "claim assets expected");
        assertEq(assetsReceived, weth.balanceOf(address(etherfiARM)) - wethBefore, "assets received");

        (,,,,, pendingRedeemAssets,,) = etherfiARM.baseAssetConfigs(address(weeth));
        assertEq(pendingRedeemAssets, 0, "pending redeem assets after claim");
    }

    function test_EETH_CannotRescueActiveWithdrawalNFT() public {
        vm.prank(address(weeth));
        eeth.transfer(address(etherfiARM), 1 ether);

        vm.prank(operator);
        etherfiARM.requestBaseAssetRedeem(address(eeth), 1 ether);
        uint256 requestId = etherfiAssetAdapter.pendingRequestId(0);

        vm.expectRevert(abi.encodeWithSelector(EtherFiAssetAdapter.ActiveWithdrawalNFT.selector, requestId));
        etherfiAssetAdapter.rescueWithdrawalNFT(requestId, bob);
    }

    function test_EETH_RescueAccidentalWithdrawalNFT() public {
        address recipient = address(0xBEEF);
        uint256 requestId = _requestAdapterEETHWithdrawal();
        _clearEETHAdapterRequest(requestId);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalNFTRescued(requestId, recipient);
        etherfiAssetAdapter.rescueWithdrawalNFT(requestId, recipient);

        assertEq(IERC721(address(etherfiWithdrawalNFT)).ownerOf(requestId), recipient, "rescued NFT owner");
    }

    function test_WeETH_CannotRescueActiveWithdrawalNFT() public {
        uint256 weethAmount = 1 ether;
        deal(address(weeth), address(etherfiARM), weethAmount);

        vm.prank(operator);
        etherfiARM.requestBaseAssetRedeem(address(weeth), weethAmount);
        uint256 requestId = weethAssetAdapter.pendingRequestId(0);

        vm.expectRevert(abi.encodeWithSelector(WeETHAssetAdapter.ActiveWithdrawalNFT.selector, requestId));
        weethAssetAdapter.rescueWithdrawalNFT(requestId, bob);
    }

    function test_WeETH_RescueAccidentalWithdrawalNFT() public {
        address recipient = address(0xBEEF);
        uint256 requestId = _requestAdapterWeETHWithdrawal(1 ether);
        _clearWeETHAdapterRequest(requestId);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalNFTRescued(requestId, recipient);
        weethAssetAdapter.rescueWithdrawalNFT(requestId, recipient);

        assertEq(IERC721(address(etherfiWithdrawalNFT)).ownerOf(requestId), recipient, "rescued NFT owner");
    }

    function test_EETH_OnlyARMOwnerCanRescueWithdrawalNFT() public {
        uint256 requestId = _requestAdapterEETHWithdrawal();
        _clearEETHAdapterRequest(requestId);

        vm.prank(alice);
        vm.expectRevert(EtherFiAssetAdapter.OnlyARMOwner.selector);
        etherfiAssetAdapter.rescueWithdrawalNFT(requestId, bob);
    }

    function _requestAdapterEETHWithdrawal() internal returns (uint256 requestId) {
        vm.prank(address(weeth));
        eeth.transfer(address(etherfiARM), 1 ether);

        vm.prank(operator);
        etherfiARM.requestBaseAssetRedeem(address(eeth), 1 ether);

        requestId = etherfiAssetAdapter.pendingRequestId(0);
        assertEq(IERC721(address(etherfiWithdrawalNFT)).ownerOf(requestId), address(etherfiAssetAdapter), "NFT owner");
    }

    function _requestAdapterWeETHWithdrawal(uint256 weethAmount) internal returns (uint256 requestId) {
        deal(address(weeth), address(etherfiARM), weethAmount);

        vm.prank(operator);
        etherfiARM.requestBaseAssetRedeem(address(weeth), weethAmount);

        requestId = weethAssetAdapter.pendingRequestId(0);
        assertEq(IERC721(address(etherfiWithdrawalNFT)).ownerOf(requestId), address(weethAssetAdapter), "NFT owner");
    }

    function _clearEETHAdapterRequest(uint256 requestId) internal {
        stdstore.target(address(etherfiAssetAdapter)).sig("requestShares(uint256)").with_key(requestId)
            .checked_write(uint256(0));
        assertEq(etherfiAssetAdapter.requestShares(requestId), 0, "request shares cleared");
    }

    function _clearWeETHAdapterRequest(uint256 requestId) internal {
        stdstore.target(address(weethAssetAdapter)).sig("requestShares(uint256)").with_key(requestId)
            .checked_write(uint256(0));
        stdstore.target(address(weethAssetAdapter)).sig("requestAssets(uint256)").with_key(requestId)
            .checked_write(uint256(0));
        assertEq(weethAssetAdapter.requestShares(requestId), 0, "request shares cleared");
        assertEq(weethAssetAdapter.requestAssets(requestId), 0, "request assets cleared");
    }
}
