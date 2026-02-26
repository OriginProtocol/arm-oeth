---
name: solidity
description: "Multi-pass Solidity security review. Activates on: review, audit, check, scan, or any security analysis of .sol files. Does NOT activate on: writing code, creating contracts, implementing features, writing tests, fixing bugs, or answering Solidity questions — Claude handles those natively."
---

# Solidity Security Review

One agent. Three phases. A notes file as living memory. Iterate until exhausted.

## Philosophy

1. **Multi-pass over single-pass** — a human auditor re-reads code to deepen understanding. So do we. Each pass sees what the previous one missed.
2. **Notes are hypotheses, not truth** — every observation starts as a hypothesis. Later passes challenge and correct earlier ones.
3. **Zero false positives over completeness** — a noisy report erodes trust. Only report findings you can prove with code references.
4. **Targeted loading** — load the security checklist in Phase 2, vulnerability patterns in Phase 3. Never load everything upfront.
5. **Self-correction** — if a later pass disproves an earlier hypothesis, update the notes. The final report reflects only verified findings.

## Trigger Rules

**Activate this skill for**: review, audit, security check, vulnerability scan, "is this safe", "look for bugs", or any request to analyze .sol files for security issues.

**Do NOT activate for**: writing code, creating contracts, implementing features, adding functions, writing tests, fixing compiler errors, gas optimization, answering Solidity questions, or explaining code. Claude handles these natively without this skill.

## Scope Determination

Before starting, determine what to review:

1. **Explicit scope** — user names specific files or directories → use those
2. **System-level default** — user says "review" or "audit" without specifics → discover all contracts in scope (read directory, map inheritance, identify the system boundary)
3. **Ambiguous** — ask the user: "Which contracts should I review? I can review [list discovered contracts] or a subset."

Always map the full inheritance tree and identify external dependencies, even if only reviewing a subset.

## Phase 1 — Understand

**Goal**: Build a complete mental model of the system. No bug hunting yet.

Read every contract in scope. For each one, capture in the notes file:

### What to Capture

- **Purpose**: What does this contract do? One sentence.
- **Inheritance**: What does it inherit from? What overrides what?
- **State variables**: List all storage variables with types and visibility
- **Entry points**: All external/public functions — who can call them (access control)?
- **Asset flows**: How do tokens/ETH enter and leave? Trace every path.
- **Trust boundaries**: Which addresses are trusted (owner, operator)? What can they do?
- **External dependencies**: What external contracts does this call? What assumptions does it make about them?
- **Key invariants**: What must always be true? (e.g., "total shares == sum of all user shares", "withdrawal queue is FIFO")
- **Upgrade pattern**: Is it upgradeable? What are the storage layout implications?
- **Surprising observations**: Anything unexpected, unusual, or that deserves closer inspection

### Notes File

Create a file called `notes-review.md` in the working directory. Structure it as:

```markdown
# Security Review Notes

## System Overview
[One paragraph summary of the system architecture]

## Contract: [Name]
**Purpose**: ...
**Inherits**: ...
**State**: ...
**Entry points**: ...
**Asset flows**: ...
**Trust boundaries**: ...
**External deps**: ...
**Invariants**: ...

### Hypotheses
- HYPOTHESIS: [observation that needs verification]
- HYPOTHESIS: [another observation]
```

### Stopping Condition

Phase 1 is complete when you have a notes entry for every contract in scope and can explain the system's architecture without looking at the code.

## Phase 2 — Question

**Goal**: Challenge every hypothesis from Phase 1. Verify invariants. Find logical flaws.

### Setup

Load `references/security-checklist.md`. Re-read the code alongside your notes.

### What to Do

1. **Challenge hypotheses** — for each HYPOTHESIS in your notes, re-read the relevant code. Can you prove it? Disprove it? Update the status:
   - `VERIFIED: [hypothesis] — [evidence with file:line references]`
   - `DISPROVEN: [hypothesis] — [what's actually true, with evidence]`
   - `UNCERTAIN: [hypothesis] — [what you'd need to verify]`

