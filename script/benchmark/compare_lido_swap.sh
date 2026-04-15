#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE_UPGRADE_COMMIT="${PRE_UPGRADE_COMMIT:-9c297fb}"
PRE_WORKTREE="${PRE_WORKTREE:-/tmp/arm-oeth-pre-lido-bench}"
CURRENT_ONLY="${CURRENT_ONLY:-0}"

IN_TOKEN="${IN_TOKEN:-steth}"
OUT_TOKEN="${OUT_TOKEN:-weth}"
BENCHMARK_LABEL="${BENCHMARK_LABEL:-$(tr '[:lower:]' '[:upper:]' <<< "${IN_TOKEN:0:1}")${IN_TOKEN:1}_To_$(tr '[:lower:]' '[:upper:]' <<< "${OUT_TOKEN:0:1}")${OUT_TOKEN:1}}"
BENCHMARK_SUFFIX="${BENCHMARK_SUFFIX:-${IN_TOKEN}_to_${OUT_TOKEN}}"

CURRENT_BENCHMARK_PATH="${CURRENT_BENCHMARK_PATH:-test/fork/LidoARM/__CodexIsolatedSwapBenchmark_${BENCHMARK_SUFFIX}.t.sol}"
PRE_BENCHMARK_PATH="${PRE_BENCHMARK_PATH:-test/fork/LidoFixedPriceMultiLpARM/__CodexIsolatedSwapBenchmark_${BENCHMARK_SUFFIX}.t.sol}"
BENCHMARK_TEST_NAME="${BENCHMARK_TEST_NAME:-test_Benchmark_SwapExactTokensForTokens_${BENCHMARK_LABEL}_Isolated}"

if [[ -f "$ROOT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
fi

RPC_URL="${MAINNET_URL:-${PROVIDER_URL:-}}"
if [[ -z "$RPC_URL" ]]; then
    echo "error: MAINNET_URL or PROVIDER_URL must be set" >&2
    exit 1
fi

ensure_pre_worktree() {
    if [[ ! -d "$PRE_WORKTREE/.git" && ! -f "$PRE_WORKTREE/.git" ]]; then
        git -C "$ROOT_DIR" worktree add "$PRE_WORKTREE" "$PRE_UPGRADE_COMMIT" >/dev/null
    fi

    if [[ ! -e "$PRE_WORKTREE/dependencies" ]]; then
        ln -s "$ROOT_DIR/dependencies" "$PRE_WORKTREE/dependencies"
    fi
}

write_isolated_benchmark_test() {
    local output_path="$1"
    local in_token="$2"
    local out_token="$3"
    local benchmark_test_name="$4"

    cat > "$output_path" <<EOF
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Fork_Shared_Test_} from "test/fork/shared/Shared.sol";

contract Fork_Concrete_LidoARM_IsolatedSwapBenchmark_Test is Fork_Shared_Test_ {
    uint256 private constant INITIAL_BALANCE = 1_000 ether;

    function setUp() public override {
        super.setUp();

        deal(address(weth), address(this), INITIAL_BALANCE);
        deal(address(steth), address(this), INITIAL_BALANCE);
        deal(address(wsteth), address(this), INITIAL_BALANCE);

        deal(address(weth), address(lidoARM), INITIAL_BALANCE);
        deal(address(steth), address(lidoARM), INITIAL_BALANCE);
        deal(address(wsteth), address(lidoARM), INITIAL_BALANCE);

        lidoARM.collectFees();
    }

    function ${benchmark_test_name}() public {
        vm.pauseGasMetering();
        ${in_token}.approve(address(lidoARM), type(uint256).max);
        uint256 amountIn = 1 ether;
        vm.resumeGasMetering();

        lidoARM.swapExactTokensForTokens(${in_token}, ${out_token}, amountIn, 0, address(this));

        vm.pauseGasMetering();
    }
}
EOF
}

run_test_and_extract_gas() {
    local workdir="$1"
    local test_path="$2"
    local test_name="$3"
    local rpc_env_name="$4"
    local output
    local gas
    local status

    set +e
    output="$(
        cd "$workdir"
        env "$rpc_env_name=$RPC_URL" forge test \
            --match-path "$test_path" \
            --match-test "$test_name" \
            2>&1
    )"
    status=$?
    set -e

    if [[ "${VERBOSE:-0}" == "1" ]]; then
        printf '%s\n' "$output" >&2
    fi

    if [[ $status -ne 0 ]]; then
        printf '%s\n' "$output" >&2
        echo "error: forge test failed for $test_name" >&2
        exit $status
    fi

    gas="$(printf '%s\n' "$output" | sed -n 's/.*(gas: \([0-9][0-9]*\)).*/\1/p' | tail -n 1)"
    if [[ -z "$gas" ]]; then
        printf '%s\n' "$output" >&2
        echo "error: failed to extract gas from forge output for $test_name" >&2
        exit 1
    fi

    printf '%s' "$gas"
}

if [[ "$CURRENT_ONLY" != "1" ]]; then
    ensure_pre_worktree
fi

cleanup() {
    rm -f "$ROOT_DIR/$CURRENT_BENCHMARK_PATH" "$PRE_WORKTREE/$PRE_BENCHMARK_PATH"
}
trap cleanup EXIT

write_isolated_benchmark_test "$ROOT_DIR/$CURRENT_BENCHMARK_PATH" "$IN_TOKEN" "$OUT_TOKEN" "$BENCHMARK_TEST_NAME"
if [[ "$CURRENT_ONLY" != "1" ]]; then
    write_isolated_benchmark_test "$PRE_WORKTREE/$PRE_BENCHMARK_PATH" "$IN_TOKEN" "$OUT_TOKEN" "$BENCHMARK_TEST_NAME"
fi

echo "Running current benchmark..." >&2
current_gas="$(
    run_test_and_extract_gas "$ROOT_DIR" "$CURRENT_BENCHMARK_PATH" "$BENCHMARK_TEST_NAME" "MAINNET_URL"
)"

if [[ "$CURRENT_ONLY" == "1" ]]; then
    cat <<EOF
Lido swap benchmark
Mode: isolated swap call
Benchmark: $CURRENT_BENCHMARK_PATH::$BENCHMARK_TEST_NAME

Current: $current_gas gas
EOF
else
    echo "Running pre-upgrade benchmark..." >&2
    pre_gas="$(
        run_test_and_extract_gas "$PRE_WORKTREE" "$PRE_BENCHMARK_PATH" "$BENCHMARK_TEST_NAME" "PROVIDER_URL"
    )"

    delta_gas=$((current_gas - pre_gas))
    delta_pct="$(awk -v current="$current_gas" -v previous="$pre_gas" 'BEGIN { printf "%.2f", ((current - previous) / previous) * 100 }')"

    cat <<EOF
Lido swap benchmark
Mode: isolated swap call
Current benchmark: $CURRENT_BENCHMARK_PATH::$BENCHMARK_TEST_NAME
Pre-upgrade benchmark: $PRE_BENCHMARK_PATH::$BENCHMARK_TEST_NAME
Pre-upgrade commit: $PRE_UPGRADE_COMMIT

Before: $pre_gas gas
After:  $current_gas gas
Delta:  $delta_gas gas ($delta_pct%)
EOF
fi
