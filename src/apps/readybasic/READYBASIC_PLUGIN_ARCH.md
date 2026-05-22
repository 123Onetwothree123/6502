# ReadyBASIC Lean REU Plugin Architecture

## Current V1 Layout

- `BASIC_START = $1C01`; BASIC owns `$1C01-$9FFF`, with `33789` empty free bytes (33.0K).
- `$1000-$1102`: tiny app entry (`$0103`, 259B) that copies hidden helpers and bridge state before BASIC starts.
- `$1200-$1BF9`: visible resident core (`$09FA`, 2554B). This is the only code that calls BASIC ROM helpers.
- `$1C00`: BASIC sentinel byte; it must stay zero before stored-program `RUN`.
- `$A900-$ADDF`: low command overlay slot under BASIC ROM. Current packed low command image is `$04E0` bytes (1.2K).
- `$C200-$C5FF`: fixed call frame, result frame, descriptor buffer, command-name buffer, page buffer, and warm-resume staging (`$0400`, 1.0K).
- `$A000-$A336`: hidden helper code (`$0337`, 0.8K), restored from the visible `$C280` shadow.
- `$A800-$A84C`: hidden worker overlay slot (`$004D`, 77B) used by `HCRC`.
- `$C000-$C1C4`: bridge state only (`$01C5`, 453B); the implementation stays below `$C200`.

## REU Banks

- Bank `$44` is ReadyBASIC common/system storage.
- Bank `$45` is packed command code storage.
- ReadyOS REU type constants are mirrored as `REU_RB_CORE = 14` and `REU_RB_CODE = 15`.
- ReadyBASIC marks `$C600+$44` and `$C600+$45` during boot so REU viewer and allocator state know those banks are owned.
- Full registry/code prestash runs only on cold ReadyBASIC entry. Warm resume
  re-marks ownership but does not reread `CMDPACK`, hidden/bridge load images,
  or `REGSEED`, because those load-image addresses become normal BASIC
  workspace after launch.

## Bank `$44` Regions

- `$0000`: registry header (`RBPL`, version, descriptor count, descriptor size, frame offsets).
- `$0400`: current call-frame snapshot.
- `$0500`: current result-frame snapshot.
- `$0600`: reserved REU debug ring region.
- `$0800`: persistent handle metadata snapshot.
- `$0A00`: ReadyOS suspend/resume zero-page snapshot.
- `$0B00`: ReadyOS suspend/resume stack-page snapshot.
- `$1000-$1FFF`: 128 compact command descriptor slots, 32 bytes each. Slot 13 is `SCRCAP`, slot 128 is `SCRPUT`, and zero-filled filler slots are unused.
- `$8000-$8FFF`: current V1 16-page persistent data heap for sample buffer handles.

## Bank `$45` Regions

- Offset `$0000`: low overlay pack copied from the linker `LOWPACK` segment.
- Offset `$04E0`: hidden overlay pack copied from the linker `HIDDENPACK` segment.
- Descriptors store code offsets and run offsets; normal low commands copy only their slice. Buffer/heap/screen sample commands currently load the whole low pack because their allocator and screen-copy helpers live in the overlay pack rather than resident core RAM.

## Descriptor ABI

Each descriptor is 32 bytes:

- `0`: command id.
- `1`: flags (`LOW`, `HIDDEN`).
- `2-3`: low code offset in bank `$45`.
- `4-5`: low code size.
- `6-7`: hidden code offset in bank `$45`.
- `8-9`: hidden code size.
- `10-11`: low run offset from `$A900`.
- `12-13`: hidden run offset from `$A000`.
- `14`: signature id.
- `15`: uppercase command-name length.
- `16-31`: uppercase command-name bytes, padded with zeroes.

## Frames

- Call frame starts at `$C200`.
- Result frame starts at `$C300`.
- Descriptor buffer starts at `$C480`.
- Command buffer starts at `$C4A0`.
- Page buffer starts at `$C500`.
- V1 supports up to the requested frame size, but implemented sample signatures use direct fixed slots rather than a generalized signature VM.
- Numeric expressions are evaluated through BASIC ROM `FRMNUM` and `GETADR`.
- Variable and array references use BASIC ROM `PTRGET`; output integers are cleared before command execution.
- String output heap mutation happens in visible resident code only.

## Implemented Commands

- `!PING OUT%`: low overlay, returns `1`.
- `!ADD16 A,B,OUT%`: low overlay, returns 16-bit sum.
- `!STRUP S$,OUT$`: low overlay, copies and uppercases a string variable or quoted literal.
- `!HCRC S$,OUT%`: hidden `$A800` overlay, returns a simple checksum.
- `!SUMAI A%(0),COUNT,OUT%`: low overlay, sums integer array elements.
- `!RANGEAI START,COUNT,A%(0)`: low overlay, stages integer array output and resident commit writes it.
- `!BUFNEW LEN,H%`: low overlay, creates a persistent handle in bank `$44`.
- `!BUFFILL H%,BYTE`: low overlay, fills buffer handle pages and rejects non-buffer handles.
- `!BUFFREE H%`: low overlay, frees any valid handle type.
- `!TEMPSCRATCH LEN,OUT%`: low overlay, allocates and frees temporary pages, returning page count.
- `!FAIL CODE,OUT%`: low overlay, exercises the error path after output clearing.
- `!FREEMEM`: low overlay, prints the current live BASIC free-byte count and refreshes the header.
- `!SCRCAP H%`: low overlay, captures screen text plus color RAM into a typed screen handle.
- `!SCRPUT H%`: low overlay, validates a typed screen handle and restores screen text plus color RAM. This descriptor lives in slot 128 to prove full-table lookup.

## Known V1 Boundaries

- No private command token: stored lines remain visible `!COMMAND args`, so
  regular BASIC `LIST` shows the `!` command text.
- A tiny crunch hook delegates to ROM first, then normalizes tokenized
  `THEN !COMMAND` to `THEN :!COMMAND` so BASIC's existing statement dispatcher
  reaches the `$0308` execute hook. String, `REM`, and `DATA` text are left alone.
- Raw stored-program `RUN` is supported through the `$0308` execute hook; the
  relocated BASIC sentinel byte at `BASIC_START-1` must stay zero.
- Command lookup is linear over descriptor pages in bank `$44`: one 256-byte page is fetched into `$C500`, eight descriptors are scanned locally, and the matched descriptor is copied into `$C480`.
- String input currently supports string variables and quoted literals; fully general BASIC string expressions remain a follow-up.
- V1 integer arrays are explicit base element plus count, e.g. `A%(0),N`.
- The persistent sample heap currently suballocates inside bank `$44`; handle type `1` is a byte buffer and type `2` is a screen text+color buffer. Future large/long-lived data should allocate extra REU banks and record those banks in the same handle table.
