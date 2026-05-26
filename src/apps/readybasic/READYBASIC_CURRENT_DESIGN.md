# ReadyBASIC Current Design

ReadyBASIC is a ReadyOS app that keeps the BASIC program area useful while
adding readable command syntax, native `PROC`/`FUNC`, flow-control helpers, REU
handles, and assembler command modules. The current branch replaces the old
`LOWPACK`/`HIDDENPACK` command split with module-aware descriptors and three
2KB under-ROM submodule slots.

## Design Center

- BASIC text stays readable. Commands are written as `NAME(...)`, not private
  token bytes.
- Resident visible code remains small and below `BASIC_START`.
- Command implementation code lives under BASIC ROM or in REU, not in the BASIC
  program workspace.
- ReadyOS owns the lifecycle. ReadyBASIC must stay inside the `$1000-$C5FF`
  app contract and must never use `$C600-$C9FF` as private scratch.
- Cold seed bytes are temporary. After initialization, BASIC owns `$2AC1-$9FFF`;
  command registries and payloads are authoritative in REU.

## Current Measurements

Measured from `obj/readybasic.map`:

| Item | Value |
| --- | ---: |
| `BASIC_START` | `$2AC1` |
| Empty BASIC free bytes | `30013` |
| `ENTRY` | `$1000-$1102`, `$0103` / 259B |
| `RESIDENT` | `$1200-$2ABB`, `$18BC` / 6332B |
| BASIC sentinel | `$2AC0` |
| `HIDDEN` common under-ROM helper | `$A000-$A364`, `$0365` / 869B |
| Slot 0 `LOWPACK` | `$A800-$AEC6`, `$06C7` / 1735B |
| Slot 1 `SLOTPACK1` | `$B000-$B140`, `$0141` / 321B |
| Slot 2 proof/overlays | `$B800-$B83E`, small proof slices |
| `BRIDGE` | `$C000-$C1F6`, `$01F7` / 503B |
| Shared frames | `$C200-$C5FF`, 1KB |
| Registry seed | `$5000-$600F`, `$1010` / 4112B load-only |

## Command Surface

| Family | Commands | Purpose |
| --- | --- | --- |
| Scalar demos | `ZECHO1`, `ZADD16`, `FADD`, `ZPAUSE`, `ZFAIL`, `FREEMEM`, `ERRCODE`, `ERRLINE` | Integer/float results, waits, error reporting, free-memory reporting. |
| String demos | `UPPER`, `LOWER`, `ZHIDDENRAM` | String staging, result commit, and under-ROM checksum proof. |
| Array demos | `ZSUMNUMARRAY`, `ZRANGENUMARRAY` | Integer array input/output with resident commit. |
| REU handles | `BUFNEW`, `BUFFILL`, `BUFFREE`, `ZTEMPSCRATCH`, `SCRCAP`, `SCRPUT` | Persistent and temporary REU-backed resources. |
| Built-in module proofs | `ZSLOT0`, `ZSLOT1`, `ZSLOT2`, `ZSPAN`, `ZOVL1`, `ZOVL2`, `ZCPYRST`, `ZCOPY` | Slot, span, overlay, and no-recopy tests. |
| Disk module proof | `ZMODLD`, `ZDM1`, `ZDM2S`, `ZDOV1`, `ZDOV2` | Load sample module files from disk into REU and register their commands. |

`ZMODLD(name$)` is intentionally not named `ZMODLOAD`; C64 BASIC tokenizes
keyword text such as `LOAD` inside command names before ReadyBASIC sees it.

## Native Language Features

These features are resident parser/runtime features, not command descriptors:

| Feature | Current behavior |
| --- | --- |
| `PROC NAME(...) ... ENDP` | Stored BASIC routine called with `EXEC NAME(...)`. |
| `FUNC NAME(...) ... RET expr ... ENDP` | Expression routine returning integer, string, or float values. |
| `REPEAT ... UNTIL expr` | Post-test loop, nested four deep. |
| `LABEL name` / `JUMP name` | Named stored-program transfer without changing BASIC `GOTO`. |
| `ERRCODE()` / `ERRLINE()` | Also exposed as commands, backed by resident runtime state. |

Definitions should live after `END`; falling into a `PROC` or `FUNC`
definition is invalid in V1.

## Post-BASIC Memory Map

This is the important picture for day-to-day design. Cold-load placement above
`$2AC1` matters only until ReadyBASIC has copied seed data into REU.

