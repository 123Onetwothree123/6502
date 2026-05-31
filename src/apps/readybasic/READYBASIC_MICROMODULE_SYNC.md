# ReadyBASIC Micromodule Sync Ledger

ReadyBASIC now duplicates a small amount of ReadyOS REU and shim knowledge in assembler. Keep this file updated whenever either side changes.

## Current Module/Submodule Constants

The module/submodule design keeps the fixed ReadyOS contract and updates the
under-ROM command layout:

| Constant or range | Current value |
|---|---:|
| `BASIC_START` | `$2AC1` |
| Formula empty BASIC bytes | `30013` |
| `RESIDENT` | `$1200-$2ABB`, `$18BC` |
| Common under-ROM helper | `$A000-$A7FF`, current use `$A000-$A364` |
| Submodule slot 0 | `$A800-$AFFF`, current module 1 payload `$A800-$AEC6` |
| Submodule slot 1 | `$B000-$B7FF`, current module 2 payload `$B000-$B140` |
| Submodule slot 2 | `$B800-$BFFF`, current proof/overlay payloads through `$B83E` |
| `BRIDGE` | `$C000-$C1F6`, `$01F7` |
| Shared frames | `$C200-$C5FF` |

Descriptor byte 1 is now module id, not a `LOW`/`HIDDEN` flag. Descriptor bytes
2-13 identify payload offset/size in REU bank `$45`, submodule id, overlay id,
slot mask, generation/check byte, runtime destination offset from `$A000`, and
entry offset. Byte 14 remains the signature id, and bytes 15-31 remain the
uppercase name field.

## REU DMA Registers

- ReadyBASIC source: `src/apps/readybasic/readybasic.s`
- Mirrored concepts from:
  - `src/lib/reu_mgr_dma.c`
  - `src/lib/reu_mgr.h`
- Constants:
  - `$DF01`: command register.
  - `$DF02-$DF03`: C64 address.
  - `$DF04-$DF05`: REU offset.
  - `$DF06`: REU bank.
  - `$DF07-$DF08`: transfer length.
  - `$90`: C64 to REU stash.
  - `$91`: REU to C64 fetch.

## Fixed ReadyBASIC REU Banks

- ReadyBASIC assembler:
  - `RB_REU_CORE_BANK = $44`
  - `RB_REU_CODE_BANK = $45`
  - `RB_REU_DESC_OFF = $1000`
  - `RB_CMD_DESC_COUNT = 128`
  - `RB_REU_TYPE_CORE = 14`
  - `RB_REU_TYPE_CODE = 15`
- ReadyOS C mirrors:
  - `src/lib/reu_mgr.h`
  - `src/lib/reu_mgr_init.c`
  - `src/apps/reuviewer/reuviewer.c`
- Static checker:
  - `build_support/verify_readybasic_plugin.py`

## Shim / Resume Boundary

- ReadyBASIC still uses:
  - `SHIM_RETURN = $C80C`
  - bridge state at `$C000-$C1F3`
  - shared frames and visible helper shadow at `$C200-$C5FF`
  - app runtime zero-page/stack save in REU bank `$44` offsets `$0A00/$0B00`
- Do not place ReadyBasic state in `$C800-$C9FF`; that remains shim ABI territory.
- Do not use `$C600-$C7FF` as ReadyBASIC scratch; it remains ReadyOS REU metadata.

## Current ReadyBASIC Memory Snapshot

- `BASIC_START = $2AC1`; BASIC owns `$2AC1-$9FFF`, with `30013` formula empty free bytes.
- `ENTRY` lives at `$1000-$1102`.
- `RESIDENT` lives at `$1200-$2ABB` (`$18BC`, 6332B) and must stay below `$2AC0`.
- `CMDPACK` load-only seed space is `$2B00-$3FFF`; it is copied to REU bank `$45` on cold entry.
- `HIDLOAD` load-only helper seed starts at `$4000`.
- `BRLOAD` load-only bridge seed starts at `$4800`.
- `REGSEED` load-only registry seed is `$5000-$600F`, size `$1010`.
- Runtime common under-ROM helper code is `$A000-$A364`, size `$0365` / 869B.
- Runtime submodule slot 0 is `$A800-$AFFF`; current module 1/default payload uses `$A800-$AEC6`, size `$06C7` / 1735B.
- Runtime submodule slot 1 is `$B000-$B7FF`; current module 2 proof/streaming loader payload uses `$B000-$B238`, size `$0239` / 569B.
- Runtime submodule slot 2 is `$B800-$BFFF`; current proof/overlay payloads use `$B800-$B83E` in 21B slices.
- Runtime `BRIDGE` is `$C000-$C1F8`, size `$01F9` / 505B; the native `PROC`/`FUNC`
  return stack and flow-control scratch live here and must stay below shared frames at `$C200`.

## Bank `$44` ReadyBASIC Core Layout

- `$0000`: registry header.
- `$0400`: current call-frame snapshot.
- `$0400`: current result-frame snapshot.
- `$0600`: reserved debug region.
- `$0800-$09FF`: REU-backed handle directory, 128 descriptors at 4 bytes each.
- `$0A00`: zero-page snapshot.
- `$0B00`: stack-page snapshot.
- `$0C00-$0CFF`: heap page bitmap, 192 pages tracked in REU.
- `$1000-$1FFF`: 128 command descriptor slots, 32 bytes each. Slots 1-16 are current front commands, slots 17-127 are filler, and slot 128 is `SCRPUT`.
- `$2000-$3FFF`: reserved common/system expansion space.
- `$4000-$FFFF`: typed handle heap, 48KB.

