# ReadyBASIC Current Design

This is the current ReadyBASIC design as implemented by
`src/apps/readybasic/readybasic.s`, linked by `cfg/ready_app_readybasic.cfg`,
and verified against the current `obj/readybasic.map`.

ReadyBASIC is a ReadyOS app that hosts a relocated C64 BASIC V2 workspace and
adds a lean command spine for bare `COMMAND(...)` statements and selected
`COMMAND(...)` expressions, plus native bare `PROC`/`FUNC` reusable BASIC
routines. It is not a private BASIC token system. Stored program lines remain
readable, `LIST` shows visible `PROC`, `FUNC`, `EXEC`, `ENDP`, and command text,
and the execute/eval hooks recognize extensions when BASIC dispatches a
statement or expression.

## Current Syntax And Statement Behavior

ReadyBASIC commands now prefer ordinary-looking parenthesized BASIC syntax:

```basic
COMMAND(arg,arg,out%)
PRINT COMMAND(arg,arg)
```

Statement commands keep the existing output-variable convention. Expression
commands return the scalar or string result directly. The older `!COMMAND args`
statement path was removed on the expression-style branch; current examples and
tests use bare `COMMAND(...)`.

Bare commands are recognized only where BASIC is about to dispatch a statement
or evaluate an expression:

| Context | Supported | Notes |
|---|---:|---|
| Immediate mode statement | Yes | Example: `ZECHO1(P%)`. |
| Stored program line start | Yes | Raw command text survives `LIST` and runs through `$0308`. |
| After `:` | Yes | Example: `PRINT "A":ZECHO1(P%)`. |
| Inside `FOR/NEXT` body | Yes | Use it as a statement in the loop body. |
| After `IF ... THEN` | Yes | The crunch hook rewrites `THEN COMMAND(...)` to `THEN :COMMAND(...)` for known command names. |
| Inside `PRINT`, assignments, or larger expressions | Selected commands only | `ZADD16(2,3)+7`, `UPPER(S$)`, and numeric/string `FUNC` expression returns are supported. |
| Inside strings, `REM`, or `DATA` | Ordinary text | These are not rewritten or dispatched. |
| After `ELSE` | No native support | BASIC V2 has no `ELSE`; ReadyBASIC does not add it. |

`IF 1 THEN ZECHO1(P%)` works when typed interactively, but the stored/listed form
becomes `IF 1 THEN :ZECHO1(P%)`. That is an intentional size-saving
normalization. It lets BASIC's existing statement dispatcher reach the normal
ReadyBASIC execute hook without adding a larger custom IF parser.

Native routines use ordinary BASIC program text:

```basic
1000 PROC SHOW(P%,M$)
1010 PRINT P%;M$
1020 ENDP

1100 FUNC ADDI(X%,Y%)
1110 RET X%+Y%
1120 ENDP

10 EXEC SHOW(3,"READY")
20 A%=ADDI(4,5)
30 PRINT ADDI(6,7)
```

`EXEC` calls a `PROC`. `PROC` has input formals only. `FUNC` also declares input
formals only, but is called as a BASIC expression and returns with a `RET`
statement. `EXEC FUNC(...)` is rejected; write `A%=ADDI(4,5)` or
`PRINT ADDI(6,7)` instead. `ENDP` returns from `PROC` without a value.
Version 1 supports scalar `%` integer and `$` string formals only, no arrays,
plain floating variables, locals, by-reference parameters, or multiple outputs.
String inputs and returns use the same 64-byte ReadyBASIC string cap as command
results. Nested `EXEC` has a four-entry return stack; a fifth active call reports
`?RB ERROR 33`.

`RET expr` returns from a `FUNC`. `RET% expr` and `RET$ expr` are accepted when
the return type should be explicit; otherwise ReadyBASIC infers string returns
from a quoted literal or `$` variable and uses integer return handling for the
other supported V1 cases. A `FUNC` expression scans and runs simple scalar
assignment statements before `RET`, so later assignment then return works:

```basic
2000 FUNC ADDLATE(X%,Y%)
2010 R%=X%+Y%
2020 RET R%
2030 ENDP

10 A%=ADDLATE(4,5)
```

This is still intentionally smaller than a general BASIC subinterpreter: V1
`FUNC` bodies support scalar `%`/`$` assignments before `RET`, including nested
numeric `FUNC` calls and string command returns in the tested simple assignment
forms. Other statements inside a `FUNC` body remain invalid, and command/FUNC
returns are not currently general-purpose arguments to BASIC ROM functions such
as `ABS(...)` or `LEFT$(...)`.

Routine definitions are normal BASIC lines and are not command overlays,
descriptors, or `LOWPACK` entries. Put definitions after `END` in V1. Reaching a
`PROC` or `FUNC` definition by ordinary fall-through is invalid and produces a
BASIC syntax error; this keeps the resident implementation small. Like C64 BASIC
variables generally, formal variables are global by name. Avoid reusing a
function's input formal name as an important caller variable unless you intend
the call to overwrite that global BASIC variable.

