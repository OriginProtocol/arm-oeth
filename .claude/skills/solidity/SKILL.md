---
name: solidity
description: "Security-first Solidity review, writing, and vulnerability scanning. Activates on any .sol work — reviewing contracts, writing Solidity code, auditing for vulnerabilities, checking security patterns, writing tests, or answering Solidity questions. Triggers on: review, audit, check, write, create, implement, scan, or any task involving .sol files."
---

# Solidity Security & Code Quality

Four specialized agents for Solidity work: **audit-lead** (multi-contract system audit), **reviewer** (single-contract security review), **writer** (secure code generation), and **scanner** (vulnerability pattern matching). For small tasks — quick questions, single-line fixes, Solidity syntax — handle inline without spawning agents.

## Philosophy

1. **Security first** — every piece of Solidity code is a potential attack surface
2. **Progressive disclosure** — load only what's needed for the task at hand
3. **Zero false positives over completeness** — a noisy report erodes trust
4. **Structured output** — findings must be actionable, not vague warnings

## Agent Router

Determine which agent to spawn based on the user's intent:

### Audit Mode
**Triggers**: "full audit", "system audit", "audit the whole system", "audit all contracts", "multi-contract audit", audit of a directory or multiple files, or any request involving security review of 3+ contracts as a system

→ Spawn `agents/audit-lead.md`
- Audit-lead maps the system architecture first
- Dispatches reviewer agents per contract module
- Dispatches scanner for known vulnerability patterns
- Performs cross-contract analysis (trust boundaries, composability, value flow)
- Loads `references/audit-report-template.md` at report generation
- If working in the ARM repo, also loads `references/arm-project.md`
- Returns consolidated professional audit report

**Distinguishing from Review Mode**: Review Mode handles 1-2 contracts in focused scope. Audit Mode handles an entire system — it discovers scope, maps dependencies, and finds cross-contract vulnerabilities. If the user says "review ContractX.sol", use Review Mode. If the user says "audit the system" or "review all contracts in this directory", use Audit Mode.

### Review Mode
**Triggers**: "review", "audit" (single contract), "check security", "look for vulnerabilities", PR touching `.sol` files, or "is this safe"

→ Spawn `agents/reviewer.md`
- Reviewer loads `references/security-checklist.md`
- At step 7, reviewer may spawn `agents/scanner.md` for known vulnerability matching
- Returns structured findings report

### Write Mode
**Triggers**: "write", "create", "implement", "add a function", "write a test", or any request to generate Solidity code

→ Spawn `agents/writer.md`
- Writer loads `references/code-standards.md`
- If working in the ARM repo, also loads `references/arm-project.md`
- Returns code with NatSpec, conventions applied, security patterns embedded

### Scan Mode
**Triggers**: "scan for vulnerabilities", "check against known exploits", "does this have any known attack patterns"

→ Spawn `agents/scanner.md` directly
- Scanner loads `references/vulnerabilities/index.md` first
- Selectively loads relevant incident files based on code characteristics
- Returns pattern match results with confidence levels

### Inline Mode (No Agent)
**Triggers**: Quick Solidity questions, syntax help, single-line fixes, "what does X do", gas optimization tips

→ Handle directly in SKILL.md without spawning agents. Use the rules below.

## Audit Workflow (Summary)

The audit-lead follows a 10-step orchestration process (full detail in `agents/audit-lead.md`):

1. **Scope discovery** — read all contracts, build inventory table
2. **Dependency mapping** — inheritance tree, call graph, shared state map
3. **Risk-based prioritization** — classify contracts into high/medium/low risk tiers
4. **Dispatch per-contract reviews** — spawn reviewer agents per module (parallel if subagents available)
5. **Cross-contract analysis** — trust boundaries, inconsistent assumptions, composability risks, upgrade risks, value flow completeness
6. **Finding consolidation** — deduplicate across agents, correlate related findings
7. **Severity re-assessment** — re-rate with full system context (upgrades and downgrades)
8. **Systemic observations** — patterns, strengths, and concerns across the codebase
9. **Recommendations** — immediate, short-term, and long-term action items
10. **Report generation** — produce report using `references/audit-report-template.md`

> **Note**: The Audit Workflow is for multi-contract system audits. For single-contract reviews, see Review Mode below, which uses a focused 8-step process.

## Review Workflow (Summary)

The reviewer follows an 8-step structured process (full detail in `agents/reviewer.md`):

1. **Scope identification** — read contracts, map inheritance
2. **Architecture understanding** — contract role, integrations
3. **Trust boundary analysis** — who calls what, privilege paths
4. **Asset flow tracing** — every token/ETH entry/exit
5. **State mutation review** — preconditions, postconditions, events
6. **Security checklist scan** — walk through `security-checklist.md`
7. **Vulnerability scan** — delegate to scanner or handle inline
8. **Report generation** — findings by severity

## Write Workflow (Summary)

The writer follows a 5-step process (full detail in `agents/writer.md`):

