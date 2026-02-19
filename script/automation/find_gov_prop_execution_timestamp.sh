#!/bin/bash
# Find the execution timestamp for a governance proposal.
# Args: $1=proposalId, $2=rpc_url, $3=governor_address, $4=tsDeployment
# Returns: ABI-encoded uint256 timestamp (0 if not executed)
set -euo pipefail

PROPOSAL_ID=$1
RPC_URL=$2
GOVERNOR=$3
TS_DEPLOYMENT=$4

# ProposalExecuted(uint256 proposalId) - proposalId is NOT indexed, it's in the data field
# Topic0 = keccak256("ProposalExecuted(uint256)")
TOPIC0="0x712ae1383f79ac853f8d882153778e0260ef8f03b504e2866e0593e04d2b291f"

# Convert proposalId to padded 32-byte hex for data matching
# Note: can't use printf '%064x' because uint256 overflows bash integers
PADDED=$(cast abi-encode "f(uint256)" "$PROPOSAL_ID")

# Find the block at deployment time to scope the search
FROM_BLOCK=$(cast find-block "$TS_DEPLOYMENT" --rpc-url "$RPC_URL")

# Query ProposalExecuted events from deployment block onward
RESULT=$(cast logs \
  --address "$GOVERNOR" \
  "$TOPIC0" \
  --from-block "$FROM_BLOCK" \
  --rpc-url "$RPC_URL" \
  --json 2>/dev/null || echo "[]")

# Find matching log entry where data == padded proposalId
BLOCK=$(echo "$RESULT" | jq -r --arg data "$PADDED" '.[] | select(.data == $data) | .blockNumber' | head -1)

if [ -z "$BLOCK" ]; then
  # Not executed yet
  cast abi-encode "f(uint256)" "0"
  exit 0
fi

# Get block timestamp
TIMESTAMP=$(cast block "$BLOCK" --field timestamp --rpc-url "$RPC_URL")
cast abi-encode "f(uint256)" "$TIMESTAMP"