`IF 1 THEN A%=ADDI(1,2)` works through BASIC's normal assignment path. `IF 1
THEN EXEC SHOW(7)` works when typed into ReadyBASIC and is normalized by
the crunch hook to `IF 1 THEN :EXEC SHOW(7)`. `petcat`-built stored examples
should use the already-normalized `THEN :EXEC` form because they bypass the
interactive crunch hook.

ReadyBASIC also recognizes manual prompt `EXIT` as the ReadyOS yield command.
Program-line `EXIT` resume remains future work; the proven V1 path is direct
prompt `EXIT`.

## Command Families

The current commands are examples of command shapes that the spine needs to
support, not the final product command catalog.

| Category | Commands | Purpose |
|---|---|---|
| Scalar Outputs | `ZECHO1`, `ZADD16` | Prove integer output variables, numeric expression parsing, and scalar result commit. |
| String Transfer/Transform | `UPPER`, `LOWER` | Prove string input capture and resident-owned BASIC string output allocation. |
| Hidden Banked Worker | `ZHIDDENRAM` | Prove worker code can run under BASIC ROM RAM in the `$A800` hidden overlay slot. |
| Integer Array Transfer | `ZSUMNUMARRAY`, `ZRANGENUMARRAY` | Prove array input/output via explicit base element plus count. |
| Persistent REU Handles | `BUFNEW`, `BUFFILL`, `BUFFREE`, `SCRCAP`, `SCRPUT` | Prove stable BASIC-visible handles for persistent REU-backed data, including typed screen text+color resources. |
| Temporary REU Workspace | `ZTEMPSCRATCH` | Prove temporary page allocation and cleanup. |
| Error/Failure Contract | `ZFAIL` | Prove outputs are cleared before execution and stale results are not committed. |
| Runtime Introspection | `FREEMEM` | Prints live BASIC free memory and refreshes the header value without returning an output variable. |
| ReadyOS Yield | `EXIT` | Save BASIC runtime state, restore vectors, and return through the ReadyOS shim. |

### Command Inventory

| Command | Code placement | Parameters | Result behavior |
|---|---|---|---|
| `ZECHO1(OUT%)` / `ZECHO1()` | Low overlay at `$A900+$0000`, copy `$0015` | output integer, or expression integer | Returns `1`. |
| `ZADD16(A,B,OUT%)` / `ZADD16(A,B)` | Low overlay at `$A900+$0015`, copy `$001E` | two numeric expressions, output integer or expression integer | Returns 16-bit sum. |
| `UPPER(S$,OUT$)` / `UPPER(S$)` | Low overlay at `$A900+$0033`, copy `$003B` | string variable or quoted literal, output string or expression string | Uppercases staged bytes. |
| `LOWER(S$,OUT$)` / `LOWER(S$)` | Low overlay at `$A900+$006E`, copy `$003B` | string variable or quoted literal, output string or expression string | Lowercases staged byte values. On the default C64 screen this is verified by `ASC()` values, because display case is charset-dependent. |
| `ZHIDDENRAM(S$,OUT%)` / `ZHIDDENRAM(S$)` | Hidden overlay at `$A800`, copy `$004D` (77B) | string variable or quoted literal, output integer or expression integer | Returns a simple uppercase-byte checksum. |
| `ZSUMNUMARRAY(A%(0),COUNT,OUT%)` / `ZSUMNUMARRAY(A%(0),COUNT)` | Low overlay at `$A900+$00A9`, copy `$0044` | integer array base, count, output integer or expression integer | Sums integer array elements. |
| `ZRANGENUMARRAY(START,COUNT,A%(0))` | Low overlay at `$A900+$00ED`, copy `$003D` | start value, count, output array base | Stages consecutive integers, then resident code writes them to the array. |
| `BUFNEW(LEN,H%)` / `BUFNEW(LEN)` | Low overlay entry `$012A`, copy full `$061A` (1.5K) low pack | byte length, output handle or expression handle | Allocates buffer pages in REU bank `$44` and returns a one-based handle. |
| `BUFFILL(H%,BYTE)` | Low overlay entry `$012E`, copy full `$061A` (1.5K) low pack | buffer handle, fill byte | Fills buffer handles through the `$C500` page buffer and rejects non-buffer handles. |
| `BUFFREE(H%)` | Low overlay entry `$0132`, copy full `$061A` (1.5K) low pack | handle | Frees any valid handle type and clears metadata/page bitmap state. |
| `ZTEMPSCRATCH(LEN,OUT%)` / `ZTEMPSCRATCH(LEN)` | Low overlay entry `$0136`, copy full `$061A` (1.5K) low pack | byte length, output integer or expression integer | Allocates and frees temporary pages, returning page count. |
| `ZFAIL(CODE,OUT%)` | Low overlay at `$A900+$013A`, copy `$001B` | error code, output integer | Clears output first, then reports `?RB ERROR code`. |
| `FREEMEM()` | Low overlay at `$A900+$0155`, copy `$0016` | none | Prints current live BASIC free bytes and refreshes the header. |
| `SCRCAP(H%)` / `SCRCAP()` | Slot 14 descriptor; low overlay entry `$016B`, copy full `$061A` (1.5K) low pack | output handle or expression handle | Captures screen text `$0400-$07E7` and color RAM `$D800-$DBE7` into a typed screen handle. |
| `SCRPUT(H%)` | Slot 128 descriptor; low overlay entry `$0194`, copy full `$061A` (1.5K) low pack | screen handle | Validates the screen handle type and restores text plus color RAM. |

The handle-oriented commands copy the full low pack because their wrappers share
allocator helper routines that currently live in the packed low overlay. That
keeps the resident core lean at the cost of copying more overlay bytes for these
sample commands.

`SCRCAP`/`SCRPUT` were named to avoid C64 BASIC tokenizer conflicts with
embedded `SAVE`/`LOAD` tokens. They are the implemented forms of the original
screen save/load concept.

Historical proof names such as `PING`, `ADD16`, `STRUP`, `HCRC`, `SUMAI`,
`RANGEAI`, `TEMPSCRATCH`, and `FAIL` are no longer runtime command aliases.
Their current demo/proof forms use the `Z...` namespace, and array demo names
use `NUM` rather than `INT` to avoid the BASIC `INT` token.

## Command Overlay Loading And Files Involved

There is one ReadyBASIC app executable: `bin/readybasic.prg`. There is not one
PRG or executable file per command. The command overlays are linker segments
inside that one PRG load image:

| File or artifact | Role |
|---|---|
| `src/apps/readybasic/readybasic.s` | All current ReadyBASIC code, command descriptors, low overlay code, hidden overlay code, and hidden helpers. |
| `cfg/ready_app_readybasic.cfg` | Defines the load/run split: resident code, `CMDPACK`, `REGSEED`, hidden helper load image, bridge load image, and runtime overlay slots. |
| `Makefile` | Assembles `readybasic.s`, links it with `ready_app_readybasic.cfg`, and writes `bin/readybasic.prg` plus `obj/readybasic.map`. |
| `obj/readybasic.map` | Current source of truth for segment ranges and sizes. |
| `bin/readybasic.prg` | The single ReadyOS app executable that contains resident code plus cold-load seed images. |
| `src/apps/readybasic/rbtest1.bas` / `obj/rbtest1.prg` | Legacy sample BASIC program only; not part of the command overlay mechanism. |
| `src/apps/readybasic/rbproc1.bas` / `obj/rbproc1.prg` | Positive `PROC`/`FUNC` sample: no-param PROC, `%`, `$`, `%` return, `$` return, explicit `RET%`/`RET$`, colon chain, normalized `IF THEN :EXEC`, nested depth 2, command and FUNC return assignments, command return inside top-level `ABS(...)`, flat numeric expression actuals, and string command return inside a `FUNC` body. |
| `src/apps/readybasic/rbprocerr.bas` / `obj/rbprocerr.prg` | Negative `PROC`/`FUNC` sample; run sections by line number to exercise unknown routine, wrong count/type, statement `EXEC` to `FUNC`, PROC extra actual, bare `ENDP`, and return-stack overflow. |
| `build_support/verify_readybasic_plugin.py` | Static guardrail checker for the ReadyBASIC layout and REU constants. |
| `READYBASIC_MAKING_COMMAND_GUIDE.md` / `readybasic_making_command_guide.html` | Walkthrough for adding commands using the current demo, string, array, hidden, and REU-handle examples. |

The linker puts packed command bytes in the PRG load image at `CMDPACK`
`$2800-$2FFF`, but their runtime addresses are different:

| Segment | Size | Load/source role | Runtime role |
|---|---:|---|---|
| `LOWPACK` | `$061A` (1.5K, 1562 exact bytes) | Packed low command bytes loaded from `CMDPACK` and prestashed to REU bank `$45` offset `$0000`. | Fetched on demand into the banked low overlay slot at `$A900+`, under BASIC ROM. |
| `HIDDENPACK` | `$004D` (77B) | Packed hidden worker bytes loaded after `LOWPACK` in `CMDPACK` and prestashed to REU bank `$45` offset `$061A`. | Fetched on demand into hidden RAM at `$A800-$A84C`. |
| `HIDLOAD` | `$0377` (0.9K, 887 exact bytes) | Load-only hidden helper seed starting at `$4000`. | Copied on cold boot into `$A000-$A376` and the visible `$C280-$C5F6` warm-resume shadow. |
| `BRLOAD` | `$01F5` (501B) | Load-only bridge seed starting at `$4800`. | Copied on cold boot into `$C000-$C1F4`. |
| `REGSEED` | `$1010` (4.0K, 4112 exact bytes) | Load-only registry header and 128 command descriptors at `$5000-$600F`. | Copied on cold boot into REU bank `$44` offsets `$0000` and `$1000`. |

Cold boot is the only time the load-image command pack and `REGSEED` are trusted.
The hidden helper copies the registry/header to REU bank `$44` and copies
`LOWPACK` plus `HIDDENPACK` to REU bank `$45`. After that, BASIC may own the
former load-image addresses, so warm resume reuses the REU copies and does not
reseed from `$2800+`, `$4000+`, `$4800+`, or `$5000+`.

At command execution time, the descriptor tells the resident loader which bytes
to fetch:

1. Low commands use descriptor offsets `2-5` for code offset/size and `10-11`
   for entry offset. ReadyBASIC maps RAM under BASIC ROM, fetches from bank
   `$45` into `$A900 + offset`, and jumps through the computed low overlay
   entry.
2. Hidden commands use descriptor offsets `6-9` for code offset/size and
   `12-13` for entry offset. ReadyBASIC maps RAM under BASIC ROM, fetches into
   `$A000 + entry offset`, and calls the hidden overlay entry.
3. Commands can fetch a small slice or the whole low pack. The current handle
   and screen-handle commands fetch the whole `$061A` low pack because their
   shared allocator and screen-copy helpers live there.

## C64 RAM Layout

ReadyBASIC runs inside the ReadyOS app working region `$1000-$C5FF`. ReadyOS
metadata and shim space above that are not general ReadyBASIC scratch.

| Region | Current range | Size | Owner and role |
|---|---:|---:|---|
| `ENTRY` | `$1000-$1102` | `$0103` (259B) | Tiny entry, cold/warm discriminator, early hidden/bridge copies. |
| `RESIDENT` | `$1200-$23FD` | `$11FE` (4.5K, 4606 exact bytes) | Visible parser, vector hooks, BASIC ROM calls, REU DMA wrappers, result commit, bare command dispatch, expression hook, native `PROC`/`FUNC`/`RET` dispatch. |
| BASIC sentinel | `$2400` | 1 byte | Must stay zero before stored-program `RUN`. |
| BASIC workspace | `$2401-$9FFF` | `$7BFF` region, `31741` formula free bytes (31.0K) | Program text, variables, arrays, string heap. |
| Command pack load image | `$2800-$3FFF` | `$1800` (6.0K) file range | Low and hidden overlay seed bytes before cold prestash. |
| Hidden helper load image | `$4000+` | `$0377` (0.9K, 887 exact bytes) load-only | Hidden helper seed copied to `$A000` and `$C280`. |
| Bridge load image | `$4800+` | `$01F5` (501B) load-only | Bridge seed copied to `$C000`. |
| Registry seed load image | `$5000-$600F` | `$1010` (4.0K, 4112 exact bytes) load-only | Header and 128 descriptors copied to REU bank `$44`. |
| Runtime snapshot | REU bank `$44`, offsets `$0A00-$0BFF` | `$0200` (0.5K) plus bridge metadata | Saved zero page, stack page, SP, resume mode, line-chain guards. |
| `HIDDEN` | `$A000-$A376` | `$0377` (0.9K) | Helper code run with RAM mapped under BASIC ROM. |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` (77B) | Hidden worker overlay image. |
| `LOWPACK` runtime | `$A900-$AF19` | `$061A` (1.5K) | Banked low command pack fetched from REU bank `$45`. |
| `BRIDGE` | `$C000-$C1F4` | `$01F5` (501B) | Persistent bridge state, saved vectors, overlay variables, current handle scratch, debug bytes, native routine return stack. |
| Shared frames | `$C200-$C5FF` | `$0400` (1.0K) | Call frame, result frame, descriptor buffer, command-name buffer, page/runtime buffers. |
| Hidden shadow | `$C280-$C5F6` | `$0377` (0.9K) | Visible-RAM source for restoring `$A000` helper on warm resume; refreshed during `EXIT`. |
| ReadyOS REU metadata | `$C600-$C7FF` | `$0200` (0.5K) shared | ReadyBASIC only marks REU bank ownership here. |
| ReadyOS shim ABI | `$C800-$C9FF` | `$0200` (0.5K) shared | ReadyOS jump table and data; not ReadyBASIC RAM. |

