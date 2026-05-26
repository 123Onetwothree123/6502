# ReadyBASIC REU Plugin Architecture

This is the compact architecture note for the current ReadyBASIC command
module branch. For the full memory/lifecycle walkthrough, see
`READYBASIC_LIFECYCLE_AND_REU_ARCHITECTURE.md`. For adding commands, see
`READYBASIC_MAKING_COMMAND_GUIDE.md`.

## Current Steady-State Layout

After ReadyBASIC finishes cold initialization, BASIC owns the normal program
workspace from `BASIC_START=$2AC1` through `$9FFF`. The empty BASIC formula
reports `30013` free bytes. Cold seed bytes that were loaded above `$2AC1` are
not persistent C64 RAM; they have already been copied into REU banks.

| Region | Address | Size | Role |
| --- | ---: | ---: | --- |
| Entry | `$1000-$1102` | `$0103` / 259B | Cold/warm discriminator and startup handoff. |
| Resident | `$1200-$2ABB` | `$18BC` / 6332B | Parser hooks, BASIC ROM calls, REU DMA wrappers, dispatch, commit, native language features. |
| BASIC sentinel | `$2AC0` | 1B | Must remain zero before stored-program `RUN`. |
| BASIC workspace | `$2AC1-$9FFF` | 30013 formula bytes free | Program text, variables, arrays, strings, and reclaimed cold seed space. |
| Common under-ROM | `$A000-$A7FF` | 2KB window, `$0365` used | Helper code under BASIC ROM. |
| Submodule slot 0 | `$A800-$AFFF` | 2KB window, `$06C7` used | Default/system command module. |
| Submodule slot 1 | `$B000-$B7FF` | 2KB window, `$0141` used | Built-in proof module and `ZMODLD` loader command. |
| Submodule slot 2 | `$B800-$BFFF` | 2KB window, overlay proof bytes used | Proof commands and overlay targets. |
| Bridge | `$C000-$C1F6` | `$01F7` / 503B | Small state, return stacks, dispatch scratch below `$C200`. |
| Shared frames | `$C200-$C5FF` | 1KB | Call/result frames, descriptor buffer, command buffer, page buffer, disk-module load page. |
| ReadyOS REU metadata | `$C600-$C7FF` | 512B | Shared ReadyOS allocation table. ReadyBASIC only marks ownership here. |
| ReadyOS shim ABI | `$C800-$C9FF` | 512B | Shim jump table/data. Not ReadyBASIC scratch. |

ReadyBASIC never treats `$C600-$C9FF` as private app RAM. Normal verification
must boot ReadyOS through `run.sh` / `run.ps1`; direct single-app launch misses
the launcher and shim contract.

## Under-ROM Command Model

All descriptor-backed commands are under-ROM commands now. The old special
"hidden command" distinction is gone at dispatch time: a descriptor says which
module/submodule/overlay payload is needed, where it lives in REU bank `$45`,
and which under-BASIC-ROM runtime address receives it.

The under-ROM layout is deliberately proportional:

| Window | Address | Meaning |
| --- | ---: | --- |
| Common | `$A000-$A7FF` | Shared helpers, REU prestash/save/restore routines, and future resident-code relief. |
| Slot 0 | `$A800-$AFFF` | Preferred always-useful system submodule. Current `LOWPACK` runs here. |
| Slot 1 | `$B000-$B7FF` | Swappable submodule slot. Current built-in proof/loader submodule runs here. |
| Slot 2 | `$B800-$BFFF` | Swappable submodule/overlay slot. Current slot-2 and overlay proofs run here. |

A submodule may claim one slot, two adjacent slots, or all three slots. A
six-kilobyte exclusive submodule cannot assume slot-0 helper code remains in
place unless it calls only resident ABI services or brings its own helper code.

## REU Banks

ReadyBASIC reserves two fixed REU banks and marks them in the ReadyOS allocation
table at `$C600+$44` and `$C600+$45`:

| Bank | Type | Purpose |
| ---: | ---: | --- |
| `$44` | 14 | Runtime registry, command descriptors, handle directory, snapshots, typed heap, and reserved module metadata. |
| `$45` | 15 | Built-in and disk-loaded command/module payload bytes. |

Cold entry copies the registry seed and built-in command payloads into those
banks. Warm resume re-marks ownership and reuses REU state; it must not trust
the old load-image bytes inside the BASIC workspace.

### Bank `$44`

