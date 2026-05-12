# ReadyBASIC Lean REU Plugin Architecture

## Current V1 Layout

- `BASIC_START = $3001`; BASIC owns `$3001-$95FF`.
- `$1000-$1102`: tiny app entry that copies hidden helpers and bridge state before BASIC starts.
- `$1200-$1ABE`: visible resident core. This is the only code that calls BASIC ROM helpers.
- `$1C00-$23FF`: low command overlay slot. Current packed low command image is `$02EF` bytes.
- `$2400-$27FF`: fixed call frame, result frame, descriptor buffer, command-name buffer, and page buffer.
- `$A000-$A141`: hidden helper code, restored from `$9A00`.
- `$A800-$A82F`: hidden worker overlay slot used by `HCRC`.
- `$C000-$C075`: bridge state only; the implementation stays below `$C600`.

## REU Banks

- Bank `$44` is ReadyBASIC common/system storage.
- Bank `$45` is packed command code storage.
- ReadyOS REU type constants are mirrored as `REU_RB_CORE = 14` and `REU_RB_CODE = 15`.
- ReadyBASIC marks `$C600+$44` and `$C600+$45` during boot so REU viewer and allocator state know those banks are owned.
- Full registry/code prestash runs only on cold ReadyBasic entry. Warm resume re-marks ownership but does not reread the `REGSEED` load image, because `$4000+` becomes normal BASIC workspace after launch.

## Bank `$44` Regions

- `$0000`: registry header (`RBPL`, version, descriptor count, descriptor size, frame offsets).
- `$0100`: compact command descriptors, 32 bytes each.
- `$0400`: current call-frame snapshot.
- `$0500`: current result-frame snapshot.
- `$0600`: reserved REU debug ring region.
- `$0800`: persistent handle metadata snapshot.
- `$8000-$8FFF`: current V1 16-page persistent data heap for sample buffer handles.

## Bank `$45` Regions

- Offset `$0000`: low overlay pack copied from the linker `LOWPACK` segment.
- Offset `$02EF`: hidden overlay pack copied from the linker `HIDDENPACK` segment.
- Descriptors store code offsets and run offsets; normal low commands copy only their slice. Buffer/heap sample commands currently load the whole low pack because their allocator helpers live in the overlay pack rather than resident core RAM.

## Descriptor ABI

Each descriptor is 32 bytes:

- `0`: command id.
- `1`: flags (`LOW`, `HIDDEN`).
- `2-3`: low code offset in bank `$45`.
- `4-5`: low code size.
- `6-7`: hidden code offset in bank `$45`.
- `8-9`: hidden code size.
- `10-11`: low run offset from `$1C00`.
- `12-13`: hidden run offset from `$A000`.
- `14`: signature id.
- `15`: uppercase command-name length.
- `16-31`: uppercase command-name bytes, padded with zeroes.

## Frames

- Call frame starts at `$2400`.
- Result frame starts at `$2500`.
- V1 supports up to the requested frame size, but implemented sample signatures use direct fixed slots rather than a generalized signature VM.
- Numeric expressions are evaluated through BASIC ROM `FRMNUM` and `GETADR`.
- Variable and array references use BASIC ROM `PTRGET`; output integers are cleared before command execution.
- String output heap mutation happens in visible resident code only.

## Implemented Commands

- `RB PING,OUT%`: low overlay, returns `1`.
- `RB ADD16,A,B,OUT%`: low overlay, returns 16-bit sum.
- `RB STRUP,S$,OUT$`: low overlay, copies and uppercases a string variable or quoted literal.
- `RB HCRC,S$,OUT%`: hidden `$A800` overlay, returns a simple checksum.
- `RB SUMAI,A%(0),COUNT,OUT%`: low overlay, sums integer array elements.
- `RB RANGEAI,START,COUNT,A%(0)`: low overlay, stages integer array output and resident commit writes it.
- `RB BUFNEW,LEN,H%`: low overlay, creates a persistent handle in bank `$44`.
- `RB BUFFILL,H%,BYTE`: low overlay, fills handle pages.
- `RB BUFFREE,H%`: low overlay, frees a handle.
- `RB TEMPSCRATCH,LEN,OUT%`: low overlay, allocates and frees temporary pages, returning page count.
- `RB FAIL,CODE,OUT%`: low overlay, exercises the error path after output clearing.

## Known V1 Boundaries

- No cruncher: stored lines remain raw `RB COMMAND,...`, so regular BASIC `LIST` shows `RB`.
- Raw stored-program `RUN` is supported through the `$0308` IGONE hook; the
  relocated BASIC sentinel byte at `BASIC_START-1` must stay zero.
- Command lookup is linear over fixed descriptors in bank `$44`.
- String input currently supports string variables and quoted literals; fully general BASIC string expressions remain a follow-up.
- V1 integer arrays are explicit base element plus count, e.g. `A%(0),N`.
- The persistent sample heap currently suballocates inside bank `$44`; future large/long-lived data should allocate extra REU banks and record those banks in the same handle table.
