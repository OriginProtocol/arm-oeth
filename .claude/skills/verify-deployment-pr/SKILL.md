---
name: verify-deployment-pr
description: >-
  Verifies a POST-EXECUTION deployment PR for arm-oeth (Foundry framework):
  confirms every deployed contract is listed in the PR description, that the
  on-chain verified source matches the codebase via `make match`, that
  constructor args match the deploy script's `_execute()`, that any proxy
  initialize/interaction matches the script, and that the on-chain GOVERNANCE
  proposal (and/or multisig upgrade) matches the script's `_buildGovernanceProposal()`.
  Emits a full report plus a short, GitHub-pasteable MD summary file.
  Use when asked to review, verify, audit, or sign off on an executed
  deployment PR. Invoke explicitly with /verify-deployment-pr <PR#>.
argument-hint: <PR#>
allowed-tools: Bash, Read, Grep, Glob, Task
disable-model-invocation: false
---

# Verify Deployment PR (arm-oeth / Foundry)

READ-ONLY audit of an already-executed deployment PR. Never broadcast a transaction,
never edit files, never re-run the live deployment. All on-chain data comes from the
block explorer (via `cast source` / Etherscan) or a read-only RPC.

> This is the arm-oeth (Foundry) counterpart of origin-dollar's Hardhat skill. The
> 6-check structure is identical; the mechanics differ. See "Stack differences" at the
> bottom for the full mapping if a check behaves unexpectedly.

## Step 0 — Prerequisites (fail fast)

1. All commands run from the **repo root** (there is no `contracts/` subdir).
2. Require `.env` with `MAINNET_URL` and `ETHERSCAN_API_KEY`:
   `grep -oE '^(MAINNET_URL|ETHERSCAN_API_KEY)=.' .env`. Source it for shell use:
   `set -a; . ./.env; set +a` (so `cast source` / `cast call` can reach Etherscan + RPC).
   - Missing `ETHERSCAN_API_KEY` → checks 2/3 can't run → STOP and report the blocker.
   - Missing `MAINNET_URL` (or `SONIC_URL` for a Sonic PR) → checks 3/4/5 can't run.
3. Require `gh` authenticated (`gh auth status`). If absent, ask the user to paste the
   PR body + deployed-address list rather than failing.
4. Require Foundry on PATH (`command -v forge cast make`). No `sol2uml`/npm needed — code
   comparison uses the repo's own `make match` target (`forge flatten` vs `cast source`).
5. **Verify you are on the correct branch.** This is the most important prereq: every
   check diffs the on-chain deployment against the *local* code, so a wrong branch (or a
   dirty tree) silently produces meaningless results. Match the checkout to the PR head:
   - `gh pr view "$PR" --json headRefName,state,mergeCommit`
   - `git rev-parse --abbrev-ref HEAD` and `git status --porcelain`
   - Require the current branch to equal the PR's `headRefName`, OR — if the PR is already
     merged — that the checkout contains its merge commit
     (`git merge-base --is-ancestor <mergeCommit> HEAD`).
   - On mismatch or a dirty working tree → **STOP**. Tell the user to `gh pr checkout <PR>`
     and re-run. (Exception: if the only files that differ between your branch and the PR
     head are the contract sources *being verified* — confirm with
     `git diff --stat <prHead>...HEAD -- src/` — you may proceed, but say so explicitly.)

## Step 1 — Gather PR context

1. `PR=$1`. `gh pr view "$PR" --json title,body,files,baseRefName,headRefName,state,url`.
2. **Find the deploy script.** Unlike Hardhat repos, an arm-oeth deployment PR usually
   changes ONLY the deployment-history file `build/deployments-1.json` (mainnet) or
   `build/deployments-146.json` (Sonic) — the numbered `*.s.sol` script was typically
   merged in an earlier PR. So:
   - Read the **script path from the PR body** (the `## Deployment` section names it, e.g.
     `script/deploy/mainnet/028_UpgradeARMsPauseScript.s.sol`), AND
   - Diff the history file to see the new execution + addresses:
     `git diff origin/<base>...HEAD -- build/deployments-*.json`.
   - The folder `script/deploy/<network>/` gives the **network** (mainnet → chain 1,
     sonic → chain 146). Use it to pick the history file and the explorer (see check 2).
