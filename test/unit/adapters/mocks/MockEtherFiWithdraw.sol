// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Solmate
import {ERC20} from "@solmate/tokens/ERC20.sol";

/// @notice Test double for Ether.fi's withdrawal queue and withdrawal NFT, combined into one contract.
///         Implements the subset used by `EtherFiAssetAdapter` / `WeETHAssetAdapter`:
///         `requestWithdraw` (pulls eETH from the caller and opens a request) and
///         `batchClaimWithdraw` / `claimWithdraw` (sends ETH to the request recipient, i.e. the NFT
///         owner, as EtherFi does — the claim is permissionless but proceeds go to the owner). Requests are finalized
///         on creation; `mock_*` setters drive the adapter's un-finalized / claimed edge-case branches.
///         The mock must be pre-funded with ETH so claims can pay out.
contract MockEtherFiWithdraw {
    struct Request {
        address recipient;
        uint256 amount;
        bool finalized;
        bool claimed;
    }

    /// @notice eETH pulled from the adapter when a withdrawal is requested.
    ERC20 public immutable eeth;
    /// @notice Next request id to assign.
    uint256 public counter;
    mapping(uint256 requestId => Request) public requests;

    constructor(address _eeth) {
        eeth = ERC20(_eeth);
    }

    receive() external payable {}

    /// @dev Pulls `amount` eETH from the caller (the adapter) and records a finalized request.
    function requestWithdraw(address recipient, uint256 amount) external returns (uint256 requestId) {
        eeth.transferFrom(msg.sender, address(this), amount);
        requestId = counter++;
        requests[requestId] = Request({recipient: recipient, amount: amount, finalized: true, claimed: false});
    }

    /// @dev Claims finalized requests in batch, sending 1:1 ETH to each request's recipient (the NFT owner).
    function batchClaimWithdraw(uint256[] calldata requestIds) external {
        for (uint256 i = 0; i < requestIds.length; ++i) {
            _claim(requestIds[i]);
        }
    }

    function claimWithdraw(uint256 requestId) external {
        _claim(requestId);
    }

    function finalizeRequests(uint256 requestId) external {
        requests[requestId].finalized = true;
    }

    function mock_setFinalized(uint256 requestId, bool finalized) external {
        requests[requestId].finalized = finalized;
    }

    function mock_setClaimed(uint256 requestId, bool claimed) external {
        requests[requestId].claimed = claimed;
    }

    function _claim(uint256 requestId) internal {
        Request storage request = requests[requestId];
        require(request.finalized, "Mock EF: not finalized");
        require(!request.claimed, "Mock EF: already claimed");
        request.claimed = true;

        // EtherFi pays the NFT owner (the recorded recipient), not the caller, and reverts the whole
        // claim — including the NFT burn — if that transfer fails. Real EtherFi masks the failure as
        // `EthTransferFailed()`; the mock bubbles the recipient's revert reason instead so tests can
        // assert the adapter's gate (`UnauthorizedEtherFiClaim`) is what blocks an out-of-band claim.
        (bool ok, bytes memory ret) = request.recipient.call{value: request.amount}("");
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}