Command lookup fetches one 256-byte descriptor page at a time into `$C500`,
scans eight descriptors locally, and copies the matched descriptor into
`$C480`. Zero-filled descriptors are filler/empty slots.

## Bank `$45` Command Code Layout

- `$0000-$06C6`: built-in module 1/default slot-0 payload, fetched to `$A800-$AEC6`.
- `$06C7-$08FF`: built-in module 2 slot-1 proof and streaming `ZMODLD` loader payload, fetched to `$B000-$B238`.
- `$0900-$0914`: built-in module 2 slot-2 proof payload, fetched to `$B800-$B814`.
- `$0915-$0929`: built-in two-slot span proof payload, fetched to `$B000-$B014`.
- `$092A-$093E`: built-in slot-2 overlay proof 1, fetched to `$B815-$B829`.
- `$093F-$0953`: built-in slot-2 overlay proof 2, fetched to `$B82A-$B83E`.
- `$1500-$151F`: `rbm.sample1` disk-module descriptor sample for `ZDM1`.
- `$1600-$165F`: `rbm.sample2` disk-module descriptor samples for `ZDM2S`, `ZDOV1`, and `ZDOV2`.
- `$1700-$1ABF`: `rbm.sample3` disk-module descriptors for `ZSAA`-`ZUEB`.
- `$3000-$3014`, `$3200-$3214`, `$3300-$3314`, `$3400-$3414`: current small disk-module proof payloads.
- `$3800-$4629`: `rbm.sample3` payload records for `ZSAA`-`ZUEB`.

Cold entry prestashes these bytes once. Warm resume reuses the REU copies and
must not reread `CMDPACK`, `HIDLOAD`, `BRLOAD`, or `REGSEED` from BASIC-owned
load-image addresses.

Native `PROC`/`FUNC` routines are deliberately absent from bank `$45`: their
bodies are BASIC program text, found by scanning the stored program during
`EXEC`. They add no descriptor slots and no command-code bank bytes.

## Current Nested-Term Sync Points

ReadyBASIC keeps the command overlay layout stable while supporting targeted
ROM-consumable command/`FUNC` returns and one-wrapper numeric actual parsing.

- Proven targeted nested return forms: `ABS(ADDI(1,6)-10)` and
  `LEFT$(GREET("READY"),2)`.
- Proven one-wrapper numeric actual forms: `ADDI(1,(2+4))`,
  `ZADD16(1,(2+4))`, and `ADDI((1+2),(3+4))`.

## Current Float-Term Sync Points

ReadyBASIC keeps the fixed frame addresses and supports float slots in the
call/result frame plus resident state preservation for nested ReadyBASIC
expression terms.

- `FADD(A,B)` and `FADD(A,B,Q)` use plain C64 BASIC float values.
- Proven proper-term forms include `ADDI(1,ADDI(2,3))`,
  `FADD(1.5,FADD(2.25,3.25))`, `ABS(FADD(1.2,2.3)-3)`, and
  `LEFT$(GREET("READY")+"!",3)`.

## Current Expression-Style Sync Points

ReadyBASIC supports bare `COMMAND(...)` statements plus an eval-vector hook, but
keeps command overlays unchanged. Expression-safe command calls are resident
dispatch wrappers over existing descriptors.

- Bare statement commands use the same descriptor/signature parser as expression
  commands.
- Command expressions cover scalar/string-result signatures such as
  `ZECHO1()`, `ZADD16(a,b)`, `UPPER(s$)`, `LOWER(s$)`, `ZHIDDENRAM(s$)`,
  `BUFNEW(n)`, `ZTEMPSCRATCH(n)`, `SCRCAP()`, and `ZSUMNUMARRAY(a%(0),n)`.
- String and numeric `FUNC` calls return through `RET`, `RET%`, or `RET$`.
  `FUNC` is expression-only; calls scan the body, execute simple scalar
  assignments before `RET`, and evaluate
  that expression.

## Typed Handles

- Live handle count is 128.
- Handle descriptors and the 192-page heap bitmap are canonical in REU.
- Type `1` is a byte buffer.
- Type `2` is a screen text+color buffer.
- `BUFFILL` accepts only type `1`.
- `BUFFREE` frees any valid handle type.
- `SCRPUT` accepts only type `2`.

## Banking Discipline

- Visible resident code calls BASIC ROM helpers only with normal `$01=$37`.
- Hidden helper and hidden worker calls set low CPU port bits for RAM under BASIC while keeping KERNAL visible.
- Any future hidden worker that needs KERNAL calls must preserve this mode and restore `$01`.
- Any future worker that disables KERNAL too needs its own ledger entry and a tighter trampoline contract.

## Future Full-System Commands

The current plugin spine can support a command that takes over most of the machine only if the command returns through ReadyBasic's resident completion path. A custom suspend/resume command that bypasses the launcher would need new ABI notes; a command that wants ReadyOS-visible app switching or global storage still needs shim/launcher-level coordination rather than only plugin changes.