3. **Parse the deployed contracts** from the script's `_execute()`: every
   `_recordDeployment("<NAME>", address(...))` call. Resolve each `<NAME>` → address from
   the `contracts[]` array in `build/deployments-<chainId>.json` (`{name, implementation}`;
   note `implementation` holds the proxy address for proxy entries and the impl address for
   `*_IMPL` entries). Cross-check these against the addresses in the PR body table.
4. **Parse constructor args** from the same `_execute()`: the `new <Contract>(...)` argument
   list (e.g. `new LidoARM(Mainnet.STETH, Mainnet.WETH, Mainnet.LIDO_WITHDRAWAL, 10 minutes,
   1e7, 1e18)`). Resolve `Mainnet.*` / `Sonic.*` symbols via `src/contracts/utils/Addresses.sol`.
   These are the source of truth for check 3 (there is no per-contract `.args` JSON).
5. **Parse governance** from `_buildGovernanceProposal()`: each
   `govProposal.action(target, "sig", abi.encode(args))`. Also read `_fork()` — ARMs upgraded
   by **multisig directly** (e.g. EthenaARM, owned by `MULTISIG_2_OF_8`) are pranked there, NOT
   in the proposal; they are a manual/Safe follow-up, not part of the on-chain Governor proposal.
6. **Find the proposalId.** Prefer the one in the PR body (`Proposal Id:`); also read the
   `executions[]` entry for this script in `build/deployments-<chainId>.json` (`.proposalId`).
   If they DIFFER, flag it (the recorded id is computed from the script's description; a
   different on-chain id usually means the submitted description differed) and verify check 5
   against the PR-body id. `proposalId == 0` → governance pending; `== 1` → no governance needed.
7. Working set: `[{name, address, ctorArgs, network, chainId, deployScript, proposalId,
   govActions, multisigUpgrades}]`.

## Step 2 — Run the checks

Checks 2/3 are per-address and independent — fan them out with parallel `Task` sub-agents
(one per deployed contract) when there are several; otherwise run inline. Each check yields:
status (✅ pass / ⚠️ needs-human / ❌ fail), one-line evidence, a details block, and a
confidence (High/Med/Low). Absence of evidence is ⚠️/❌, never ✅.

**1 — All deployed contracts listed in the PR description**
- Compare the Step-1 deployed name+address set against the PR body table.
- ✅ every deployed contract (name and address) appears; ❌ a deployed contract is
  missing; ⚠️ names present but addresses missing/ambiguous.

**2 — Verified on-chain code matches the codebase (`make match`)**
- For each deployed address, from the repo root:
  `make match file=src/contracts/<Name>.sol addr=<address>`
  This flattens the local source (`forge flatten`) and diffs it against the explorer-verified
  flattened source (`cast source --flatten`). The PR body's "Contract diff" section usually
  lists the exact `make match` commands — run those.
- ✅ prints `✅ Success: ... matches deployment`; ❌ prints `❌ Failure: ... differs` — show the
  `diff` hunk. For a `*Proxy` address, match against `src/contracts/Proxy.sol`.
- **Caveat:** `make match` is a *textual* flatten-diff, so import-ordering/whitespace/pragma
  noise can cause a false ❌ that an AST diff would tolerate. On ❌, inspect the hunk before
  declaring a real mismatch; a one-line pragma/import reordering with identical logic is ⚠️,
  not ❌. As written `make match` targets **Etherscan only** — for a **Sonic** PR (chain 146)
  it must be pointed at the Sonic explorer (add `--chain sonic` / `ETHERSCAN_API_KEY` for
  Sonicscan, or diff manually); mark ⚠️ "tooling: Sonic explorer" if you can't.
- Confidence High when the diff is clean.

**3 — Constructor arguments are correct**
- Take the `new <Contract>(...)` args parsed in Step 1.4 and resolve every `Mainnet.*`/`Sonic.*`
  symbol via `src/contracts/utils/Addresses.sol`.
