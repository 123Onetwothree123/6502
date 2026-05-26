# ReadyBASIC Lifecycle And REU Architecture

This note describes the memory picture that matters after ReadyBASIC has
initialized BASIC, then works backward to explain cold seed data, REU registries,
under-ROM modules, overlays, disk module files, suspend/resume, and guardrails.

## The Important Picture: After BASIC Is Initialized

ReadyBASIC's steady state is designed around one promise: the user gets a real
BASIC workspace, while command code and persistent command data live outside
that workspace.

Current measured values:

| Measurement | Value |
| --- | ---: |
| `BASIC_START` | `$2AC1` |
| Empty BASIC free bytes | `30013` |
| Resident visible core | `$1200-$2ABB`, `$18BC` / 6332B |
| Bridge | `$C000-$C1F6`, `$01F7` / 503B |
| Shared frame/buffer area | `$C200-$C5FF`, 1KB |
| Built-in payload bytes in REU `$45` | `$0000-$085B` |

## C64 Memory Map

| Range | Owner / visibility after init | ReadyBASIC meaning |
| --- | --- | --- |
| `$0000-$00FF` | CPU/BASIC/KERNAL zero page | ReadyBASIC uses only explicit known locations. It saves this page to REU `$44:$0A00` for suspend/resume. |
| `$0100-$01FF` | Hardware stack | Saved to REU `$44:$0B00` on suspend/resume. |
| `$0200-$02FF` | BASIC/KERNAL workspace | Used only according to ROM conventions. |
| `$0300-$03FF` | Vectors and buffers | ReadyBASIC owns the execute/eval hook vectors while active and restores them on exit. |
| `$0400-$07E7` | Screen RAM | `SCRCAP` copies this and color RAM into a typed REU handle. |
| `$0800-$0FFF` | Low BASIC/system RAM | Not ReadyBASIC app-owned RAM. |
| `$1000-$1102` | Entry segment | Startup discriminator and handoff. |
| `$1103-$11FF` | Gap | Not used as a large persistent structure. |
| `$1200-$2ABB` | ReadyBASIC resident | Visible code that can call BASIC ROM. |
| `$2AC0` | BASIC sentinel | Must remain zero before stored-program `RUN`. |
| `$2AC1-$9FFF` | BASIC workspace | Program text, variables, arrays, strings, and reclaimed cold seed bytes. |
| `$A000-$BFFF` | BASIC ROM visible, RAM underneath | ReadyBASIC maps RAM underneath only when helpers or command slots run. |
| `$C000-$C1F6` | ReadyBASIC bridge | Small state, return stacks, dispatch scratch. Must stay below `$C200`. |
| `$C200-$C2FF` | Call frame | Parsed input values for command workers. |
| `$C300-$C3FF` | Result frame | Command worker output for resident commit. |
| `$C400-$C47F` | Runtime scratch/staging | Zero-page restore and small runtime staging. |
| `$C480-$C49F` | Descriptor buffer | One 32-byte selected descriptor. |
| `$C4A0-$C4FF` | Command/name buffer | Parsed command text and small strings. |
| `$C500-$C5FF` | Page/load buffer | Descriptor page scans, heap pages, stack staging, and `ZMODLD` PRG load target. |
| `$C600-$C7FF` | ReadyOS REU metadata | Shared table. ReadyBASIC only marks `$44/$45` bank ownership here. |
| `$C800-$C9FF` | ReadyOS shim ABI | Jump table/data. Never ReadyBASIC scratch. |
| `$CA00-$CFFF` | Upper RAM outside ReadyBASIC contract | Avoid unless ReadyOS explicitly assigns it. |
| `$D000-$DFFF` | I/O or character ROM | REU registers live at `$DF01-$DF08` when I/O is visible. |
| `$E000-$FFFF` | KERNAL ROM normally visible | KERNAL calls remain available when normal banking is restored. |

## Banking Model

Normal BASIC execution keeps BASIC ROM, I/O, and KERNAL ROM visible. During
under-ROM helper or command execution, ReadyBASIC temporarily maps RAM behind
BASIC ROM so the code at `$A000-$BFFF` can execute. It then restores normal
banking before returning to BASIC or using ROM services again.

The common helper at `$A000` is for bank-sensitive work and routines that should
not permanently occupy visible resident memory. Command submodules live in the
three slots above it.

## Under-ROM Module Slots