| Offset | Role |
| ---: | --- |
| `$0000` | Registry header: magic/version, descriptor count/size, frame offsets. |
| `$0400` | Call/result snapshot scratch. The call and result frame snapshots reuse this offset at different moments. |
| `$0600` | Reserved debug ring area. |
| `$0800-$09FF` | 128 handle descriptors, 4 bytes each. |
| `$0A00` | Zero-page snapshot for ReadyOS suspend/resume. |
| `$0B00` | Hardware stack-page snapshot for ReadyOS suspend/resume. |
| `$0C00-$0CFF` | Heap page bitmap for the 48KB typed heap. |
| `$1000-$1FFF` | 128 command descriptors, 32 bytes each. Disk module samples currently register at descriptor pages starting `$1500` and `$1600`. |
| `$2000-$3FFF` | Reserved module/catalog/residency expansion space. The current proof keeps only a tiny last-command copy counter in bridge RAM. |
| `$4000-$FFFF` | Typed heap for byte buffers and screen text/color handles. |

### Bank `$45`

| Offset | Payload | Runtime |
| ---: | --- | --- |
| `$0000-$06C6` | Built-in module 1, system/default slot 0 | `$A800-$AEC6` |
| `$06C7-$0807` | Built-in module 2, slot 1 including `ZMODLD` | `$B000-$B140` |
| `$0808-$081C` | Built-in module 2, slot 2 proof | `$B800-$B814` |
| `$081D-$0831` | Built-in two-slot span proof payload | `$B000-$B014` |
| `$0832-$0846` | Built-in overlay proof 1 | `$B815-$B829` |
| `$0847-$085B` | Built-in overlay proof 2 | `$B82A-$B83E` |
| `$3000` | Disk sample `RBM1` command `ZDM1` | slot 1 |
| `$3200` | Disk sample `RBM2` command `ZDM2S` | slots 1+2 span |
| `$3300` | Disk sample `RBM2` overlay command `ZDOV1` | slot 2 overlay |
| `$3400` | Disk sample `RBM2` overlay command `ZDOV2` | slot 2 overlay |

## Descriptor ABI

Every command descriptor is 32 bytes:

| Byte(s) | Meaning |
| ---: | --- |
| `0` | Stable command id. |
| `1` | Module id. |
| `2-3` | Payload offset in REU bank `$45`. |
| `4-5` | Payload size to copy when the submodule/overlay is not resident. |
| `6` | Submodule id. |
| `7` | Overlay id (`0` for normal submodules). |
| `8` | Slot mask: bit 0 = `$A800`, bit 1 = `$B000`, bit 2 = `$B800`. |
| `9` | Generation/check byte used by residency logic. |
| `10-11` | Runtime destination offset from `$A000`. |
| `12-13` | Entry offset within the copied runtime payload. |
| `14` | Parser signature id. |
| `15` | Uppercase command-name length. |
| `16-31` | Uppercase command-name bytes, zero padded. |

Dispatch always parses in resident code first, mirrors the call frame to REU
bank `$44`, fetches the descriptor-selected payload from `$45` only when needed,
maps RAM under BASIC ROM, calls the entry, restores normal banking, then commits
the result in resident code.

## Implemented Command Families

| Family | Commands |
| --- | --- |
| Scalar/string/array demos | `ZECHO1`, `ZADD16`, `UPPER`, `LOWER`, `ZHIDDENRAM`, `ZSUMNUMARRAY`, `ZRANGENUMARRAY`, `FADD`, `ZPAUSE`, `ZFAIL`, `FREEMEM`, `ERRCODE`, `ERRLINE` |
| REU-backed handles | `BUFNEW`, `BUFFILL`, `BUFFREE`, `ZTEMPSCRATCH`, `SCRCAP`, `SCRPUT` |
| Built-in module proofs | `ZSLOT0`, `ZSLOT1`, `ZSLOT2`, `ZSPAN`, `ZOVL1`, `ZOVL2`, `ZCPYRST`, `ZCOPY` |
| Disk module proof | `ZMODLD`, then `ZDM1`, `ZDM2S`, `ZDOV1`, `ZDOV2` after loading `RBM1`/`RBM2` |

`ZMODLD` intentionally avoids the suffix `LOAD`; C64 BASIC tokenizes keyword
text inside command names, so names must be screened before becoming public.

Native `PROC`/`FUNC`, `EXEC`, `REPEAT`/`UNTIL`, `LABEL`/`JUMP`, and direct
runtime error introspection are resident language features. They do not consume
command descriptors or bank `$45` payload bytes unless they call a command.
