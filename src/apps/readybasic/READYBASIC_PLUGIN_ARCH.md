# ReadyBASIC Lean REU Plugin Architecture

## Current V1 Layout

- `BASIC_START = $2401`; BASIC owns `$2401-$9FFF`, with `31741` formula empty free bytes (31.0K).
- `$1000-$1102`: tiny app entry (`$0103`, 259B) that copies hidden helpers and bridge state before BASIC starts.
- `$1200-$23FD`: visible resident core (`$11FE`, 4606B). This is the only code that calls BASIC ROM helpers.
- `$2400`: BASIC sentinel byte; it must stay zero before stored-program `RUN`.
- `$A900-$AF19`: low command overlay slot under BASIC ROM. Current packed low command image is `$061A` bytes (1.5K, 1562 exact bytes).
- `$C200-$C5FF`: fixed call frame, result frame, descriptor buffer, command-name buffer, page buffer, and warm-resume staging (`$0400`, 1.0K).
- `$A000-$A376`: hidden helper code (`$0377`, 887B), restored from the visible `$C280` shadow.
- `$A800-$A84C`: hidden worker overlay slot (`$004D`, 77B) used by `ZHIDDENRAM`.
- `$C000-$C1F4`: bridge state plus native routine return stack (`$01F5`, 501B); the implementation stays below `$C200`.

## REU Banks

- Bank `$44` is ReadyBASIC common/system storage.
- Bank `$45` is packed command code storage.
- ReadyOS REU type constants are mirrored as `REU_RB_CORE = 14` and `REU_RB_CODE = 15`.
- ReadyBASIC marks `$C600+$44` and `$C600+$45` during boot so REU viewer and allocator state know those banks are owned.
- Full registry/code prestash runs only on cold ReadyBASIC entry. Warm resume
  re-marks ownership but does not reread `CMDPACK`, hidden/bridge load images,
  or `REGSEED`, because those load-image addresses become normal BASIC
  workspace after launch.
- Native `PROC`/`FUNC` definitions are ordinary BASIC program text. They do not
  use descriptors, `LOWPACK`, `HIDDENPACK`, or bank `$45` command-code storage.

## Bank `$44` Regions

- `$0000`: registry header (`RBPL`, version, descriptor count, descriptor size, frame offsets).
- `$0400`: current call-frame snapshot.
- `$0400`: current result-frame snapshot.
- `$0600`: reserved REU debug ring region.
- `$0800-$09FF`: REU-backed handle directory, 128 descriptors at 4 bytes each.
- `$0A00`: ReadyOS suspend/resume zero-page snapshot.
- `$0B00`: ReadyOS suspend/resume stack-page snapshot.
- `$0C00-$0CFF`: 192-page heap bitmap plus reserved bytes.
- `$1000-$1FFF`: 128 compact command descriptor slots, 32 bytes each. Slot 14 is `SCRCAP`, slot 128 is `SCRPUT`, and zero-filled filler slots are unused.
- `$2000-$3FFF`: reserved common/system expansion space.
- `$4000-$FFFF`: typed 48KB heap for buffer and screen handles.

## Bank `$45` Regions

- Offset `$0000`: low overlay pack copied from the linker `LOWPACK` segment.
- Offset `$061A`: hidden overlay pack copied from the linker `HIDDENPACK` segment.
- Descriptors store code offsets and run offsets; normal low commands copy only their slice. Buffer/heap/screen sample commands currently load the whole low pack because their REU descriptor, allocator, bitmap, and screen-copy helpers live in the overlay pack rather than resident core RAM.

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
- Native `EXEC` reuses the same BASIC ROM expression and variable helpers where
  possible: numeric inputs use `FRMNUM`/`GETADR`, output actuals use the existing
  output-variable capture and result commit paths, and string values use the
  existing 64-byte staging cap.

## Implemented Commands

