# Benchmarks

## Lido swap comparison

Run the like-for-like pre-upgrade vs post-upgrade stETH swap benchmark with:

```bash
./script/benchmark/compare_lido_swap.sh
```

Defaults:
- mode:
  isolated swap call only
- current benchmark:
  `test/fork/LidoARM/__CodexIsolatedSwapBenchmark.t.sol::test_Benchmark_SwapExactTokensForTokens_Steth_To_Weth_Isolated`
- pre-upgrade benchmark:
  `test/fork/LidoFixedPriceMultiLpARM/__CodexIsolatedSwapBenchmark.t.sol::test_Benchmark_SwapExactTokensForTokens_Steth_To_Weth_Isolated`
- pre-upgrade commit:
  `9c297fb`

Environment:
- uses `MAINNET_URL` if set
- otherwise falls back to `PROVIDER_URL`
- if neither is exported, it will source `.env`

Optional overrides:

```bash
PRE_UPGRADE_COMMIT=<commit> \
PRE_WORKTREE=/tmp/custom-pre-lido \
CURRENT_BENCHMARK_PATH=<path> \
PRE_BENCHMARK_PATH=<path> \
BENCHMARK_TEST_NAME=<name> \
IN_TOKEN=steth \
OUT_TOKEN=weth \
./script/benchmark/compare_lido_swap.sh
```

Current-only mode:

```bash
CURRENT_ONLY=1 IN_TOKEN=wsteth OUT_TOKEN=weth ./script/benchmark/compare_lido_swap.sh
```