The PRG load image is larger than the live resident core. On cold entry,
ReadyBASIC copies the hidden helper seed from the load image to `$A000` and
the visible shadow at `$C280`, copies the bridge seed to `$C000`, and prestashes
registry/code seed data into REU. After that, BASIC owns `$2401-$9FFF`. Warm resume must therefore
not reread load-only seed tables at `$4000+`, because that address range may now
be BASIC program or variable storage.

### Stage-Specific Memory Use

Some map entries intentionally overlap the eventual BASIC workspace. That is
not a contradiction; it is a time-of-use distinction.

| Stage | C64 RAM ownership | BASIC-visible effect |
|---|---|---|
| PRG load / cold seed | `CMDPACK` is loaded at `$2800-$3FFF`, `HIDLOAD` at `$4000+`, `BRLOAD` at `$4800+`, and `REGSEED` at `$5000-$600F`. These ranges are inside the future BASIC workspace but BASIC is not live there yet. | No user BASIC program or variables exist yet, so the load image can safely occupy this space temporarily. |
| End of cold seed | `LOWPACK`/`HIDDENPACK` have been copied from `CMDPACK` to REU bank `$45`; the registry has been copied to REU bank `$44`; hidden and bridge live copies are in their runtime homes. | `$2401-$9FFF` becomes the BASIC workspace. The former load-image bytes are now disposable. |
| Ready prompt / running BASIC | BASIC owns `$2401-$9FFF`, including the old `$2800-$600F` load ranges. Command code is fetched from REU into `$A800/$A900` under BASIC ROM only while a command runs. | Empty BASIC free space is `31741` formula bytes. Warm resume never trusts the old load-image addresses. |
| Future command growth | The current `CMDPACK` reservation is `$1800` (6.0K). Today it carries `LOWPACK` `$061A` plus `HIDDENPACK` `$004D`, about 1.6K of actual packed command code. | The remaining reserved `CMDPACK` capacity can absorb more packed command code without reducing steady-state BASIC free bytes. Growing beyond the reserved load-only area may increase PRG size or require another cold-only seed range, but it should still be reclaimed before BASIC owns the workspace. |