- Compare them, positionally, to the on-chain values. **Preferred:** read the contract's public
  immutable getters on the impl address and compare to the resolved constant —
  `cast call <impl> "<getter>()(address|uint256|int256)"` (with `ETH_RPC_URL` exported; see Notes).
  e.g. for LidoARM: `steth()`, `weth()`, `lidoWithdrawalQueue()`, `claimDelay()`,
  `minSharesToRedeem()`, `allocateThreshold()`; EtherFiARM adds `eeth()`, `etherfiWithdrawalQueue()`,
  `etherfiWithdrawalNFT()`; EthenaARM has `usde()`, `susde()`. Numeric literals compare directly
  (`10 minutes`→`600`, `1e7`→`10000000`, `1e18`, `100e18`). The immutables live in the impl bytecode,
  so read them on the **impl** address. (Fallback: the explorer's "Constructor Arguments" — but
  Etherscan's v1 `getsourcecode` API is deprecated and now returns an error string, so prefer getters.)
- ✅ all args match; ❌ any positional mismatch (show deploy-script value vs on-chain).
  Proxies have no constructor args — note `[]`.

**4 — The initialize / interaction tx matches the deploy script**
- Only applies when `_execute()` deploys a `Proxy` and then calls `initialize(...)` /
  `upgradeToAndCall(...)` (e.g. Sonic `001_DeployOriginARMProxy` + `002_…`). Locate the
  corresponding on-chain tx (explorer tx list for the proxy, or its deployment receipt) and
  confirm the arguments match the script.
- ✅ init args match; ⚠️ the script only deploys implementations / has no init call (nothing to
  check — this is the common case for upgrade PRs like #254); ❌ args differ (show the diff).

**5 — Governance proposal matches the deploy script**
- arm-oeth's Governor is `Mainnet.GOVERNANCE = 0x1D3Fbd4d129Ddd2372EA85c5Fa00b2682081c9EC`
  (the same OZ Governor origin-dollar uses). Read it directly with `cast` — the 78-digit
  proposalId works natively as a decimal, no ethers/hardhat needed:
  - `cast call $GOV "state(uint256)(uint8)" <id> --rpc-url $MAINNET_URL`
    (enum: 0 Pending · 1 Active · 2 Canceled · 3 Defeated · 4 Succeeded · 5 Queued · 6 Expired · 7 Executed)
  - `cast call $GOV "getActions(uint256)(address[],uint256[],string[],bytes[])" <id> --rpc-url $MAINNET_URL`
    (calldatas are selector-stripped; the signature is the separate `string[]`).
- Build the expected actions from `_buildGovernanceProposal()`: resolve each `action.contract`
  → target address, keep the `"sig"`, and the `data` is the `abi.encode(args)` already in the
  script. Compare element-by-element to the on-chain `(targets, sigs, calldatas)`.
- ✅ identical (same count, targets, signatures, calldatas); ❌ any divergence (show it).
  Report `state`: `Executed (7)` for a fully-executed deploy; `Pending/Active/Queued` is normal
  when reviewing before execution — flag it, not a failure.
- **Split governance (multisig-direct upgrades):** if `_fork()` upgrades some ARMs via a multisig
  directly (e.g. EthenaARM), those proxies are NOT in the Governor `getActions`. Verify each:
  1. **Find the controlling Safe — read the proxy's `owner()`, don't assume.**
     `cast call <proxy> "owner()(address)"`. (Observed: the EthenaARM proxy is owned by
     `MULTISIG_5_OF_8 0xbe2AB3d3…`, **not** `MULTISIG_2_OF_8` — always read it on-chain.)
  2. Read the proxy's current impl: `cast call <proxy> "implementation()(address)"` (or the EIP-1967
     slot). If it already equals the new impl → ✅ executed.
  3. If it doesn't, the upgrade is pending in the Safe — pull it from the Safe Transaction Service
     and verify the queued tx (this turns "human owes, can't check" into a real check):
     `curl -sS -L "https://safe-transaction-mainnet.safe.global/api/v1/safes/<safe>/multisig-transactions/?nonce=<n>"`
     — **`-L` is required** (the API 308-redirects; without it you get an empty body and a confusing
     JSON parse error). Confirm `to` = the proxy, `dataDecoded.method` = `upgradeTo` (selector
     `0x3659cfe6`, check with `cast sig "upgradeTo(address)"`), the `newImplementation` arg = the
     verified new impl, `value` 0, `operation` 0 (CALL, not delegatecall); report `isExecuted` and
     `confirmations`/`confirmationsRequired`.
  - ✅ if the live impl already matches the new impl; ⚠️ if the Safe tx is correctly formed but not
    yet executed (report signatures collected vs threshold, and list it under "Human still owes");
    ❌ if a queued Safe tx targets the wrong proxy/impl or uses a non-CALL operation.

**6 — Smoke tests after fork execution** — SKIPPED (per project decision). Mark N/A.
(arm-oeth smoke tests bootstrap DeployManager and run automatically in CI — `make test-smoke`.)

## Step 3 — Synthesize

Verdict = **VERIFIED** only if checks 2,3,5 are ✅ (check 1 may be ⚠️ if the sole gap is
documentation; check 4 may be ⚠️ if the script only deploys implementations). Any ❌ in 2–5, or
an unresolved ⚠️, → **BLOCKERS FOUND**. Emit the report:

```
# Deployment PR Verification — #<PR> (<title>)
Verified against: <branch>@<short-sha>
Deploy script: <path>   |   Network: <net> (chain <id>)   |   Proposal: <proposalId> (<state>)
Verdict: <VERIFIED | BLOCKERS FOUND>

- [<✅|⚠️|❌>] 1. All deployed contracts listed in PR description — <evidence> (conf)
- [<✅|⚠️|❌>] 2. Verified code matches codebase (make match) — <evidence> (conf)
- [<✅|⚠️|❌>] 3. Constructor args correct — <evidence> (conf)
- [<✅|⚠️|❌>] 4. Initialize/interaction tx matches deploy script — <evidence> (conf)
- [<✅|⚠️|❌>] 5. Governance proposal / multisig upgrade matches deploy script — <evidence> (conf)
- [⏭️] 6. Smoke tests — skipped (N/A)

## Details
### 2. make match   <per-address: address, ✅/❌, differing files>
### 3. Constructor args   <per-address: script args (resolved) vs on-chain>
### 4. Initialize tx   <tx hash, decoded args vs script — or "impl-only, N/A">
### 5. Proposal diff   <on-chain getActions vs script actions; + multisig-direct upgrades>

## Human still owes (manual)
- Multisig-direct upgrades from _fork() (e.g. EthenaARM via MULTISIG_2_OF_8) — confirm Safe execution.
- That the PR's stated intent matches the on-chain effect (judgment).
- Anything marked ⚠️ above (incl. proposalId PR-body vs deployments JSON mismatch, if any).
```

## Step 4 — Short GitHub-pasteable summary

Besides the full report above, **always also write a short, concise version to an MD file**
(`PR-<PR#>-deployment-verification.md` at the repo root) that can be pasted straight into the
GitHub PR as a deployment-confirmation comment. Aim for ~10 lines / ~10% of the full report:
verdict, the deployed implementations with per-contract status (live / pending), the governance
proposal id + state, and any pending multisig Safe tx. No per-check details, no shell commands,
no Details/Human-owes sections. Template:

```
# Deployment Verification — PR #<PR> (<one-line scope>)

Script `<NNN_Name>`, <network> — read-only audit (on-chain + `make match`), <date>.

✅ **Verified.** All <N> implementations match the codebase and deploy-script constructor args:
- <Contract> `<addr>` — <live | pending>
- ...

<Gov-upgraded ARMs> upgraded via executed Governor proposal `<id>`. <Multisig ARM> awaits Safe tx
**#<nonce>** (`upgradeTo` to the verified impl, <m>/<n> sigs, not yet executed).
```

Then tell the user the file path so they can paste it. If the verdict is BLOCKERS FOUND, lead with
`❌` and one line naming the blocker; if everything is live with nothing pending, drop the trailing
Safe-tx sentence.

## Notes / common false positives

- Run everything from the repo root and `set -a; . ./.env; set +a` first so `$ETHERSCAN_API_KEY`
  and `$MAINNET_URL` reach `cast`/`make`. For `cast` calls, `export ETH_RPC_URL="$MAINNET_URL"` and
  drop the `--rpc-url` flag — passing the flag through a shell variable (`R="--rpc-url $URL"; cast … $R`)
  mis-splits the argument and fails with `error: unexpected argument '--rpc-url …'`.
- A **proxy address will not match an implementation's source** — `make match` a `*Proxy`
  address against `src/contracts/Proxy.sol`, not the impl.
- `make match` clean output (`✅ Success`) is the pass signal for check 2; treat a `❌ Failure`
  as needs-human (inspect the flatten-diff hunk) rather than an automatic blocker — see the
  textual-diff caveat above.
- The **proposalId in the PR body can differ from the one recorded in `build/deployments-*.json`**
  — they're computed from the proposal description, so a wording change yields a different id.
  Don't fabricate; verify check 5 against the PR-body id and note the discrepancy. A matching id is
  itself a strong cross-check: it's `keccak256(targets, values, calldatas, descriptionHash)`, so
  script-id == on-chain-id == PR-body-id proves the actions *and* description all match.
- **Parse `build/deployments-*.json` with `python`/`jq`, not `grep`.** Records span multiple lines,
  so grepping for a script name can attribute an *adjacent* record's `proposalId` to it and surface
  a false "discrepancy". (Hit this live: `102890619…` looked like 028's id but belonged to 009.)
- `tsGovernance: 0` in a deployment record while the on-chain proposal is `Executed` is normal lag —
  the hourly `update-deployments` CI job back-fills the execution timestamp. Trust on-chain `state()`,
  not the recorded timestamp, when deciding whether governance executed.
- If a helper command errors/rate-limits, retry once, then mark that check ⚠️ "tool error" with
  the stderr tail and continue the others. Never silently pass.

## Stack differences (origin-dollar Hardhat → arm-oeth Foundry)

| Aspect | origin-dollar (Hardhat) | arm-oeth (Foundry) |
|---|---|---|
| Working dir | `cd contracts` | repo root |
| Env keys | `PROVIDER_URL`, `ETHERSCAN_API_KEY` | `MAINNET_URL` (+`SONIC_URL`), `ETHERSCAN_API_KEY` |
| Code-diff tool | `sol2uml diff <addr> .,node_modules` | `make match file=<path> addr=<addr>` (forge flatten vs cast source) |
| Deployed contracts | `deployWithConfirmation()` + `deployments/<net>/<Name>.json` | `_recordDeployment()` in `_execute()` + `build/deployments-<chainId>.json` |
| Constructor args | `<Name>.json` `.args` | `new X(...)` in `_execute()`, symbols from `Addresses.sol` (no args JSON) |
| Governance source | `deploymentWithGovernanceProposal({actions})` | `_buildGovernanceProposal()` (`govProposal.action(...)`) |
| Governance read | ethers + GovernorSix ABI (hardhat task overflows on big id) | plain `cast call GOVERNANCE "getActions/state"` (big id native) |
| Governor contract | GovernorSix | **same contract** — `GOVERNANCE 0x1D3Fbd4d…` |
| Split governance | (single proposal) | some ARMs via Governor, some via `MULTISIG_2_OF_8` direct (in `_fork()`) |
| What the PR changes | deploy script + per-contract JSON | usually only `build/deployments-<chainId>.json` |
| Per-network artifact | `deployments/<net>/` | `build/deployments-1.json` (mainnet) / `-146.json` (Sonic) |

## Do NOT

- Never send transactions, never re-run the deployment, never edit files. Explorer +
  read-only RPC only.
- Never declare VERIFIED while any of checks 2,3,5 is ❌ or an unresolved ⚠️.
