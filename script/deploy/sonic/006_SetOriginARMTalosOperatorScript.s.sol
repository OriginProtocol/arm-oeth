// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// Contracts
import {Sonic} from "contracts/utils/Addresses.sol";
import {OwnableOperable} from "contracts/OwnableOperable.sol";

// Deployment
import {AbstractDeployScript} from "script/deploy/helpers/AbstractDeployScript.s.sol";

/// @notice Migrates the operator of OriginARM on Sonic from the old relayer EOA
/// to the new Talos KMS signer. OriginARM on Sonic is owned by the Sonic Timelock
/// (not the 5/8 admin), so setOperator (onlyOwner on OwnableOperable) must go
/// through the timelock. The real migration is a Sonic Timelock schedule/execute
/// driven by the Sonic 5/8 admin, performed manually as a separate step:
/// arm-oeth has no auto-JSON generation for the Sonic timelock, and
/// origin-dollar's 030_migrate_sonic_operators_to_talos covers only the
/// OSonicVault + SonicStakingStrategy timelock actions, NOT this OriginARM
/// setOperator. This script only implements _fork() to validate the operator
/// change against a Sonic fork by pranking the owner (the Sonic Timelock).
contract $006_SetOriginARMTalosOperatorScript is AbstractDeployScript("006_SetOriginARMTalosOperatorScript") {
    // ────────────────────────────────────────────────────────────────────────────────────────
    // MANUAL SONIC TIMELOCK MIGRATION — reference calldata
    // Generated with `cast`; the operation id is verified against the live Sonic Timelock.
    //
    // OriginARM.setOperator() is onlyOwner, and OriginARM's owner is the Sonic Timelock
    // (0x31a91336414d3B955E494E7d485a6B06b55FC8fB, an OpenZeppelin TimelockController).
    // So the change is a two-step, time-locked operation driven by the Sonic 5/8 admin Safe
    // (0xAdDEA7933Db7d83855786EB43a238111C69B00b6), which holds both PROPOSER and EXECUTOR roles:
    //     1) Safe -> Timelock.schedule(...)   queues the op and starts the 48h timer
    //     2) wait getMinDelay() = 172800s (48h)
    //     3) Safe -> Timelock.execute(...)    runs the op; the Timelock then calls setOperator
    // Send BOTH transactions TO the Timelock 0x31a91336414d3B955E494E7d485a6B06b55FC8fB, value 0.
    //
    // HOW THE CALLDATA IS STRUCTURED
    // Solidity ABI-encoding = 4-byte selector, then a 32-byte "head" word per top-level argument,
    // then a "tail" holding the contents of any dynamic (`bytes`) argument. A `bytes` argument does
    // not sit inline in the head; its head word is an OFFSET (measured from the first byte after the
    // selector) pointing into the tail, where the layout is [32-byte length][content padded up to a
    // 32-byte boundary]. address/uint256/bytes32 are static and sit inline in the head, left-padded.
    //
    // ── Inner call the Timelock performs (this is the `data`/`payload` bytes carried below) ──
    //   target   = OriginARM 0x2F872623d1E1Af5835b08b0E49aAd2d81d649D30
    //   function = setOperator(address)                      selector 0xb3ab15fb
    //   arg      = Sonic.TALOS_RELAYER 0x739212d5bAfE6AAC8Be49a60B7d003bD41DBf38b
    //   data (36 bytes) = 0xb3ab15fb000000000000000000000000739212d5bafe6aac8be49a60b7d003bd41dbf38b
    //                      └ selector (4) ┘└──────── address, left-padded to 32 bytes ────────┘
    //
    // ── Operation id = keccak256(abi.encode(target, value, data, predecessor, salt)) ──
    //   0xdafe6d5b3c6dee208b6146e82e0e73acfab9e6a4c60f00f95ea9ef4b4ff6fcc5
    //   (emitted in CallScheduled; pass it to cancel() / isOperationReady() / isOperationDone())
    //
    // ════════════ STEP 1 — Timelock.schedule(address,uint256,bytes,bytes32,bytes32,uint256) ════════════
    // selector 0x01d5062a. The head has 6 words, so the `data` offset is 6*32 = 0xc0.
    //   0x01d5062a
    //   0000000000000000000000002f872623d1e1af5835b08b0e49aad2d81d649d30  target       = OriginARM
    //   0000000000000000000000000000000000000000000000000000000000000000  value        = 0
    //   00000000000000000000000000000000000000000000000000000000000000c0  offset->data = 0xc0 (192)
    //   0000000000000000000000000000000000000000000000000000000000000000  predecessor  = 0x0 (no dependency)
    //   0000000000000000000000000000000000000000000000000000000000000000  salt         = 0x0
    //   000000000000000000000000000000000000000000000000000000000002a300  delay        = 0x2a300 (172800)
    //   0000000000000000000000000000000000000000000000000000000000000024  data.length  = 0x24 (36 bytes)
    //   b3ab15fb000000000000000000000000739212d5bafe6aac8be49a60b7d003bd41dbf38b          data (36 bytes)
    //   00000000000000000000000000000000000000000000000000000000          right-pad to a 32-byte boundary
    //
    // STEP 1 one-line calldata:
    // 0x01d5062a0000000000000000000000002f872623d1e1af5835b08b0e49aad2d81d649d30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a3000000000000000000000000000000000000000000000000000000000000000024b3ab15fb000000000000000000000000739212d5bafe6aac8be49a60b7d003bd41dbf38b00000000000000000000000000000000000000000000000000000000
    //
    // ════════════ STEP 2 — Timelock.execute(address,uint256,bytes,bytes32,bytes32) ════════════
    // selector 0x134008d3. Callable only after the 48h delay. predecessor + salt MUST match STEP 1,
    // otherwise the recomputed operation id won't be the one that was scheduled. Here the head has 5
    // words, so the `payload` offset is 5*32 = 0xa0 (the only structural difference from schedule).
    //   0x134008d3
    //   0000000000000000000000002f872623d1e1af5835b08b0e49aad2d81d649d30  target          = OriginARM
    //   0000000000000000000000000000000000000000000000000000000000000000  value           = 0
    //   00000000000000000000000000000000000000000000000000000000000000a0  offset->payload = 0xa0 (160)
    //   0000000000000000000000000000000000000000000000000000000000000000  predecessor     = 0x0
    //   0000000000000000000000000000000000000000000000000000000000000000  salt            = 0x0
    //   0000000000000000000000000000000000000000000000000000000000000024  payload.length  = 0x24 (36 bytes)
    //   b3ab15fb000000000000000000000000739212d5bafe6aac8be49a60b7d003bd41dbf38b          payload (36 bytes)
    //   00000000000000000000000000000000000000000000000000000000          right-pad to a 32-byte boundary
    //
    // STEP 2 one-line calldata:
    // 0x134008d30000000000000000000000002f872623d1e1af5835b08b0e49aad2d81d649d30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024b3ab15fb000000000000000000000000739212d5bafe6aac8be49a60b7d003bd41dbf38b00000000000000000000000000000000000000000000000000000000
    //
    // predecessor = 0x0 means the op depends on nothing. salt = 0x0 is fine for a one-off; if an
    // identical op (same target/value/data/predecessor/salt) is already queued, schedule() reverts
    // with "TimelockController: operation already scheduled" — bump salt to any unique bytes32 and
    // recompute BOTH calls (and the operation id) with the same salt. delay must be >= getMinDelay();
    // 172800 is exactly the current minimum.
    // ────────────────────────────────────────────────────────────────────────────────────────
    function _fork() internal override {
        OwnableOperable arm = OwnableOperable(resolver.resolve("ORIGIN_ARM"));

        if (arm.operator() != Sonic.TALOS_RELAYER) {
            vm.startPrank(arm.owner());
            arm.setOperator(Sonic.TALOS_RELAYER);
            vm.stopPrank();
        }
    }
}