The visual way to read this: `CMDPACK` looks like it overlaps BASIC RAM in the
link/load map because it really does during cold loading. It does not reduce the
steady-state BASIC workspace because its live copy is in REU before the user can
store a BASIC program.

`CMDPACK` is only the current C64 cold-load seed window. It is not the total
command-code capacity of the architecture. The current descriptor format points
into REU bank `$45` with 16-bit offsets and sizes, so the current single code
bank can hold up to `$10000` bytes (64.0K) of packed command bodies. The build
currently uses `$0667` (1.6K, 1639 exact bytes), leaving `$F999` (62.4K, 63897
exact bytes) available in bank `$45`. To actually seed beyond the current 6.0K
`CMDPACK` linker window, the cold-load layout would need a larger or additional
load-only seed range, copied to REU before BASIC owns `$2401-$9FFF`. Going
beyond one 64K code bank would require a descriptor/loader extension for
additional command-code banks.

## BASIC Free RAM Compared With Stock C64 BASIC

Stock C64 BASIC V2 starts at `$0801` and normally has memory top at `$A000`,
which gives about `38911` bytes free on an empty machine.

ReadyBASIC relocates BASIC to `$2401` and uses `$A000` as the BASIC memory top.
On an empty ReadyBASIC workspace, variables begin at `$2403`, so the practical
empty BASIC free space is:

```text
$A000 - $2403 = 31741 bytes (31.0K)
```

That is `7170` bytes (7.0K) less than stock C64 BASIC, or about `81.6%` of the
stock empty BASIC free space. The extra `$0300` loss from the native
`PROC`/`FUNC` `$2101` layout pays for the bare-command and eval-vector expression
syntax while keeping the resident segment below `$2400`.

