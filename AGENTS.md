# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## Documentation Conventions

- When writing NatSpec for scaled or non-obvious numeric parameters, include concrete examples.
  For example: `10,000 = 100% fee`, `500 = 5% fee`, `1e18 = 100% buffer`, `0.1e18 = 10% buffer`.
- When adding custom errors under `src/contracts`, include the 4-byte selector in an inline comment next to
  the declaration, for example `error SomeError(); // 0x12345678`. Compute selectors from canonical ABI
  signatures, using the ABI type for enums (for example, `uint8`).