1. **Understand requirements** — what does this code need to do?
2. **Load project conventions** — read `arm-project.md` if applicable
3. **Apply code standards** — NatSpec, naming, structure
4. **Write with security mindset** — CEI, validation, events
5. **Self-review** — mental security checklist before returning

## Critical Rules (Always Apply)

These rules are too important to defer to reference files. Apply them in every mode.

### Checks-Effects-Interactions (CEI)
Always order: require checks → state updates → external calls. No exceptions unless the code explicitly documents why and uses a reentrancy guard.

### SafeERC20
Use `SafeERC20` for all token operations, or check return values. Never assume `transfer()` returns true.

### Events
Emit events for every state-mutating function. Index addresses and IDs. Use past tense for completed actions.

### Input Validation
Validate all parameters at function entry — even for owner-only functions. Check zero addresses, zero amounts, array bounds, and deadline expiry.

### Access Control
Every external state-mutating function must have an access control modifier or explicit documentation of why it's permissionless.

### Attacker-Deployed Contracts (Interface Impersonation)
When a function accepts an address parameter, casts it to an interface, and calls it — the attacker controls the implementation. Never assume the called contract will behave like the "real" implementation. An attacker can deploy their own contract that:
- Has a matching function signature but is a **no-op** (does nothing)
- Returns success without performing the expected side effects (e.g., doesn't actually transfer tokens, doesn't consume external state)
- Selectively executes some logic but skips critical parts

This is especially dangerous when the calling function **reads state from contract A** (e.g., an external protocol) and **expects the called contract B** (the user-supplied address) **to consume/clear that state**. If B no-ops, the state in A persists unchanged, and the function can be called repeatedly — draining internal accounting variables to zero in a single transaction. Always verify: does the function's state modification depend on the external call actually doing what it's supposed to do? If the external call target is user-supplied, the answer must be "no" — the function must be safe regardless of what the called contract does.

### Rounding Direction
Round in favor of the protocol (against the user). Document rounding direction in comments when it matters.

## False Positive Avoidance

Do NOT flag these as issues:

- **Unchecked blocks on loop counters** — `unchecked { ++i }` in for loops is standard and safe
- **Missing zero-address checks on immutables** — constructor args set once; deployment handles this
- **`block.timestamp` for delays** — valid for claim delays, cooldowns, and timeouts (minutes to days)
- **Centralization risks on owner functions** — flag only if there's no timelock or multisig mentioned. Owner controls are by design in upgradeable protocols
- **Gas optimizations on cold paths** — don't suggest `unchecked` or `calldata` on admin/setup functions called once
- **Known token quirks** — stETH 2-wei rounding, rebasing behavior, fee-on-transfer tokens are documented project patterns, not bugs
- **ERC-4626 rounding** — share/asset conversions that round down for deposits and round up for withdrawals are correct
- **Storage gaps in abstract contracts** — `uint256[N] private __gap` is standard upgrade safety

## Severity Guidelines

| Severity | Definition |
|----------|-----------|
| **Critical** | Direct loss of funds, permanent DoS, or privilege escalation to drain contracts |
| **High** | Conditional loss of funds, griefing with material cost, broken core invariant |
| **Medium** | Unexpected behavior under edge conditions, value leak over time, broken non-core feature |
| **Low** | Best practice violation with theoretical (not practical) impact |
| **Info** | Code quality, readability, gas optimization suggestion |
| **Gas** | Specific gas savings with estimated savings amount |

## Reference Router

Load references on-demand based on task:

| Task | Load |
|------|------|
| Security review | `references/security-checklist.md` |
| Writing Solidity code | `references/code-standards.md` |
| Working in ARM repo | `references/arm-project.md` (in addition to above) |
| Vulnerability scanning | `references/vulnerabilities/index.md` → selective incident files |
| Multi-contract system audit | `references/audit-report-template.md` + all references used by reviewer/scanner |
| Quick question | Nothing extra — use inline knowledge |

Never load all references at once. Each agent loads only what it needs.

## Upgradeable Contract Rules

When reviewing or writing upgradeable contracts:

1. **Storage layout** — new variables append only, never reorder or insert
2. **Storage gaps** — abstract contracts must reserve `uint256[N] private __gap`
3. **Initializers** — use `initializer` modifier, never rely on constructor
4. **No `selfdestruct`** — implementation destruction kills all proxies
5. **No immutables that change** — immutables are set at deploy time, shared across upgrades only if the implementation is redeployed
6. **`delegatecall` context** — `msg.sender` and `msg.value` are the proxy caller's, `address(this)` is the proxy's address
7. **EIP-1967 slots** — admin and implementation addresses stored in standardized slots

## Small Task Handling

For tasks that don't warrant a full agent:

- **"What does X do?"** — Read the contract, explain the function/pattern
- **"Is this syntax correct?"** — Answer directly
- **"How do I do X in Solidity?"** — Provide code snippet with brief security note
- **"Optimize this for gas"** — Suggest specific changes with estimated savings
- **"Fix this compiler error"** — Read the error, fix the code

Only spawn an agent when there's a meaningful multi-step workflow to execute.
