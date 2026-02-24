---
name: solidity
description: "Security-first Solidity review, writing, and vulnerability scanning. Activates on any .sol work — reviewing contracts, writing Solidity code, auditing for vulnerabilities, checking security patterns, writing tests, or answering Solidity questions. Triggers on: review, audit, check, write, create, implement, scan, or any task involving .sol files."
---

# Solidity Security & Code Quality

Three specialized agents for Solidity work: **reviewer** (security audit), **writer** (secure code generation), and **scanner** (vulnerability pattern matching). For small tasks — quick questions, single-line fixes, Solidity syntax — handle inline without spawning agents.

## Philosophy

1. **Security first** — every piece of Solidity code is a potential attack surface
2. **Progressive disclosure** — load only what's needed for the task at hand
3. **Zero false positives over completeness** — a noisy report erodes trust
4. **Structured output** — findings must be actionable, not vague warnings

## Agent Router

Determine which agent to spawn based on the user's intent:

### Review Mode
**Triggers**: "review", "audit", "check security", "look for vulnerabilities", PR touching `.sol` files, or "is this safe"

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
