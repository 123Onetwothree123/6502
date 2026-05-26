# ReadyBASIC Micromodule Sync Ledger

ReadyBASIC mirrors a small amount of ReadyOS REU and memory-layout knowledge in
assembler. Keep this ledger synchronized whenever `readybasic.s`, the linker
config, ReadyOS REU allocation metadata, or the visual/docs pages change.

## ReadyOS Contract

| Contract | Current rule |
| --- | --- |
| App-owned RAM | `$1000-$C5FF`. ReadyOS save/restore targets this region. |
| Shared REU metadata | `$C600-$C7FF`; ReadyBASIC may mark bank ownership here but must not use it as scratch. |
| ReadyOS shim ABI | `$C800-$C9FF`; never treat as ReadyBASIC app memory. |
| Verification | Boot ReadyOS normally through `run.sh` / `run.ps1`, not a single-app direct load. |

## REU DMA Registers

ReadyBASIC's assembler REU helpers use the standard REU register block:

| Register | Meaning |
| ---: | --- |
| `$DF02-$DF03` | C64 address. |
| `$DF04-$DF05` | REU offset. |
| `$DF06` | REU bank. |
| `$DF07-$DF08` | Transfer length. |
| command `$90` | C64 to REU stash. |
| command `$91` | REU to C64 fetch. |

## Fixed ReadyBASIC REU Banks

The constants in `src/apps/readybasic/readybasic.s` are authoritative:

| Constant | Value |
| --- | ---: |
| `RB_REU_CORE_BANK` | `$44` |
| `RB_REU_CODE_BANK` | `$45` |
| `RB_REU_TYPE_CORE` | `14` |
| `RB_REU_TYPE_CODE` | `15` |
| `RB_REU_HEADER_OFF` | `$0000` |
| `RB_REU_CALL_OFF` | `$0400` |
| `RB_REU_RESULT_OFF` | `$0400` |
| `RB_REU_DEBUG_OFF` | `$0600` |
| `RB_REU_HANDLE_OFF` | `$0800` |
| `RB_REU_RUNTIME_ZP_OFF` | `$0A00` |
| `RB_REU_RUNTIME_STACK_OFF` | `$0B00` |
| `RB_REU_HEAP_OFF` | `$0C00` |
| `RB_REU_DESC_OFF` | `$1000` |
| `RB_REU_SLOT_STATE_OFF` | `$2000` |
| `RB_REU_DATA_OFF` | `$4000` |

`RB_REU_CALL_OFF` and `RB_REU_RESULT_OFF` intentionally point at the same
scratch offset. The call frame and result frame are mirrored at different
moments, so they are not simultaneous persistent structures.

## Current Linker Snapshot

Measured from `obj/readybasic.map` on the command-module branch:

| Segment | Runtime range | Size |
| --- | ---: | ---: |
| `ENTRY` | `$1000-$1102` | `$0103` / 259B |
| `RESIDENT` | `$1200-$2ABB` | `$18BC` / 6332B |
| `REGSEED` | `$5000-$600F` | `$1010` / 4112B load-only |
| `HIDDEN` | `$A000-$A364` | `$0365` / 869B |
| `LOWPACK` | `$A800-$AEC6` | `$06C7` / 1735B |
| `SLOTPACK1` | `$B000-$B140` | `$0141` / 321B |
| `SPANPACK` | `$B000-$B014` | `$0015` / 21B |
| `SLOTPACK2` | `$B800-$B814` | `$0015` / 21B |
| `OVL1PACK` | `$B815-$B829` | `$0015` / 21B |
| `OVL2PACK` | `$B82A-$B83E` | `$0015` / 21B |
| `BRIDGE` | `$C000-$C1F6` | `$01F7` / 503B |

`BASIC_START=$2AC1`, the sentinel is `$2AC0`, and the formula empty BASIC free
count is `30013`. The bridge must remain below `$C200`; shared frames occupy
`$C200-$C5FF`.

## Under-BASIC-ROM Windows

ReadyBASIC treats `$A000-$BFFF` as four 2KB windows under BASIC ROM:

| Window | Range | Current use |
| --- | ---: | --- |
| Common | `$A000-$A7FF` | Shared hidden/helper code. |
| Slot 0 | `$A800-$AFFF` | Default/system module, current `LOWPACK`. |
| Slot 1 | `$B000-$B7FF` | Built-in proof/loader module, disk span target. |
| Slot 2 | `$B800-$BFFF` | Built-in slot proof and overlay target. |

Slot masks in descriptors use bit 0 for slot 0, bit 1 for slot 1, and bit 2
for slot 2. A submodule can use one slot, two adjacent slots, or all three.

## Bank `$45` Payload Offsets

Cold init copies the built-in payload seed into REU bank `$45`. Disk module
loading extends the same bank at explicit offsets.

| Offset | Size | Runtime | Payload |
| ---: | ---: | ---: | --- |
| `$0000` | `$06C7` | `$A800` | Built-in module 1 slot 0. |
| `$06C7` | `$0141` | `$B000` | Built-in module 2 slot 1 and `ZMODLD`. |
| `$0808` | `$0015` | `$B800` | Built-in module 2 slot 2 proof. |
| `$081D` | `$0015` | `$B000` | Built-in module 2 span proof. |
| `$0832` | `$0015` | `$B815` | Built-in overlay 1 proof. |
| `$0847` | `$0015` | `$B82A` | Built-in overlay 2 proof. |
| `$3000` | module-file defined | slot 1 | Disk sample `RBM1` / `ZDM1`. |
| `$3200` | module-file defined | slots 1+2 | Disk sample `RBM2` / `ZDM2S`. |
| `$3300` | module-file defined | slot 2 | Disk sample overlay `ZDOV1`. |
| `$3400` | module-file defined | slot 2 | Disk sample overlay `ZDOV2`. |

## Descriptor ABI

Each descriptor remains exactly 32 bytes:

| Byte(s) | Meaning |
| ---: | --- |
| `0` | Command id. |
| `1` | Module id. |
| `2-3` | Payload REU offset in bank `$45`. |
| `4-5` | Payload size. |
| `6` | Submodule id. |
| `7` | Overlay id. |
| `8` | Slot mask. |
| `9` | Generation/check byte. |
| `10-11` | Runtime destination offset from `$A000`. |
| `12-13` | Entry offset. |
| `14` | Signature id. |
| `15` | Command-name length. |
| `16-31` | Uppercase command name, zero padded. |

The old `RB_CMD_F_LOW` / `RB_CMD_F_HIDDEN` dispatch meaning is obsolete. Macro
names such as `CMD_LOW` remain only as source conveniences for slot-0 system
payloads.

## Guardrails To Keep In Sync

- `build_support/verify_readybasic_plugin.py` must reject resident growth past
  `BASIC_START`, bridge growth past `$C200`, slot overlap, and ReadyBASIC usage
  of `$C600-$C9FF`.
- The ReadyBASIC VICE suite should cover existing commands, module slot proofs,
  span proofs, overlay rotation, no-recopy behavior, and disk module load/use.
- HTML docs should show the post-BASIC steady-state map first; cold-load seed
  placement is secondary because those bytes are reclaimed by BASIC.
