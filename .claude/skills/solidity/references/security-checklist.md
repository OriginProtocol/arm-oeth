# Security Checklist

Structured security checklist for Solidity smart contract review. Based on [Solcurity](https://github.com/transmissions11/solcurity) by transmissions11, restructured and expanded with DeFi-specific patterns, signature security, oracle checks, and flash loan resistance.

Use checklist IDs (e.g., V1, F6, D3) when referencing findings in review reports.

---

## Variables & Storage

- **V1** — Can it be `internal` instead of `public`? (unnecessary getters increase attack surface)
- **V2** — Can it be `constant`? (saves ~2100 gas per SLOAD)
- **V3** — Can it be `immutable`? (set once in constructor, cheaper than storage)
- **V4** — Is its visibility explicitly set? Don't rely on defaults (SWC-108)
- **V5** — Is the purpose documented with NatSpec?
- **V6** — Can it be packed with an adjacent storage variable? (same slot = cheaper)
- **V7** — Can it be packed in a struct with other variables?
- **V8** — Use full 256-bit types unless packing. Smaller types cost gas for masking
- **V9** — If public array, is a separate function provided to return the full array?
- **V10** — Prefer `internal` over `private` for flexibility in child contracts

## Structs

- **ST1** — Is a struct necessary? Can the data be packed raw?
- **ST2** — Are fields packed to minimize storage slots?
- **ST3** — Is the struct and all fields documented with NatSpec?

## Functions & Access Control

- **F1** — Can it be `external` instead of `public`? (saves gas for large calldata)
- **F2** — Should it be `internal`?
- **F3** — Should it be `payable`? (saves gas if caller always sends ETH)
- **F4** — Can it be combined with a similar function to reduce code surface?
- **F5** — Are ALL parameters validated, even for trusted callers?
- **F6** — Is checks-effects-interactions (CEI) pattern followed? (SWC-107)
- **F7** — Is there a front-running risk? (approve race condition, sandwich) (SWC-114)
- **F8** — Is insufficient gas griefing possible? (SWC-126)
- **F9** — Are correct modifiers applied? (`onlyOwner`, `nonReentrant`, etc.)
- **F10** — Are return values always assigned on all code paths?
- **F11** — Are precondition invariants documented and tested?
- **F12** — Are postcondition invariants documented and tested?
- **F13** — Is the function name clear and unambiguous about behavior?
- **F14** — If intentionally unsafe (gas optimization), is the name unwieldy to signal risk?
- **F15** — Are all arguments, return values, and side effects documented with NatSpec?
- **F16** — If operating on another user, is `msg.sender` verified as authorized?
- **F17** — If requires uninitialized state, is an explicit `initialized` flag checked? (not `owner == address(0)`)
- **F18** — Prefer `internal` over `private` for child contract flexibility
- **F19** — Use `virtual` where child contracts may legitimately override behavior

## Modifiers

- **M1** — No storage updates in modifiers (except reentrancy locks)
- **M2** — No external calls in modifiers
- **M3** — Modifier purpose documented with NatSpec

## Code Quality & Logic

- **C1** — Using 0.8+ checked math or SafeMath? (SWC-101)
- **C2** — Are storage slots read multiple times in a function? (cache in local variable)
- **C3** — Unbounded loops or arrays that could cause DoS? (SWC-128)
- **C4** — `block.timestamp` only for long intervals (minutes+, not seconds) (SWC-116)
- **C5** — Not using `block.number` for elapsed time (SWC-116)
- **C7** — Avoid `delegatecall`, especially to external contracts (SWC-112)
- **C8** — Not updating array length while iterating
- **C9** — Not using `blockhash()` for randomness (SWC-120)
- **C10** — Signatures protected against replay with nonce AND `block.chainid` (SWC-121)
- **C11** — All signatures use EIP-712 (SWC-117, SWC-122)
- **C12** — `abi.encodePacked()` not hashed with >2 dynamic types. Prefer `abi.encode()` (SWC-133)
- **C13** — Assembly doesn't use arbitrary data (SWC-127)
- **C14** — Don't assume specific ETH balance (SWC-132)
- **C15** — Gas griefing prevention (SWC-126)
- **C16** — Private data isn't private on-chain (SWC-136)
- **C17** — Memory struct/array updates don't modify storage
- **C18** — No shadowed state variables (SWC-119)
- **C19** — Function parameters not mutated
- **C20** — Computing on-the-fly vs. storing: which is cheaper?
- **C21** — State variables read from correct contract (master vs. clone)
- **C22** — Comparison operators correct (`>`, `<`, `>=`, `<=`)? Off-by-one?
- **C23** — Logical operators correct (`==`, `!=`, `&&`, `||`, `!`)? Off-by-one?
- **C24** — Multiply before divide (unless overflow risk)
- **C25** — Magic numbers replaced by named constants
- **C26** — Reverting fallback causing DoS? (SWC-113)
- **C27** — SafeERC20 or return value checks for token transfers
- **C28** — `msg.value` not used in a loop
- **C29** — `msg.value` not used with recursive delegatecalls (Multicall/Batchable)
- **C30** — Don't assume `msg.sender` is always a relevant user
- **C31** — Don't use `assert()` except for fuzzing/formal verification (SWC-110)
- **C32** — Don't use `tx.origin` for authorization (SWC-115)
- **C33** — Don't use `address.transfer()` or `.send()`. Use `.call{value:}("")` (SWC-134)
- **C34** — Check contract existence before low-level calls
- **C35** — Use named argument syntax for functions with many parameters
- **C36** — Don't use assembly for `create2` — use salted creation syntax
- **C37** — Don't use assembly for `chainid` or contract code/size/hash
- **C38** — Use `delete` keyword for zeroing variables
- **C39** — Comment the "why" generously
- **C40** — Comment the "what" for obscure/unconventional code
- **C41** — Comment explanations + example inputs/outputs for complex math
- **C42** — Comment gas savings estimates for optimizations
- **C43** — Comment why certain optimizations were intentionally avoided
- **C44** — `unchecked` blocks documented with overflow impossibility reasoning and gas estimate
- **C45** — Don't rely on operator precedence — use parentheses
- **C46** — No side effects in comparison/logical expressions
- **C47** — Precision loss documented and benefits correct actor
- **C48** — Reentrancy lock usage documented with `@dev` comment
- **C49** — Fuzzer inputs bounded with modulo for specific ranges
- **C50** — Ternary expressions for simple branching
- **C51** — When operating on two addresses, check if they could be the same

## External Calls

- **X1** — Is the external call actually needed?
- **X2** — Could an error cause DoS? (`balanceOf()` reverting) (SWC-113)
- **X3** — Would reentrancy into the current function be harmful?
- **X4** — Would reentrancy into a different function be harmful? (cross-function reentrancy)
- **X5** — Is the return value checked and errors handled? (SWC-104)
- **X6** — What if the call consumes all forwarded gas?
- **X7** — Could massive return data cause out-of-gas?
- **X8** — Don't assume `success` means the function exists (phantom functions)

## Static Calls

- **SC1** — Is the static call actually needed?
- **SC2** — Is the called function actually `view` in the interface?
- **SC3** — Could the call revert and cause DoS? (SWC-113)
- **SC4** — Could the call enter an infinite loop and cause DoS?

## Events

- **E1** — Should fields be indexed for filtering?
- **E2** — Is the action creator included as indexed field?
- **E3** — Dynamic types (strings, bytes) not indexed (logs hash, not value)
- **E4** — Event emission and fields documented with NatSpec
- **E5** — All operated-on users/IDs stored as indexed fields
- **E6** — No function calls or expression evaluation in event arguments

## Contract Level

- **T1** — SPDX license identifier present
- **T2** — Events emitted for every storage-mutating function
- **T3** — Correct, simple, linear inheritance (SWC-125)
- **T4** — `receive() external payable` if contract should accept ETH
- **T5** — Invariants about stored state written down and tested
- **T6** — Contract purpose and interactions documented with NatSpec
- **T7** — `abstract` if incomplete without inheritance
- **T8** — Constructor-set non-immutables emit events (matching mutation events)
- **T9** — Avoid over-inheritance — it masks complexity
- **T10** — Named import syntax (`import {X} from "..."`)
- **T11** — Imports grouped: external deps → mocks/tests → local. Separated by blank lines
- **T12** — Contract-level `@notice` summary and `@dev` integration docs

## DeFi Patterns

- **D1** — Assumptions about external contract behavior validated
- **D2** — Don't mix internal accounting with actual `balanceOf` (donation attacks)
- **D3** — Don't use AMM spot price as oracle
- **D4** — Don't trade on AMMs without off-chain price target or oracle
- **D5** — Sanity checks to prevent oracle/price manipulation
- **D6** — Rebasing token handling documented (supported or explicitly unsupported)
- **D7** — ERC-777 callback reentrancy considered
- **D8** — Fee-on-transfer tokens handled or documented as unsupported
- **D9** — Token decimal range documented (min/max supported)
- **D10** — Raw balance not used for share price / earnings calculation
- **D11** — If contract holds approvals, no arbitrary calls from user input

## Signature Security (Extended)

- **SIG1** — Signatures include `block.chainid` to prevent cross-chain replay
- **SIG2** — Signatures include a nonce to prevent same-chain replay
- **SIG3** — EIP-712 structured data used (not raw hash signing)
- **SIG4** — `ecrecover` result checked for `address(0)` (invalid signature)
- **SIG5** — Signature malleability prevented (use OpenZeppelin ECDSA or check `s` value)
- **SIG6** — Deadline/expiry included for time-limited signatures
- **SIG7** — Contract address included in domain separator (prevents cross-contract replay)

## Oracle Security (Extended)

- **O1** — Oracle price not readable and usable in the same transaction (flash loan defense)
- **O2** — TWAP used instead of spot price where possible
- **O3** — Oracle freshness checked (stale price detection)
- **O4** — Oracle failure handled gracefully (fallback price or pause)
- **O5** — Price bounds/circuit breakers to reject unreasonable values
- **O6** — Multiple oracle sources for critical price feeds
- **O7** — Oracle decimal normalization correct (different oracles return different scales)

## Flash Loan Resistance (Extended)

- **FL1** — State changes from deposit/withdrawal can't be exploited within same block
- **FL2** — Share price can't be manipulated by direct token transfer (donation attack)
- **FL3** — Governance voting power not based on current-block balance
- **FL4** — Liquidation thresholds not manipulable by same-block actions
- **FL5** — Price oracles resistant to same-block manipulation

## Frontrunning / MEV Protection (Extended)

- **MEV1** — Slippage protection on all swaps (minAmountOut parameter)
- **MEV2** — Deadline parameter on time-sensitive operations
- **MEV3** — Commit-reveal scheme for operations vulnerable to frontrunning
- **MEV4** — No profitable reordering attacks possible on queued operations
- **MEV5** — Initialization functions protected against frontrunning

## Emergency & Recovery (Extended)

- **EM1** — Emergency pause mechanism for critical functions
- **EM2** — Pause doesn't lock user funds permanently (withdrawal still possible)
- **EM3** — Recovery function for accidentally sent tokens (excluding protocol tokens)
- **EM4** — No single key can drain all funds (multisig or timelock)
- **EM5** — Upgrade mechanism has timelock for user exit window

## ETH Handling (Extended)

- **ETH1** — `receive()` / `fallback()` only on contracts that should accept ETH
- **ETH2** — ETH sent via `.call{value:}("")` not `.transfer()` or `.send()`
- **ETH3** — Contract doesn't assume it holds zero ETH (forced ETH via selfdestruct)
- **ETH4** — Payable functions handle msg.value correctly (no double-counting in loops)
- **ETH5** — WETH wrapping/unwrapping handles all edge cases (partial, zero, max)
