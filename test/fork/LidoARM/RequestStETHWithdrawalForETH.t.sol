// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Test imports
import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

// Contracts
import {AbstractLidoAssetAdapter} from "contracts/adapters/AbstractLidoAssetAdapter.sol";
import {IERC20, IStETHWithdrawal} from "contracts/Interfaces.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LidoARM} from "contracts/LidoARM.sol";
import {Mainnet} from "contracts/utils/Addresses.sol";

contract Fork_Concrete_LidoARM_RequestLidoWithdrawals_Test_ is Fork_Shared_Test_ {
    using stdStorage for StdStorage;

    event WithdrawalNFTRescued(uint256 indexed requestId, address indexed to);

    //////////////////////////////////////////////////////
    /// --- SETUP
    //////////////////////////////////////////////////////
    function setUp() public override {
        super.setUp();

        deal(address(steth), address(lidoARM), 10_000 ether);
    }

    //////////////////////////////////////////////////////
    /// --- REVERTING TESTS
    //////////////////////////////////////////////////////
    function test_RevertWhen_RequestLidoWithdrawals_NotOperator() public asRandomAddress {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        vm.expectRevert(bytes4(keccak256("OnlyOperatorOrOwner()")));
        lidoARM.requestBaseAssetRedeem(address(steth), amounts[0]);
    }

    function test_RevertWhen_RequestLidoWithdrawals_Because_BalanceExceeded() public asOperator {
        // Remove all stETH from the contract
        deal(address(steth), address(lidoARM), 0);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;

        vm.expectRevert();
        lidoARM.requestBaseAssetRedeem(address(steth), amounts[0]);
    }

    function test_RevertWhen_RescueActiveWithdrawalNFT() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;
        uint256[] memory requestIds = _requestLidoWithdrawals(amounts);
        uint256 requestId = requestIds[0];

        vm.expectRevert(abi.encodeWithSelector(AbstractLidoAssetAdapter.ActiveWithdrawalNFT.selector, requestId));
        AbstractLidoAssetAdapter(payable(stethAdapter)).rescueWithdrawalNFT(requestId, alice);
    }

    function test_RevertWhen_RescueWithdrawalNFT_NotARMOwner() public {
        uint256 requestId = _requestAdapterLidoWithdrawal();
        _clearLidoAdapterRequest(requestId);

        vm.prank(alice);
        vm.expectRevert(AbstractLidoAssetAdapter.OnlyARMOwner.selector);
        AbstractLidoAssetAdapter(payable(stethAdapter)).rescueWithdrawalNFT(requestId, alice);
    }

    //////////////////////////////////////////////////////
    /// --- PASSING TESTS
    //////////////////////////////////////////////////////
    function test_RequestLidoWithdrawals_EmptyList() public asOperator {
        uint256[] memory emptyList = new uint256[](0);

        // Expected events

        uint256[] memory requestIds = _requestLidoWithdrawals(emptyList);

        assertEq(requestIds, emptyList);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1ether() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;
        uint256[] memory expectedLidoRequestIds = new uint256[](1);
        expectedLidoRequestIds[0] = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;

        // Main call
        uint256[] memory requestIds = _requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }

    function test_RequestLidoWithdrawals_SingleAmount_1000ethers() public asOperator {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 ether;
        uint256[] memory expectedLidoRequestIds = new uint256[](1);
        expectedLidoRequestIds[0] = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;

        // Main call
        uint256[] memory requestIds = _requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }

    function test_RequestLidoWithdrawals_MultipleAmount() public asOperator {
        uint256 length = _bound(vm.randomUint(), 2, 10);
        uint256[] memory amounts = new uint256[](length);
        uint256 startingLidoRequestId = IStETHWithdrawal(Mainnet.LIDO_WITHDRAWAL).getLastRequestId() + 1;
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = _bound(vm.randomUint(), 1, 1_000 ether);
            totalAmount += amounts[i];
        }
        uint256 expectedLength = (totalAmount + 1_000 ether - 1) / 1_000 ether;
        uint256[] memory expectedLidoRequestIds = new uint256[](expectedLength);
        for (uint256 i = 0; i < expectedLength; ++i) {
            expectedLidoRequestIds[i] = startingLidoRequestId + i;
        }

        // Main call
        uint256[] memory requestIds = _requestLidoWithdrawals(amounts);

        assertEq(requestIds, expectedLidoRequestIds);
    }

    function test_RescueAccidentalWithdrawalNFT() public {
        address recipient = address(0xBEEF);
        uint256 requestId = _requestAdapterLidoWithdrawal();
        _clearLidoAdapterRequest(requestId);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalNFTRescued(requestId, recipient);
        AbstractLidoAssetAdapter(payable(stethAdapter)).rescueWithdrawalNFT(requestId, recipient);

        assertEq(IERC721(address(Mainnet.LIDO_WITHDRAWAL)).ownerOf(requestId), recipient, "rescued NFT owner");
    }

    function _requestAdapterLidoWithdrawal() internal returns (uint256 requestId) {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = DEFAULT_AMOUNT;
        uint256[] memory requestIds = _requestLidoWithdrawals(amounts);
        requestId = requestIds[0];

        assertEq(IERC721(address(Mainnet.LIDO_WITHDRAWAL)).ownerOf(requestId), stethAdapter, "NFT owner");
    }

    function _clearLidoAdapterRequest(uint256 requestId) internal {
        AbstractLidoAssetAdapter adapter = AbstractLidoAssetAdapter(payable(stethAdapter));

        stdstore.target(address(adapter)).sig("requestShares(uint256)").with_key(requestId).checked_write(uint256(0));
        stdstore.target(address(adapter)).sig("requestAssets(uint256)").with_key(requestId).checked_write(uint256(0));
        assertEq(adapter.requestShares(requestId), 0, "request shares cleared");
        assertEq(adapter.requestAssets(requestId), 0, "request assets cleared");
    }
}
