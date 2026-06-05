# Implementation for #240

See issue #240 for details.

<html>
<body>
<!--StartFragment--><html><head></head><body><h1>Bug Report: Slashing Loss Amplification via Stale <code>lidoWithdrawalQueueAmount</code></h1>

Field | Value
-- | --
Program | Origin Protocol — Immunefi Bug Bounty
Contract | LidoARM.sol + AbstractARM.sol
Address | 0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6 (Ethereum Mainnet)
Severity | HIGH
Category | Inaccurate Accounting / Share Price Manipulation
Impact | Amplification of LP losses during Lido validator slashing event
Affected |