| Range | Owner after initialization | Notes |
| --- | --- | --- |
| `$0000-$00FF` | C64 zero page / BASIC / KERNAL / ReadyBASIC hooks | Saved to REU `$44:$0A00` on suspend. |
| `$0100-$01FF` | Hardware stack | Saved to REU `$44:$0B00` on suspend. |
| `$0200-$03FF` | BASIC/KERNAL page 2/3 vectors and buffers | ReadyBASIC uses execute/eval hooks around `$0308/$030A` and restores them on exit. |
| `$0400-$07E7` | Screen RAM | `SCRCAP` can copy it into an REU screen handle. |
| `$0800-$0FFF` | Low BASIC/system area | Outside ReadyBASIC app-owned region. |
| `$1000-$1102` | Entry | Cold/warm discriminator. |
| `$1200-$2ABB` | ReadyBASIC resident | Visible parser, dispatch, REU helpers, language runtime. |
| `$2AC0` | Sentinel | Must remain zero before stored-program `RUN`. |
| `$2AC1-$9FFF` | BASIC workspace | Program text, variables, arrays, strings, and reclaimed seed bytes. |
| `$A000-$BFFF` | BASIC ROM visible; ReadyBASIC RAM underneath | Common helper plus three 2KB submodule slots when RAM is banked in. |
| `$C000-$C1F6` | ReadyBASIC bridge | Small state below `$C200`. |
| `$C200-$C5FF` | ReadyBASIC frames/buffers | Call frame, result frame, descriptor buffer, command buffer, page buffer, disk-module load page. |
| `$C600-$C7FF` | ReadyOS REU metadata | Not scratch. ReadyBASIC marks bank `$44/$45` ownership here. |
| `$C800-$C9FF` | ReadyOS shim ABI | Not scratch. |
| `$D000-$DFFF` | I/O/char ROM window | VIC/SID/CIA/REU registers when I/O is visible. |
| `$E000-$FFFF` | KERNAL ROM normally visible | KERNAL calls remain available outside under-ROM command execution windows. |

## Under-ROM Slots

ReadyBASIC treats RAM behind BASIC ROM as four 2KB regions:

| Region | Address | Role |
| --- | ---: | --- |
| Common | `$A000-$A7FF` | Existing helper code and future resident-code relief. |
| Slot 0 | `$A800-$AFFF` | Default/system commands; current module 1. |
| Slot 1 | `$B000-$B7FF` | Swappable submodule slot; current module 2 proof and loader. |
| Slot 2 | `$B800-$BFFF` | Swappable submodule/overlay slot. |

Submodules may claim one slot, two adjacent slots, or all three slots. Overlay
payloads are just submodule payload variants that share a target slot; stable
code in another slot can rotate overlays through slot 2 and call them.

## Command Descriptor ABI

Descriptors are stored in REU bank `$44:$1000-$1FFF`. Lookup fetches one
descriptor page at a time into `$C500`, scans eight records locally, and copies
the selected descriptor to `$C480`.

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
| `14` | Parser signature id. |
| `15` | Uppercase command-name length. |
| `16-31` | Uppercase command-name bytes. |

The old dispatch meaning of `RB_CMD_F_LOW` and `RB_CMD_F_HIDDEN` is gone. Source
macros named `CMD_LOW`, `CMD_HIDDEN`, `CMD_SLOT1`, `CMD_SLOT2`, `CMD_SPAN`,
`CMD_OVL1`, and `CMD_OVL2` emit the same module-aware descriptor shape.

## Dispatch Flow

1. BASIC reaches the `$0308` execute hook or the expression hook.
2. ReadyBASIC collects a command name into `$C4A0`.
3. Descriptor lookup scans REU bank `$44` pages through `$C500`.
4. Resident signature parsing validates syntax and fills the call frame at
   `$C200`.
5. The call frame is mirrored to REU `$44:$0400`.
6. Dispatch checks whether the requested module/submodule/overlay is already
   resident in the target slot window.
7. If needed, REU bank `$45` copies the descriptor payload into `$A800`,
   `$B000`, `$B800`, or a span of those slots.
8. RAM under BASIC ROM is mapped in and the worker entry is called.
9. The worker writes the result frame at `$C300`.
10. Resident code restores normal banking, mirrors the result scratch, commits
    output variables or expression return values, and resumes BASIC.

Current residency proof is deliberately tiny: bridge state remembers the last
command/overlay and copy count so tests can prove repeated calls do not recopy.
`RB_REU_SLOT_STATE_OFF=$2000` reserves the future richer REU-backed table.

## REU Layout

### Bank `$44`: Registry and Runtime State