| Environment | BASIC text start | BASIC top | Empty free bytes |
|---|---:|---:|---:|
| Stock C64 BASIC V2 | `$0801` | `$A000` | `38911` (38.0K) |
| ReadyBASIC current layout | `$2401` | `$A000` | `31741` (31.0K) |
| Difference | - | - | `-7170` (-7.0K) |

Strategies to maximize BASIC RAM while adding many more commands:

- Keep the resident core below `$2400`; every resident byte is permanent C64 RAM
  pressure.
- Put command implementation code in packed REU code banks and copy it into the
  existing overlay slots only when invoked.
- Reuse existing signatures and commit paths where possible. A new command with
  an existing parameter/result shape should not need new resident parser code.
- Keep descriptors in the REU registry, not in resident RAM.
- Move command-private persistent data to dynamic REU banks and expose small
  BASIC integer handles instead of storing large data in BASIC RAM.
- Split or group overlay helper routines only when it reduces total copied bytes
  without bloating resident RAM.
- If the current `$45` code bank becomes crowded, extend the registry model to
  support additional packed code banks rather than lowering BASIC's top or
  adding permanent C64-resident command code.
- Consider a compact REU-backed signature/parameter table if many future
  commands would otherwise require one resident parser branch each.

Current per-command overhead:

| New command kind | Permanent C64 RAM overhead | REU/load-image overhead |
|---|---:|---|
| New command reusing an existing signature and overlay slot | Usually `0` bytes of BASIC workspace and `0` bytes of resident RAM. | One 32-byte descriptor in bank `$44`, command code bytes in bank `$45`, and matching load-image bytes in `LOWPACK` or `HIDDENPACK`. |
| New command needing a new parameter/result signature | No BASIC workspace cost, but resident parser/commit code grows by the new shared support. | One 32-byte descriptor plus command code bytes. |
| New command needing persistent data | No BASIC workspace cost if represented as a handle. | Descriptor/code bytes plus REU data-bank allocation and handle metadata. |
| New command needing a larger fixed C64 buffer | Permanent C64 RAM cost only if it expands `$C200-$C5FF`, the overlay slots, resident RAM, or bridge state. | Depends on whether the data can be moved to REU instead. |

## Page-3 Vector Ownership

ReadyBASIC saves the original BASIC vectors, then installs:

| Vector | Address | ReadyBASIC role |
|---|---:|---|
| Crunch | `$0304/$0305` | Calls ROM crunch first, then normalizes tokenized `THEN COMMAND(...)` and `THEN EXEC ...` into a colon-prefixed statement. |
| Execute | `$0308/$0309` | Peeks for `EXIT`, `PROC`, `FUNC`, `EXEC`, `ENDP`, or a bare descriptor command; otherwise tail-calls the original execute vector without advancing `TXTPTR`. |
| Eval | `$030A/$030B` | Recognizes selected `COMMAND(...)` and `FUNC(...)` expression returns, then falls back to ROM expression evaluation. |
| List | `$0306/$0307` | Saved/restored, but V1 leaves normal ROM listing behavior. |

Page-3 vectors are global machine state. `EXIT` restores the original vectors
before jumping back through the ReadyOS shim so the launcher or another app
cannot accidentally dispatch through stale ReadyBASIC code.

## Command Dispatch Pipeline

1. BASIC dispatches a statement through the execute vector.
2. ReadyBASIC peeks at the next non-space byte without mutating `TXTPTR`.
3. If the statement is neither `EXIT`, a native routine keyword, nor a known
   bare descriptor command followed by `(`, ReadyBASIC tail-calls the
   saved ROM execute vector.
4. For a bare command, ReadyBASIC parses and normalizes the command name into
   `$C4A0`, requires `(`, and reuses the descriptor lookup and signature parser.
5. Command lookup linearly scans up to 128 fixed 32-byte descriptors in REU
   bank `$44` at `$1000-$1FFF`. It fetches one 256-byte page into `$C500`,
   scans eight descriptors locally, and copies a match into `$C480`. Zero-filled
   filler descriptors are empty command slots.
6. The resident parser dispatches by signature id and uses BASIC ROM helpers to
   parse parameters and capture output references.
7. Output variables are cleared before command execution.
8. The call frame at `$C200` is mirrored to REU bank `$44` offset `$0400`.
9. Command code is fetched from REU bank `$45` into the low overlay slot
   `$A900` or hidden overlay slot `$A800`.
10. The worker writes a compact result frame at `$C300`.
11. The result frame is mirrored to REU bank `$44` offset `$0400`.
12. Resident code checks status, prints `?RB ERROR n` on failure, or commits
    integer, string, or array results to the captured BASIC output reference.

The command-name parser accepts normal letters/digits, folds lowercase ASCII to
uppercase, maps shifted uppercase/PETSCII-like `$C1-$DA` bytes back to `A-Z`,
and handles a small number of tokenization edge cases that can appear inside
names.

## Frames And ABI Surfaces

| Surface | Address or offset | Role |
|---|---:|---|
| Call frame | `$C200` | Command id, parameter count, numeric slots, pointer/count slots, string input buffer. |
| Result frame | `$C300` | Status, error number, value tag, scalar value, string output buffer, array output buffer. |
| Descriptor buffer | `$C480` | One descriptor fetched from REU bank `$44`. |
| Command buffer | `$C4A0` | Uppercase normalized command name. |
| Page buffer | `$C500` | 256-byte staging page for descriptor scans, REU handle operations, heap bitmap scans, and warm-resume stack buffer. |
| REU call snapshot | Bank `$44`, `$0400` | Copy of the current call frame. |
| REU result snapshot | Bank `$44`, `$0400` | Copy of the current result frame. |
| Runtime zero-page snapshot | Bank `$44`, `$0A00` | Saved zero page, restored through the temporary buffer at `$C400`. |
| Runtime stack snapshot | Bank `$44`, `$0B00` | Saved stack page, restored through the temporary buffer at `$C500`. |