2. **Walk the checklist** — go through `security-checklist.md` systematically against every contract. Use checklist IDs (V1, F6, D3, etc.) when noting findings. Not every item applies — skip what's irrelevant, but be deliberate about it.

3. **Verify invariants** — for each key invariant you identified, trace all code paths that could break it. Can a sequence of calls violate it? Can a revert mid-execution leave it broken?

4. **Trace trust boundaries** — for each privileged function, what's the worst an attacker could do if they gained that role? Is the damage bounded?

5. **Cross-contract analysis** — if multiple contracts interact, check:
   - Inconsistent assumptions between contracts
   - State that can be modified by one contract but read by another without synchronization
   - Composability risks (flash loans, callbacks, reentrancy across contracts)

### Notes Update

Add findings to the notes file as you go:

```markdown
### Findings (Phase 2)
- FINDING: [description] — Severity: [?] — [file:line]
- QUESTION: [something that needs deeper investigation in Phase 3]
```

### Stopping Condition

Phase 2 is complete when every hypothesis has been resolved (VERIFIED, DISPROVEN, or escalated to Phase 3) and the checklist has been walked for all contracts.

## Phase 3 — Attack

**Goal**: Think like an attacker. Exploit what you've learned. Prove or disprove every potential finding.

### Setup

Load `references/vulnerabilities/index.md`. Based on the code characteristics identified in Phase 1, load only the relevant vulnerability pattern files. Re-read the code with your verified notes.

### Attack Angles

For each contract, attempt these attack strategies:

1. **Value extraction** — can an attacker extract more value than they put in? Trace every path where assets leave the contract.
2. **State manipulation** — can an attacker put the contract into a state the developers didn't anticipate? Focus on edge cases: zero amounts, max values, empty arrays, self-referencing addresses.
3. **Ordering attacks** — can transaction ordering (frontrunning, sandwich, backrunning) be exploited? Check every swap, price-dependent operation, and time-sensitive function.
4. **Reentrancy** — for every external call, what happens if the callee re-enters? Check both same-function and cross-function reentrancy.
5. **Griefing** — can an attacker cause harm to others without profit? DoS, blocking withdrawals, inflating gas costs.
6. **Privilege escalation** — can a lower-privileged role perform higher-privileged actions through any code path?
7. **Oracle/price manipulation** — can any price or exchange rate be manipulated within a single transaction?
8. **Interface impersonation** — where user-supplied addresses are cast to interfaces, what happens if the implementation is a no-op or malicious?
9. **Adversarial state modeling** — for every permissionless entry point (deposit, swap, claim, liquidate), model what happens when the system is in an extreme but realistic state: insolvency (assets < obligations), zero liquidity, max utilization, post-slashing, post-depeg. The attacker does not need to create the extreme state — they wait for or observe a natural event, then exploit the state. Specifically for vaults: if `totalAssets()` has a floor, can an attacker deposit during insolvency to acquire cheap shares and dilute pending claims?

### Self-Correction Rule

For every potential finding, before adding it to the report:

1. **Write the attack scenario** — step by step, what does the attacker do?
2. **Trace the code** — follow the exact code path. Does it actually work?
3. **Check for guards** — is there a check, modifier, or invariant that prevents this?
4. **Verify the impact** — what's the actual damage? Quantify it if possible.
5. **If any step fails** — discard the finding. Add it to notes as `DISPROVEN` with the reason.

Only findings that survive all 5 steps make it to the report.

### Notes Update

```markdown
### Findings (Phase 3)
- VERIFIED FINDING: [description] — Severity: [level] — [file:line]
  Attack: [step-by-step scenario]
  Impact: [quantified if possible]
- DISPROVEN: [what you investigated] — [why it doesn't work]
```

### Stopping Condition