| Offset | Role |
| ---: | --- |
| `$0000` | Registry header. |
| `$0400` | Call/result frame scratch, reused at different moments. |
| `$0600` | Reserved debug ring. |
| `$0800-$09FF` | 128 handle descriptors. |
| `$0A00` | Zero-page snapshot. |
| `$0B00` | Stack-page snapshot. |
| `$0C00-$0CFF` | Heap bitmap. |
| `$1000-$1FFF` | 128 command descriptors. |
| `$2000-$3FFF` | Reserved module/catalog/residency expansion. |
| `$4000-$FFFF` | 48KB typed heap. |

### Bank `$45`: Module Payload Bytes

| Offset | Runtime | Meaning |
| ---: | ---: | --- |
| `$0000` | `$A800` | Built-in module 1 slot-0 payload. |
| `$06C7` | `$B000` | Built-in module 2 slot-1 payload and `ZMODLD`. |
| `$0808` | `$B800` | Built-in module 2 slot-2 payload. |
| `$081D` | `$B000` | Built-in two-slot span proof. |
| `$0832` | `$B815` | Built-in overlay 1 proof. |
| `$0847` | `$B82A` | Built-in overlay 2 proof. |
| `$3000+` | slot-defined | Disk sample module payloads. |

## Disk Module Format

The current sample format is assembler-friendly and intentionally small. Module
files are PRG files loaded at `$C500`; the loader command lives in module 2,
slot 1, so resident code does not grow for disk module policy.

A file begins with:

| Field | Role |
| --- | --- |
| PRG load address | `$C500`, because `$C500-$C5FF` is the ReadyBASIC page/load buffer. |
| Magic | `RBM!`. |
| Version/API | Allows later format changes. |
| Descriptor count | Number of command records to register. |
| Payload directory | REU bank `$45` offsets, sizes, target runtime offsets, slot masks, module/submodule/overlay ids. |
| Command descriptors | 32-byte ReadyBASIC descriptors copied into bank `$44`. |
| Payload bytes | Assembler payloads copied into bank `$45`. |

`RBM1` proves a single-slot disk command (`ZDM1`). `RBM2` proves a two-slot
span command (`ZDM2S`) and two overlay commands (`ZDOV1`, `ZDOV2`). Future
formats may allocate additional REU banks if `$45` has insufficient space, but
that decision stays behind the loader command boundary.

## Cold Init, Warm Resume, Exit

Cold entry:

1. Copies hidden/common helper code into `$A000`.
2. Copies bridge code/state into `$C000`.
3. Marks REU banks `$44/$45` in ReadyOS metadata.
4. Stashes registry seed into `$44` and built-in payload seed into `$45`.
5. Installs BASIC execute/eval hooks.
6. Initializes BASIC pointers so `$2AC1-$9FFF` is the workspace.

Warm resume:

1. Re-enters through ReadyOS after the app region is restored.
2. Re-marks REU ownership.
3. Reuses REU registry/payload/handle state.
4. Restores zero page and stack snapshots when returning to BASIC mode.

Exit:

1. Restores BASIC/KERNAL vectors owned by ReadyBASIC.
2. Saves zero page and stack into bank `$44`.
3. Leaves ReadyOS-owned metadata and shim space intact.

## Documentation Set

| File | Purpose |
| --- | --- |
| `READYBASIC_PLUGIN_ARCH.md` | Compact architecture and ABI summary. |
| `READYBASIC_LIFECYCLE_AND_REU_ARCHITECTURE.md` | Detailed memory, lifecycle, REU, and disk-module design. |
| `READYBASIC_MAKING_COMMAND_GUIDE.md` | Practical guide for adding or changing command modules. |
| `READYBASIC_MICROMODULE_SYNC.md` | Constants ledger to keep source, checker, and docs aligned. |
| `REadyBASICCommandModuleAndSubmodulePlan.MD` | Original plan and design rationale. |
| `CommandModuleSubmoduleLessonsLearnt.md` | Slice-by-slice implementation notes and test outcomes. |
| `readybasic_*.html` | Visual versions of the current design and command guide. |

## Guardrails

- Resident code must fit below `BASIC_START`.
- Bridge code must stay below `$C200`.
- Shared ReadyBASIC frames must stay within `$C200-$C5FF`.
- No ReadyBASIC scratch or code may enter `$C600-$C9FF`.
- Under-ROM slots must remain 2KB aligned and non-overlapping.
- Disk-loaded modules must register descriptors and payloads in REU, not rely
  on transient `$C500` file bytes after loading.
- New command names must be screened against BASIC tokenizer collisions.
