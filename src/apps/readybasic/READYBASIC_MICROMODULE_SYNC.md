# ReadyBASIC Micromodule Sync Ledger

ReadyBASIC now duplicates a small amount of ReadyOS REU and shim knowledge in assembler. Keep this file updated whenever either side changes.

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
  - bridge state at `$C000-$C1FA`
  - shared frames and visible helper shadow at `$C200-$C5FF`
  - app runtime zero-page/stack save in REU bank `$44` offsets `$0A00/$0B00`
- Do not place ReadyBasic state in `$C800-$C9FF`; that remains shim ABI territory.
- Do not use `$C600-$C7FF` as ReadyBASIC scratch; it remains ReadyOS REU metadata.

## Current ReadyBASIC Memory Snapshot

- `BASIC_START = $2101`; BASIC owns `$2101-$9FFF`, with `32509` formula empty free bytes and `32519` live header bytes.
- `ENTRY` lives at `$1000-$1102`.
- `RESIDENT` lives at `$1200-$20F3` and must stay below `$2100`.
- `CMDPACK` load-only seed space is `$2800-$3FFF`; it is copied to REU bank `$45` on cold entry.
- `HIDLOAD` load-only helper seed starts at `$4000`.
- `BRLOAD` load-only bridge seed starts at `$4800`.
- `REGSEED` load-only registry seed is `$5000-$600F`, size `$1010`.
- Runtime `LOWPACK` is `$A900-$AF19`, size `$061A`.
- Runtime `HIDDENPACK` is `$A800-$A84C`, size `$004D`.
- Runtime `BRIDGE` is `$C000-$C1FA`, size `$01FB`; the native `PROC`/`FUNC`
  return stack lives here and must stay below shared frames at `$C200`.

## Bank `$44` ReadyBASIC Core Layout

- `$0000`: registry header.
- `$0400`: current call-frame snapshot.
- `$0500`: current result-frame snapshot.
- `$0600`: reserved debug region.
- `$0800-$09FF`: REU-backed handle directory, 128 descriptors at 4 bytes each.
- `$0A00`: zero-page snapshot.
- `$0B00`: stack-page snapshot.
- `$0C00-$0CFF`: heap page bitmap, 192 pages tracked in REU.
- `$1000-$1FFF`: 128 command descriptor slots, 32 bytes each. Slots 1-14 are current front commands, slots 15-127 are filler, and slot 128 is `SCRPUT`.
- `$2000-$3FFF`: reserved common/system expansion space.
- `$4000-$FFFF`: typed handle heap, 48KB.

Command lookup fetches one 256-byte descriptor page at a time into `$C500`,
scans eight descriptors locally, and copies the matched descriptor into
`$C480`. Zero-filled descriptors are filler/empty slots.

## Bank `$45` Command Code Layout

- `$0000-$0619`: packed low overlay code fetched to `$A900-$AF19`.
- `$061A-$0666`: packed hidden worker code fetched to `$A800-$A84C`.

Cold entry prestashes these bytes once. Warm resume reuses the REU copies and
must not reread `CMDPACK`, `HIDLOAD`, `BRLOAD`, or `REGSEED` from BASIC-owned
load-image addresses.

Native `PROC`/`FUNC` routines are deliberately absent from bank `$45`: their
bodies are BASIC program text, found by scanning the stored program during
`EXEC`. They add no descriptor slots and no command-code bank bytes.

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