Phase 3 is complete when all attack angles have been exhausted for every contract and every finding has been either verified or disproven.

## Iteration

After Phase 3, review your notes. If a pass revealed new hypotheses or questions that weren't fully explored, run another pass through the relevant phase. Keep going until a pass produces nothing new.

## Output Format

After all phases are complete, produce the final report. Group findings by severity. Each finding must include:

```markdown
## Findings

### [Severity] — [Title]

**Location**: `file.sol:line`

**Description**: What's wrong and why it matters.

**Attack scenario**:
1. Attacker does X
2. This causes Y
3. Result: Z

**Recommendation**: How to fix it.
```

Severity order: Critical → High → Medium → Low → Info → Gas

If there are no findings at a given severity, omit that section. If there are no findings at all, say so explicitly — an empty report is better than a fabricated one.

After the findings, include a brief **System Observations** section noting:
- Strengths of the codebase (good patterns, solid invariants)
- Areas that deserve attention in future changes
- Any UNCERTAIN items from the notes that couldn't be fully resolved

## Critical Rules

These rules override everything above. Apply them always.

### Checks-Effects-Interactions (CEI)
Always verify: require checks → state updates → external calls. Flag any violation unless the code explicitly documents why and uses a reentrancy guard.

### SafeERC20
All token operations must use `SafeERC20` or check return values. Never assume `transfer()` returns true.

### Access Control
Every external state-mutating function must have an access control modifier or explicit documentation of why it's permissionless.

### Rounding Direction
Round in favor of the protocol (against the user). Flag any rounding that favors the user.

### Attacker-Deployed Contracts
When a function accepts an address parameter, casts it to an interface, and calls it — the attacker controls the implementation. Never assume the called contract behaves correctly. Verify: does the function's state modification depend on the external call actually doing what it's supposed to? If the target is user-supplied, the function must be safe regardless of what the called contract does.

## False Positive Avoidance

Do NOT flag these as issues:

- **Unchecked blocks on loop counters** — `unchecked { ++i }` in for loops is standard and safe
- **Missing zero-address checks on immutables** — constructor args set once; deployment handles this
- **`block.timestamp` for delays** — valid for claim delays, cooldowns, and timeouts (minutes to days)
- **Centralization risks on owner functions** — flag only if there's no timelock or multisig. Owner controls are by design in upgradeable protocols
- **Gas optimizations on cold paths** — don't suggest `unchecked` or `calldata` on admin functions called once
- **Known token quirks** — stETH 2-wei rounding, rebasing behavior, fee-on-transfer tokens are documented project patterns
- **ERC-4626 rounding** — share/asset conversions rounding down for deposits and up for withdrawals is correct
- **Storage gaps in abstract contracts** — `uint256[N] private __gap` is standard upgrade safety

## Severity Guidelines

| Severity | Definition |
|----------|-----------|
| **Critical** | Direct loss of funds, permanent DoS, or privilege escalation to drain contracts |
| **High** | Conditional loss of funds, griefing with material cost, broken core invariant |
| **Medium** | Unexpected behavior under edge conditions, value leak over time, broken non-core feature |
| **Low** | Best practice violation with theoretical (not practical) impact |
| **Info** | Code quality, readability, or documentation improvement |
| **Gas** | Specific gas savings with estimated savings amount |

## Upgradeable Contract Rules

When reviewing upgradeable contracts:

1. **Storage layout** — new variables append only, never reorder or insert
2. **Storage gaps** — abstract contracts must reserve `uint256[N] private __gap`
3. **Initializers** — use `initializer` modifier, never rely on constructor
4. **No `selfdestruct`** — implementation destruction kills all proxies
5. **No immutables that change** — immutables are set at deploy time, shared across upgrades only if reimplemented
6. **`delegatecall` context** — `msg.sender` and `msg.value` are the proxy caller's, `address(this)` is the proxy's address
7. **EIP-1967 slots** — admin and implementation addresses stored in standardized slots