- `ZECHO1(OUT%)` / `ZECHO1()`: low overlay, returns `1`.
- `ZADD16(A,B,OUT%)` / `ZADD16(A,B)`: low overlay, returns 16-bit sum.
- `UPPER(S$,OUT$)` / `UPPER(S$)`: low overlay, copies and uppercases a string variable or quoted literal.
- `LOWER(S$,OUT$)` / `LOWER(S$)`: low overlay, lowercases string byte values; tests verify bytes with `ASC()` because screen display case depends on the C64 charset mode.
- `ZHIDDENRAM(S$,OUT%)` / `ZHIDDENRAM(S$)`: hidden `$A800` overlay, returns a simple checksum.
- `ZSUMNUMARRAY(A%(0),COUNT,OUT%)` / `ZSUMNUMARRAY(A%(0),COUNT)`: low overlay, sums integer array elements.
- `ZRANGENUMARRAY(START,COUNT,A%(0))`: low overlay, stages integer array output and resident commit writes it.
- `BUFNEW(LEN,H%)` / `BUFNEW(LEN)`: low overlay, creates a persistent handle in bank `$44`.
- `BUFFILL(H%,BYTE)`: low overlay, fills buffer handle pages and rejects non-buffer handles.
- `BUFFREE(H%)`: low overlay, frees any valid handle type.
- `ZTEMPSCRATCH(LEN,OUT%)` / `ZTEMPSCRATCH(LEN)`: low overlay, allocates and frees temporary pages, returning page count.
- `ZFAIL(CODE,OUT%)`: low overlay, exercises the error path after output clearing.
- `FREEMEM()`: low overlay, prints the current live BASIC free-byte count and refreshes the header.
- `SCRCAP(H%)` / `SCRCAP()`: low overlay, captures screen text plus color RAM into a typed screen handle.
- `SCRPUT(H%)`: low overlay, validates a typed screen handle and restores screen text plus color RAM. This descriptor lives in slot 128 to prove full-table lookup.

Native reusable BASIC routines:

- `PROC NAME(P%,S$) ... ENDP`: input-only routine, called with `EXEC NAME(...)`.
- `FUNC NAME(P%,S$) ... RET expr ... ENDP`: input formals only; `RET`, `RET%`, or `RET$` supplies the return value.
- `EXEC NAME(...)`: scans stored BASIC text for the matching `PROC`, binds `%`/`$` actuals to formals, pushes a four-entry return stack in bridge state, and resumes at the routine body. `FUNC` is expression-only; `EXEC FUNC(...)` is rejected.
- `CALL` remains reserved for a future non-returning named transfer and is not implemented.

## Known V1 Boundaries

- No private command token: stored lines remain visible `COMMAND(...)` text, so
  regular BASIC `LIST` shows the command text.
- A tiny crunch hook delegates to ROM first, then normalizes tokenized
  `THEN COMMAND(...)` and `THEN EXEC ...` to colon-prefixed statements so
  BASIC's existing statement dispatcher reaches the `$0308` execute hook. String,
  `REM`, and `DATA` text are left alone.
- Raw stored-program `RUN` is supported through the `$0308` execute hook; the
  relocated BASIC sentinel byte at `BASIC_START-1` must stay zero.
- Command lookup is linear over descriptor pages in bank `$44`: one 256-byte page is fetched into `$C500`, eight descriptors are scanned locally, and the matched descriptor is copied into `$C480`.
- String input currently supports string variables and quoted literals; fully general BASIC string expressions remain a follow-up.
- V1 integer arrays are explicit base element plus count, e.g. `A%(0),N`.
- Native routine V1 formals support only `%` and `$`, no arrays, no locals, and
  no plain floating variables. `FUNC` returns through `RET` and has one returned
  value.
- Native routine definitions should be placed after `END`; fall-through into
  `PROC`/`FUNC` is invalid in V1.
- The persistent typed heap currently suballocates 48KB inside bank `$44`; handle type `1` is a byte buffer and type `2` is a screen text+color buffer. Future large/long-lived data can allocate extra REU banks and record those banks in the same REU-backed handle directory.

## Expression-Style Experiment

On the `exp/readybasic-expression-style` branch, ReadyBASIC installs an
additional eval-vector hook at `$030A/$030B`. The hook recognizes a small
allow-list of expression-safe command calls and selected numeric/string `FUNC`
calls.

- Command expressions: `ZECHO1()`, `ZADD16(a,b)`, `ZHIDDENRAM(s$)`,
  `ZSUMNUMARRAY(a%(0),n)`, `BUFNEW(n)`, `ZTEMPSCRATCH(n)`, and `SCRCAP()`
  return integers or handles; `UPPER(s$)` and `LOWER(s$)` return strings.
- Parenthesized routine syntax: `PROC NAME(P%,S$)`, `FUNC NAME(S$)`, and
  `EXEC NAME(actuals...)` for non-empty argument lists.
- Zero-argument routines use `EXEC NAME`; empty parentheses were omitted to keep
  resident code smaller.
- `FUNC` returns use `RET expr`, with optional `RET% expr` and `RET$ expr`
  markers to make the return type explicit. Expression `FUNC` calls scan the
  routine body, execute simple scalar assignments before `RET`, and then
  evaluate the return expression.

Measured branch layout: `BASIC_START=$2401`; BASIC owns `$2401-$9FFF`, for
`31741` formula empty free bytes. `RESIDENT` is `$1200-$23FD` (`4606` bytes),
`BRIDGE` is `$C000-$C1F4` (`501` bytes), and command overlays remain unchanged.