The descriptor ABI is fixed-size and compact:

| Descriptor offset | Field |
|---:|---|
| `0` | Command id. |
| `1` | Flags: low overlay, hidden overlay, or both. |
| `2-3` | Low code offset in REU bank `$45`. |
| `4-5` | Low code size. |
| `6-7` | Hidden code offset in REU bank `$45`. |
| `8-9` | Hidden code size. |
| `10-11` | Low entry offset from `$A900`. |
| `12-13` | Hidden entry offset from `$A000`. |
| `14` | Signature id. |
| `15` | Uppercase command-name length. |
| `16-31` | Uppercase command-name bytes, zero padded. |

Supported result tags are:

| Tag | Meaning |
|---:|---|
| `0` | No result. |
| `1` | Integer result. |
| `2` | String result. |
| `3` | Integer array result. |

String output is committed only by visible resident code. Workers stage string
bytes in the result frame; resident code allocates BASIC string heap space by
lowering `FRETOP` and updates the output string descriptor. Hidden and low
workers do not directly mutate the BASIC string heap.

## REU Layout

ReadyBASIC reserves two fixed REU banks:

| Bank | ReadyOS type | Purpose |
|---:|---:|---|
| `$44` | `14` | ReadyBASIC core/system storage. |
| `$45` | `15` | Packed ReadyBASIC command-code storage. |

ReadyBASIC marks the ReadyOS REU allocation table at `$C600+$44` and
`$C600+$45`. It does not use `$C600-$C7FF` as private scratch.

### Bank `$44`: Core/System Storage

| Offset | Region |
|---:|---|
| `$0000` | Header: `RBPL`, version, descriptor count, descriptor size, and frame offsets. |
| `$0400` | Current call-frame snapshot. |
| `$0400` | Current result-frame snapshot. |
| `$0600` | Reserved debug ring area. |
| `$0800-$09FF` | REU-backed handle directory: 128 descriptors, 4 bytes each. |
| `$0A00` | Saved zero page for ReadyOS suspend/resume. |
| `$0B00` | Saved stack page for ReadyOS suspend/resume. |
| `$0C00-$0CFF` | 192-byte heap page bitmap plus reserved bytes. |
| `$1000-$1FFF` | 128 command descriptor slots, 32 bytes each. Slot 14 is `SCRCAP`; slot 128 is `SCRPUT`; zero-filled slots are unused fillers. |
| `$2000-$3FFF` | Reserved common/system space for future ReadyBASIC metadata. |
| `$4000-$FFFF` | Typed handle heap: 192 pages / 48KB. |

The descriptor table intentionally leaves a large filler span between the two
screen commands:

| Descriptor range | REU offset | Role | Slots | Size |
|---|---:|---|---:|---:|
| Slots 1-14 | `$1000-$11BF` | Current front commands from `ZECHO1` through `SCRCAP`. | 14 | `$01C0` / 448B |
| Slots 15-127 | `$11C0-$1FDF` | Zero-filled filler descriptors available for future commands. | 113 | `$0E20` / 3.5K / 3616 exact bytes |
| Slot 128 | `$1FE0-$1FFF` | `SCRPUT`, deliberately placed at the end to prove full-table lookup. | 1 | `$0020` / 32B |

The persistent handle model supports 128 live handles. Each handle is
represented to BASIC as a small integer from `1` to `128`, while canonical
metadata lives in REU and bridge RAM keeps only the current descriptor scratch.
Type `1` is a byte buffer, and type `2` is a screen text+color buffer.
`BUFFILL` accepts only buffer handles; `BUFFREE` frees any valid handle;
`SCRPUT` accepts only screen handles. The typed heap uses bank `$44` pages
`$40-$FF`; future large or long-lived objects should allocate additional REU
banks and keep the same small handle model.

### Bank `$45`: Packed Command Code

| Offset | Region |
|---:|---|
| `$0000-$0619` | Low overlay pack copied into `$A900-$AF19`. |
| `$061A-$0666` | Hidden overlay pack copied into `$A800-$A84C`. |

Descriptors point into these packed bytes. Normal low commands fetch only their
slice. The REU handle and screen-handle commands currently fetch the whole low
pack because shared allocator and screen-copy helpers live there.

## Cold Boot Lifecycle

1. ReadyOS loads `readybasic.prg` at `$1000`.
2. Entry code checks its local warm/cold magic.
3. On cold path, it maps RAM under BASIC ROM long enough to copy the hidden
   helper seed to `$A000`, then copies a visible helper shadow to `$C280`.
4. It copies bridge seed bytes from the load image to `$C000`.
5. The resident core resets KERNAL/BASIC vectors, saves originals, and installs
   ReadyBASIC crunch/execute/eval hooks.
6. BASIC is relocated to `TXTTAB=$2401` with top at `$A000`.
7. `$2400`, `$2401`, and `$2402` are cleared. `$2400` is the sentinel byte
   required by BASIC `RUN`.
8. REU bank `$44` receives the header and descriptors from `REGSEED`.
9. REU bank `$45` receives the packed low and hidden command code.
10. ReadyBASIC clears/redraws the screen, prints its banner, and enters
    `BASIC_READY`.

## EXIT, Suspend, And Warm Resume

Manual prompt `EXIT` is the supported V1 ReadyOS return path.

