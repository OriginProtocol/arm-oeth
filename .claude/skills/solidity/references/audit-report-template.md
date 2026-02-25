# Audit Report Template

Template for the final report produced by the audit-lead agent.
Fill each section based on the audit findings. Delete sections that
don't apply (e.g., if no Critical findings, omit the Critical section
header entirely — don't leave an empty section).

---

## Report Structure

```markdown
# Security Audit Report: [System Name]

**Audit Date**: [Date]
**Auditor**: Claude Code — Solidity Security Skill
**Scope**: [Brief scope description]
**Commit Hash**: [If available from git]
**Overall Risk**: Critical / High / Medium / Low

---

## Executive Summary

[2-3 paragraphs maximum. Write for a CTO or protocol lead who has
10 minutes. Cover:]
- What was audited (system name, what it does, how many contracts)
- Key findings summary (X Critical, Y High, Z Medium, W Low)
- Overall assessment (safe to deploy? needs fixes first? fundamental
  design issues?)
- Top 1-2 most important actions to take

[Do NOT pad this section. If the system is well-built, say so. If it
has critical issues, lead with them.]

## Scope

### Contracts in Scope

| Contract | File | LOC | Type | Risk Tier |
|----------|------|-----|------|-----------|
| ... | ... | ... | Core / Supporting / Utility | High / Medium / Low |

**Total LOC in scope**: [N]

### Out of Scope

[Explicitly list what was NOT reviewed: test files, deployment scripts,
off-chain components, specific contracts excluded]

### Methodology

1. **Scope Discovery** — Identified all contracts, mapped inheritance
   and dependencies
2. **Per-Contract Review** — Structured 8-step security review of each
   contract (security checklist, asset flow tracing, state mutation
   analysis)
3. **Vulnerability Pattern Scanning** — Matched against known exploit
   database (N incidents consulted)
4. **Cross-Contract Analysis** — Analyzed trust boundaries, composability
   risks, and value flow across contract boundaries
5. **Severity Assessment** — Rated findings with full system context

## System Architecture

### Contract Dependency Graph

[ASCII or Markdown diagram showing inheritance and call relationships.
Show which contracts call which, who inherits from whom, and where
external protocols are integrated.]

### Trust Model

| Actor | Trust Level | Capabilities |
|-------|------------|--------------|
| ... | Untrusted / Semi-trusted / Trusted | ... |

### Value Flow

[Describe how value enters and exits the system, which contracts it
passes through. Trace: user deposit → ... → user withdrawal.]

## Findings Summary

| Severity | Count |
|----------|-------|
| Critical | X |
| High | Y |
| Medium | Z |
| Low | W |
| Informational | V |
| Gas | G |
| **Total** | **N** |

## Findings

### Critical

#### [C-01] Title
- **Contracts**: `ContractA.sol`, `ContractB.sol`
- **Location**: `ContractA.sol:L42-L48`, `ContractB.sol:L100`
- **Category**: [Reentrancy / Access Control / Logic / Oracle / etc.]
- **Checklist IDs**: [F6, X3] (if applicable from security-checklist.md)

**Description**
[Clear explanation of the vulnerability — what it is, not just what's
wrong with the code]

**Impact**
[Who is affected, what they lose, under what conditions, estimated
maximum loss]

**Proof of Concept**
[Step-by-step attack scenario. For cross-contract issues, show the
full call chain across contracts:]
1. Attacker calls ContractA.deposit() with X tokens
2. Attacker calls ContractB.manipulate() to change state
3. Attacker calls ContractA.withdraw() and receives X + Y tokens
4. Net profit: Y tokens stolen from other depositors

**Cross-Contract Context**
[If this finding involves multiple contracts, explain the cross-contract
interaction that makes it possible. Why can't a single-contract review
find this?]

**Recommendation**
[Specific code changes to fix. Show before/after if helpful.]

---

### High

#### [H-01] Title
[Same format as Critical. Proof of Concept required.]

### Medium

#### [M-01] Title
[Same format. Proof of Concept optional but encouraged.]

### Low

#### [L-01] Title
[Simplified format — Description, Impact, Recommendation. No PoC needed.]

### Informational

#### [I-01] Title
[Code quality, best practice, or architectural observation. Brief.]

### Gas Optimizations

#### [G-01] Title
- **Location**: `file.sol:L55`
- **Description**: ...
- **Estimated savings**: ~X gas per call
- **Recommendation**: ...

## Systemic Observations

[Patterns observed across the codebase that aren't individual findings
but are worth noting.]

### Strengths
- [Consistent pattern done well across the system]
- [Good architectural decision worth preserving]

### Concerns
- [Systemic pattern that could become problematic at scale]
- [Architectural limitation to be aware of]
- [Testing gaps identified]

## Recommendations

### Immediate (Before Deployment)
1. [Fix for Critical/High findings — reference finding IDs]
2. ...

### Short-Term (Before TVL Growth)
1. [Fix for Medium findings]
2. ...

### Long-Term (Ongoing)
1. [Monitoring, additional tests, process improvements]
2. ...

## Appendix

### A: Checklist Coverage

| Category | Contracts Checked | Notable Findings |
|----------|------------------|-----------------|
| Variables & Storage (V1-V10) | All | ... |
| Functions & Access Control (F1-F19) | All | ... |
| External Calls (X1-X8) | All | ... |
| DeFi Patterns (D1-D11) | [Relevant contracts] | ... |
| ... | ... | ... |

### B: Files Reviewed

[Complete list of all files read during the audit, with line counts]
```

## Formatting Rules

- Finding IDs use the format: `[SEVERITY-##]` (e.g., C-01, H-02, M-03)
- Always include contract name AND line numbers in Location
- For cross-contract findings, list ALL affected contracts and include the Cross-Contract Context section
- Proof of Concept is **required** for Critical and High findings
- Estimated gas savings **required** for Gas findings
- Do NOT include findings you're less than 50% confident about — mention them in Systemic Observations as "areas warranting further investigation" instead
- Do NOT leave empty severity sections — omit the header entirely if no findings at that level
- Keep the Executive Summary under 300 words — it should be scannable