| Area | Range | Current contents | Design intent |
| --- | ---: | --- | --- |
| Common | `$A000-$A7FF` | `HIDDEN` helper, `$0365` used | Shared helpers and future resident-code relief. |
| Slot 0 | `$A800-$AFFF` | Built-in module 1 `LOWPACK`, `$06C7` used | Default/system commands that are called often. |
| Slot 1 | `$B000-$B7FF` | Built-in module 2 proof and `ZMODLD`, `$0141` used | Swappable modules and stable overlay managers. |
| Slot 2 | `$B800-$BFFF` | Slot proof and overlay proof payloads | Swappable modules and overlay target. |

Slot masks use bit 0 for slot 0, bit 1 for slot 1, and bit 2 for slot 2. A
submodule can occupy one slot, two adjacent slots, or the full 6KB. Full-span
submodules cannot assume slot-0 helpers are still resident unless they use
resident ABI routines or carry their own helpers.

## Modules, Submodules, And Overlays

A module is a command package. A submodule is the runtime code image that can be
copied from REU into one or more under-ROM slots. An overlay is another payload
for a submodule-controlled target slot.

Examples in the current build:

| Shape | Proof command | Runtime behavior |
| --- | --- | --- |
| Slot 0 | `ZSLOT0` | Uses built-in module 1 in `$A800-$AFFF`. |
| Slot 1 | `ZSLOT1` | Fetches module 2 payload to `$B000-$B7FF`. |
| Slot 2 | `ZSLOT2` | Fetches module 2 payload to `$B800-$BFFF`. |
| Two-slot span | `ZSPAN` / `ZDM2S` | Copies one payload spanning slots 1 and 2. |
| Overlay rotation | `ZOVL1`, `ZOVL2`, `ZDOV1`, `ZDOV2` | Replaces the target overlay payload and returns distinct proof values. |
| No-recopy proof | `ZCPYRST`, `ZCOPY` | Resets and reports the copy count so repeated resident payload calls can be tested. |

The current no-recopy proof uses tiny bridge variables for the last command and
overlay identity. The reserved REU region `$44:$2000-$3FFF` is the planned home
for a richer per-slot table containing module id, submodule id, overlay id,
generation/checksum, slot mask, and payload location.

## Descriptor Registry

ReadyBASIC has 128 descriptor slots. Each descriptor is 32 bytes, and the table
lives in REU bank `$44:$1000-$1FFF`. Built-in descriptors are copied from
`REGSEED` during cold init. Disk module descriptors are copied into free
descriptor pages by `ZMODLD`.

| Byte(s) | Field |
| ---: | --- |
| `0` | Command id. |
| `1` | Module id. |
| `2-3` | Payload offset in REU bank `$45`. |
| `4-5` | Payload size. |
| `6` | Submodule id. |
| `7` | Overlay id. |
| `8` | Slot mask. |
| `9` | Generation/check byte. |
| `10-11` | Runtime destination offset from `$A000`. |
| `12-13` | Entry offset inside the runtime payload. |
| `14` | Parser signature id. |
| `15` | Command-name length. |
| `16-31` | Uppercase command name. |

The descriptor is intentionally assembler-friendly: it can be emitted by macros
or by the disk module generator without relocation records.

## REU Bank `$44`

Bank `$44` is ReadyBASIC's core/runtime bank:

| Offset | Size | Purpose |
| ---: | ---: | --- |
| `$0000` | small header | `RBPL` registry header and frame offsets. |
| `$0400` | up to 256B | Call/result frame scratch, reused at different times. |
| `$0600` | reserved | Debug ring region. |
| `$0800-$09FF` | 512B | 128 handle descriptors. |
| `$0A00` | 256B | Saved zero page. |
| `$0B00` | 256B | Saved hardware stack. |
| `$0C00-$0CFF` | 256B | Heap bitmap for typed heap pages. |
| `$1000-$1FFF` | 4096B | 128 command descriptors. |
| `$2000-$3FFF` | 8192B | Reserved module catalog and slot residency metadata. |
| `$4000-$FFFF` | 48KB | Typed heap data for buffers and screen handles. |

Handle type `1` is a byte buffer. Handle type `2` is a screen text+color
capture. Future long-lived command data should prefer REU handles or additional
REU banks over fixed C64 RAM.

## REU Bank `$45`

Bank `$45` stores command/module payload bytes:

| Offset | Payload | Runtime target |
| ---: | --- | --- |
| `$0000-$06C6` | Built-in module 1 slot-0 payload | `$A800-$AEC6` |
| `$06C7-$0807` | Built-in module 2 slot-1 payload including `ZMODLD` | `$B000-$B140` |
| `$0808-$081C` | Built-in module 2 slot-2 proof | `$B800-$B814` |
| `$081D-$0831` | Built-in module 2 two-slot proof | `$B000-$B014` |
| `$0832-$0846` | Built-in overlay proof 1 | `$B815-$B829` |
| `$0847-$085B` | Built-in overlay proof 2 | `$B82A-$B83E` |
| `$3000` | Disk module `RBM1` payload | slot 1 |
| `$3200` | Disk module `RBM2` span payload | slots 1+2 |
| `$3300` | Disk module `RBM2` overlay 1 | slot 2 |
| `$3400` | Disk module `RBM2` overlay 2 | slot 2 |

If a future disk loader cannot fit a module in `$45`, it may allocate another
REU bank and extend the metadata. That is a loader-module decision, not a
resident-core decision.

## Cold Seed Memory

Before BASIC is initialized, `readybasic.prg` contains seed bytes that are
copied into their runtime homes:

| Seed | Load range | Destination |
| --- | ---: | --- |
| Built-in payload seed | begins `$2B00` | REU `$45` payload offsets. |
| Hidden/common seed | `$4000` load image | `$A000` runtime helper. |
| Bridge seed | `$4800` load image | `$C000` runtime bridge. |
| Registry seed | `$5000-$600F` | REU `$44:$0000` header and `$44:$1000` descriptors. |

After this copy, the load-image addresses inside `$2AC1-$9FFF` are disposable
BASIC workspace. Warm resume must use REU and runtime homes, not those old seed
addresses.

## Disk Module Files

Sample disk modules are generated by
`build_support/build_readybasic_disk_modules.py` and placed on ReadyBASIC-capable
disk profiles. `ZMODLD(name$)` loads one into `$C500`, validates it, copies
descriptors to REU bank `$44`, copies payloads to bank `$45`, clears residency,
and returns.

The sample files prove:

| Disk file | Commands | Layout proof |
| --- | --- | --- |
| `RBM1` | `ZDM1` | Single-slot disk-loaded command. |
| `RBM2` | `ZDM2S`, `ZDOV1`, `ZDOV2` | Two-slot span and overlay rotation. |

The format is custom and intentionally fixed-address. Payloads are assembler
code linked for their runtime slot addresses; they are not relocatable objects.

## Command Call Lifecycle

1. Parser hook sees a possible command name.
2. Name bytes are uppercased into `$C4A0`.
3. Descriptor pages are fetched from REU `$44` into `$C500`.
4. The matching descriptor is copied into `$C480`.
5. Signature parsing runs in resident code and fills `$C200`.
6. `$C200` is mirrored to REU `$44:$0400`.
7. Dispatch checks residency and fetches REU `$45` payload bytes only if needed.
8. RAM under BASIC ROM is mapped in and the worker executes.
9. The worker writes `$C300`.
10. Resident code restores banking, commits output variables/expressions, and
    records errors in bridge state.

## Suspend, Resume, And Exit

ReadyBASIC participates in ReadyOS app switching:

| Event | ReadyBASIC action |
| --- | --- |
| Cold start | Prestash registries/payloads, install hooks, initialize BASIC workspace. |
| Manual `EXIT` / app switch | Save zero page to `$44:$0A00`, stack to `$44:$0B00`, preserve bridge guards, restore vectors. |
| Warm resume | Re-mark bank ownership, restore hooks and snapshots, reuse REU registry/payload/handle state. |

KERNAL/disk I/O may clobber app memory inside the active region. Persistent
control state belongs in known bridge fields, ReadyBASIC frames, or REU, not in
ad-hoc scratch.

## Current Guardrail Checks

Static checks should enforce:

- Resident remains below `BASIC_START`.
- Bridge remains below `$C200`.
- Shared frames remain within `$C200-$C5FF`.
- No ReadyBASIC scratch/code enters `$C600-$C9FF`.
- Under-ROM slot ranges are 2KB aligned and non-overlapping.
- `REGSEED` remains 128 descriptors of 32 bytes.
- Disk-module proof commands do not require resident loader policy beyond the
  module-2 `ZMODLD` command.

Functional VICE coverage should include existing command behavior, module slot
proofs, span proofs, overlay proofs, no-recopy checks, disk module load/use, and
warm resume.