On `EXIT`, ReadyBASIC:

1. Identifies direct-prompt return by checking that `TXTPTR` is below
   `BASIC_START`.
2. Stores bridge and entry magic for READY-mode resume.
3. Calls hidden save-state code.
4. Saves zero page `$0000-$00FF` to REU bank `$44` offset `$0A00`.
5. Saves stack page `$0100-$01FF` to REU bank `$44` offset `$0B00`.
6. Saves SP, mode, runtime magic, and line-chain guards in bridge metadata.
7. Refreshes the visible hidden-helper shadow at `$C280`.
8. Restores the original page-3 BASIC/KERNAL vectors.
9. Jumps to the ReadyOS shim return entry at `$C80C`.

On warm resume, ReadyOS restores the app window and jumps back to `$1000`.
ReadyBASIC:

1. Sees entry-local warm magic.
2. Restores the hidden helper at `$A000` from the preserved `$C280` shadow.
3. Reinstalls ReadyBASIC-owned vectors.
4. Re-marks REU bank ownership for `$44/$45`.
5. Does not reread cold-only `REGSEED` or command-pack load images.
6. Restores zero page and stack from REU bank `$44` through `$C400/$C500`, and
   restores SP/mode metadata from the bridge.
7. Preserves live BASIC pointers such as `FRETOP`, `VARTAB`, `ARYTAB`, and
   `STREND`.
8. In READY-mode resume, clears the launcher surface, redraws the ReadyBASIC
   banner, positions the prompt, and enters `BASIC_READY`.

## Hidden Code And Banking Contract

ReadyBASIC uses hidden code in two places:

| Code | Range | Purpose |
|---|---:|---|
| Hidden helper | `$A000-$A336` | REU prestash, save/restore helpers, bank-sensitive work. |
| Hidden overlay | `$A800-$A84C` | Current `ZHIDDENRAM` worker example. |

Before calling hidden code, ReadyBASIC saves flags, disables interrupts, forces
the low CPU data-direction bits in `$0000` to outputs, saves `$0001`, maps RAM
under BASIC ROM while keeping KERNAL visible, performs the copy or call, then
restores `$0001` and flags. This keeps BASIC ROM/RAM banking explicit and keeps
KERNAL-visible calls safe where needed.

## Invariants

- ReadyBASIC is verified through normal ReadyOS run/profile flows, not by
  loading an individual app directly.
- `BASIC_START` is `$2401`.
- `$2400` must remain zero before stored-program `RUN`.
- `RESIDENT` must stay below `$2400`.
- `BRIDGE` must stay below `$C200`, leaving `$C200-$C5FF` for relocated frames.
- `$C600-$C7FF` is shared ReadyOS REU metadata, not ReadyBASIC scratch.
- `$C800-$C9FF` is ReadyOS shim ABI, not app RAM.
- Warm resume restores `$A000` from the `$C280` visible shadow before hidden helper calls.
- Warm resume must not cold-reset `FRETOP`, `VARTAB`, `ARYTAB`, or `STREND`.
- ReadyBASIC-owned vectors are restored before yielding to ReadyOS.
- Non-ReadyBASIC statements tail-call the original execute vector without
  mutating `TXTPTR`.
- Output variables are cleared before command execution.
- String heap writes happen only in visible resident code.
- Acceptance re-entry uses launcher menu navigation, not direct app-bank
  hotkeys.

## Current Verification Evidence

Static guardrails:

```sh
make readybasic-plugin-static-check
```

Current static layout:

| Segment | Range | Size |
|---|---:|---:|
| `ENTRY` | `$1000-$1102` | `$0103` (259B) |
| `RESIDENT` | `$1200-$23FD` | `$11FE` (4.5K, 4606 exact bytes) |
| `REGSEED` | `$5000-$600F` | `$1010` (4.0K, 4112 exact bytes) |
| `HIDDEN` | `$A000-$A376` | `$0377` (0.9K, 887 exact bytes) |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` (77B) |
| `LOWPACK` | `$A900-$AF19` | `$061A` (1.5K, 1562 exact bytes) |
| `BRIDGE` | `$C000-$C1F4` | `$01F5` (501B) |

Before/after for native `PROC`/`FUNC`:

| Measure | Before | After |
|---|---:|---:|
| `BASIC_START` | `$1C01` | `$2101` |
| Empty BASIC free bytes | `33789` | `32509` formula bytes (`32519` live header bytes) |
| `bin/readybasic.prg` size | `20994` | `20994` |
| `RESIDENT` | `$09B4` / 2484B | `$0EF4` / 3828B |
| Resident delta | - | `+$0540` / `+1344B` |
| `LOWPACK` | `$061A` / 1562B | `$061A` / 1562B |
| Command overlay delta | - | `0B` |
| `BRIDGE` | `$019B` / 411B | `$01FB` / 507B |
| Bridge/shared-state delta | - | `+$0060` / `+96B` |
| `REGSEED` | `$1010` / 4112B | `$1010` / 4112B |

Before/after for full bare-command and expression syntax versus the native
`PROC`/`FUNC` baseline:

| Measure | Native PROC/FUNC baseline | Current branch |
|---|---:|---:|
| `BASIC_START` | `$2101` | `$2401` |
| Empty BASIC free bytes | `32509` | `31741` |
| BASIC-free delta | - | `-768` bytes |
| `bin/readybasic.prg` size | `20994` | `20994` |
| `RESIDENT` | `$0EF4` / 3828B | `$11FE` / 4606B |
| Resident delta | - | `+$030A` / `+778B` |
| `LOWPACK` | `$061A` / 1562B | `$061A` / 1562B |
| Command overlay delta | - | `0B` |
| `BRIDGE` | `$01FB` / 507B | `$01F5` / 501B |
| Bridge/shared-state delta | - | `-$0006` / `-6B` |
| `REGSEED` | `$1010` / 4112B | `$1010` / 4112B |

Recent VICE coverage includes:

| Probe | Coverage |
|---|---|
| Full expression probe | Direct bare command statements, command expressions, parenthesized `EXEC PROC`, `FUNC` with later assignment plus `RET`, numeric `FUNC` expression return/assignment, string `FUNC` expression return, and readable `LIST`. |
| Plugin command probe | Direct command statements, direct `IF 1 THEN ZECHO1(P%)`, `UPPER`/`LOWER`, old-name rejection, string/REM safety, leading-comma rejection, `SCRCAP`/`SCRPUT`, slot-128 lookup, 128-handle edge, 48KB heap edge, screen heap exhaustion, wrong-handle-type rejection, screen-handle free, resume. |
| Program probe | Stored line start, colon chains, true/false `IF ... THEN COMMAND(...)`, `FOR/NEXT`, strings, REM, DATA, arrays, hidden worker, handles, failure clearing. |
| `rbproc1` probe | Stored positive `PROC`/`FUNC`: no-param PROC, `%`, `$`, `%` return, `$` return, explicit `RET%`/`RET$`, colon chain, normalized `IF THEN :EXEC`, nested depth 2, command and FUNC return assignment, command return inside top-level `ABS(...)`, flat numeric expression actuals, string command return inside a `FUNC` body, and readable `LIST`. |
| `rbprocerr` probe | Stored negative `PROC`/`FUNC`: unknown routine, wrong count/type, statement `EXEC` to `FUNC`, PROC extra actual, `ENDP` without `EXEC`, and return-stack overflow. |
| Full visual verification | Human-watchable command, program, screen-handle, handle/heap edge, resume, and error coverage. |
| Lifecycle probe | Cold entry, `EXIT`, launcher re-entry, READY-mode redraw. |
| State probe | BASIC variable/string survival and command availability after resume. |
| `rbtest1` probe | Sample program assembled at the relocated BASIC workspace. |
| Large-vars probe | BASIC workspace and variable behavior under heavier state. |
| Cross-app resume stress | ReadyBASIC survives repeated app switches. |
| Second-entry/editor stress | ReadyBASIC survives editor/launcher round trips and later re-entry. |

Some harness wrappers can report a process-level `partial` status even when
every step is `ok` and `FailedStep` is `null`; for ReadyBASIC these were treated
as harness shutdown-status quirks, not command failures.

## Bare Command And Expression Branch: 2026-05-23

This branch makes parenthesized calls the preferred syntax and enables BASIC
expression returns while keeping the resident implementation tight.

Supported command expressions:

```basic
ZECHO1(P%)
ZADD16(4,5,A%)
PRINT ZADD16(5,10)
A=ZADD16(8,9)
T$=UPPER("ready")
PRINT ZHIDDENRAM("A")
```

Supported native routine forms:

```basic
100 PROC SHOWI(P%)
110 PRINT P%
120 ENDP

200 FUNC GREET(N$)
210 RET "HI "+N$
220 ENDP

10 EXEC SHOWI(7)
20 T$=GREET("READY"):PRINT T$
```

`PROC`/`FUNC` definitions and `EXEC` calls accept parentheses for non-empty
argument lists. Zero-argument routines still use `EXEC NAME`; `EXEC NAME()` was
cut to save resident bytes. `FUNC` uses `RET expr`, with optional `RET% expr`
or `RET$ expr` type markers. `EXEC` runs `PROC` bodies only; `FUNC` returns
the value as the expression result. `FUNC` calls scan the body, execute
simple scalar assignments, and evaluate the `RET` expression; arbitrary earlier
BASIC statements remain outside V1.

Numeric actuals for command and `FUNC` calls can be ordinary numeric
expressions in the flat forms tested by `rbproc1`, such as `ADDI(1,2+4)`.
Nested parentheses inside actual lists, such as `ADDI(1,(2+4))`, are not
supported today. String actuals remain string variables or quoted literals.
Command and `FUNC` returns can be assigned or printed directly; command numeric
returns also work inside a top-level BASIC numeric function in the tested form
`ABS(ZADD16(1,6)-10)`. `FUNC` returns are not currently accepted as nested
arguments to BASIC ROM functions such as `ABS(ADDI(...))` or
`LEFT$(GREET(...),2)`.

Memory comparison against the native PROC/FUNC baseline:

| Measure | PROC/FUNC baseline | Expression branch |
|---|---:|---:|
| `BASIC_START` | `$2101` | `$2401` |
| Empty BASIC free bytes | `32509` | `31741` |
| BASIC-free delta | - | `-768` bytes |
| `RESIDENT` | `$0EF4` / 3828B | `$11FE` / 4606B |
| Resident delta | - | `+778` bytes |
| `BRIDGE` | `$01FB` / 507B | `$01F5` / 501B |
| Bridge delta | - | `-6` bytes |
| `LOWPACK` | `$061A` / 1562B | `$061A` / 1562B |
| Command overlay delta | - | `0` bytes |
| `bin/readybasic.prg` size | `20994` | `20994` |

Verification for this branch:

| Probe | Result |
|---|---|
| `make readybasic-plugin-static-check` | Pass |
| Focused VICE expression probe | Pass: bare statement commands, `ZADD16()`, `UPPER()`, `ZHIDDENRAM()`, parenthesized `EXEC PROC`, `FUNC` with later assignment plus `RET`, numeric `FUNC` expression return/assignment, and string `FUNC` expression return. |
