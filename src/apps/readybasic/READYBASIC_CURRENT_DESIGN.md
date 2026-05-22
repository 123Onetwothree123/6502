# ReadyBASIC Current Design

This is the current ReadyBASIC design as implemented by
`src/apps/readybasic/readybasic.s`, linked by `cfg/ready_app_readybasic.cfg`,
and verified against the current `obj/readybasic.map`.

ReadyBASIC is a ReadyOS app that hosts a relocated C64 BASIC V2 workspace and
adds a lean command spine for raw `!COMMAND args` statements. It is not a
private BASIC token system. Stored program lines remain readable, `LIST` shows
the same visible `!` command text, and the execute hook recognizes commands when
BASIC dispatches a statement.

## Current Syntax And Statement Behavior

ReadyBASIC commands use this form:

```basic
!COMMAND first,arg,arg
```

The command name follows `!`. The first argument is separated by whitespace, and
later arguments use normal comma separation. A leading comma after the command
name is a syntax error, so `!ADD16,1,2,A%` is rejected.

The `!` prefix is special only where BASIC is about to dispatch a statement:

| Context | Supported | Notes |
|---|---:|---|
| Immediate mode | Yes | Example: `!PING P%`. |
| Stored program line start | Yes | Raw `!` survives `LIST` and runs through `$0308`. |
| After `:` | Yes | Example: `PRINT "A":!PING P%`. |
| Inside `FOR/NEXT` body | Yes | Use it as a statement in the loop body. |
| After `IF ... THEN` | Yes | The crunch hook rewrites `THEN !` to `THEN :!`. |
| Inside `PRINT`, expressions, or `FOR` clauses | No | `!` is not an expression operator or clause syntax. |
| Inside strings, `REM`, or `DATA` | Ordinary text | These are not rewritten or dispatched. |
| After `ELSE` | No native support | BASIC V2 has no `ELSE`; ReadyBASIC does not add it. |

`IF 1 THEN !PING P%` works, but the stored/listed form becomes
`IF 1 THEN :!PING P%`. That is an intentional size-saving normalization. It lets
BASIC's existing statement dispatcher reach the normal ReadyBASIC execute hook
without adding a larger custom IF parser.

ReadyBASIC also recognizes manual prompt `EXIT` as the ReadyOS yield command.
Program-line `EXIT` resume remains future work; the proven V1 path is direct
prompt `EXIT`.

## Command Families

The current commands are examples of command shapes that the spine needs to
support, not the final product command catalog.

| Category | Commands | Purpose |
|---|---|---|
| Scalar Outputs | `PING`, `ADD16` | Prove integer output variables, numeric expression parsing, and scalar result commit. |
| String Transfer/Transform | `STRUP` | Prove string input capture and resident-owned BASIC string output allocation. |
| Hidden Banked Worker | `HCRC` | Prove worker code can run under BASIC ROM RAM in the `$A800` hidden overlay slot. |
| Integer Array Transfer | `SUMAI`, `RANGEAI` | Prove array input/output via explicit base element plus count. |
| Persistent REU Handles | `BUFNEW`, `BUFFILL`, `BUFFREE` | Prove stable BASIC-visible handles for persistent REU-backed data. |
| Temporary REU Workspace | `TEMPSCRATCH` | Prove temporary page allocation and cleanup. |
| Error/Failure Contract | `FAIL` | Prove outputs are cleared before execution and stale results are not committed. |
| ReadyOS Yield | `EXIT` | Save BASIC runtime state, restore vectors, and return through the ReadyOS shim. |

### Command Inventory

| Command | Code placement | Parameters | Result behavior |
|---|---|---|---|
| `!PING OUT%` | Low overlay at `$1C00+$0000`, copy `$0015` | output integer | Returns `1`. |
| `!ADD16 A,B,OUT%` | Low overlay at `$1C00+$0015`, copy `$001E` | two numeric expressions, output integer | Returns 16-bit sum. |
| `!STRUP S$,OUT$` | Low overlay at `$1C00+$0033`, copy `$003B` | string variable or quoted literal, output string | Uppercases staged bytes. |
| `!HCRC S$,OUT%` | Hidden overlay at `$A800`, copy `$004D` | string variable or quoted literal, output integer | Returns a simple uppercase-byte checksum. |
| `!SUMAI A%(0),COUNT,OUT%` | Low overlay at `$1C00+$006E`, copy `$0044` | integer array base, count, output integer | Sums integer array elements. |
| `!RANGEAI START,COUNT,A%(0)` | Low overlay at `$1C00+$00B2`, copy `$003D` | start value, count, output array base | Stages consecutive integers, then resident code writes them to the array. |
| `!BUFNEW LEN,H%` | Low overlay entry `$00EF`, copy full `$02F3` low pack | byte length, output handle | Allocates pages in REU bank `$44` and returns a one-based handle. |
| `!BUFFILL H%,BYTE` | Low overlay entry `$00F3`, copy full `$02F3` low pack | handle, fill byte | Fills handle pages through the `$2700` page buffer. |
| `!BUFFREE H%` | Low overlay entry `$00F7`, copy full `$02F3` low pack | handle | Frees handle metadata and page bitmap state. |
| `!TEMPSCRATCH LEN,OUT%` | Low overlay entry `$00FB`, copy full `$02F3` low pack | byte length, output integer | Allocates and frees temporary pages, returning page count. |
| `!FAIL CODE,OUT%` | Low overlay at `$1C00+$00FF`, copy `$001B` | error code, output integer | Clears output first, then reports `?RB ERROR code`. |

The handle-oriented commands copy the full low pack because their wrappers share
allocator helper routines that currently live in the packed low overlay. That
keeps the resident core lean at the cost of copying more overlay bytes for these
sample commands.

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
| `src/apps/readybasic/rbtest1.bas` / `obj/rbtest1.prg` | Sample BASIC program only; not part of the command overlay mechanism. |
| `build_support/verify_readybasic_plugin.py` | Static guardrail checker for the ReadyBASIC layout and REU constants. |

The linker puts packed command bytes in the PRG load image at `CMDPACK`
`$2800-$2FFF`, but their runtime addresses are different:

| Segment | Load/source role | Runtime role |
|---|---|---|
| `LOWPACK` | Packed low command bytes loaded from `CMDPACK` and prestashed to REU bank `$45` offset `$0000`. | Fetched on demand into the fixed low overlay slot `$1C00-$23FF`. |
| `HIDDENPACK` | Packed hidden worker bytes loaded after `LOWPACK` in `CMDPACK` and prestashed to REU bank `$45` offset `$02F3`. | Fetched on demand into hidden RAM at `$A800-$A84C`. |
| `REGSEED` | Load-only registry header and command descriptors at `$4000-$416F`. | Copied on cold boot into REU bank `$44` offsets `$0000` and `$0100`. |

Cold boot is the only time the load-image command pack and `REGSEED` are trusted.
The hidden helper copies the registry/header to REU bank `$44` and copies
`LOWPACK` plus `HIDDENPACK` to REU bank `$45`. After that, BASIC may own the
former load-image addresses, so warm resume reuses the REU copies and does not
reseed from `$2800+` or `$4000+`.

At command execution time, the descriptor tells the resident loader which bytes
to fetch:

1. Low commands use descriptor offsets `2-5` for code offset/size and `10-11`
   for entry offset. ReadyBASIC fetches from bank `$45` into `$1C00 + offset`
   and jumps through the computed low overlay entry.
2. Hidden commands use descriptor offsets `6-9` for code offset/size and
   `12-13` for entry offset. ReadyBASIC maps RAM under BASIC ROM, fetches into
   `$A000 + entry offset`, and calls the hidden overlay entry.
3. Commands can fetch a small slice or the whole low pack. The current handle
   commands fetch the whole `$02F3` low pack because their shared allocator
   helpers live there.

## C64 RAM Layout

ReadyBASIC runs inside the ReadyOS app working region `$1000-$C5FF`. ReadyOS
metadata and shim space above that are not general ReadyBASIC scratch.

| Region | Current range | Size | Owner and role |
|---|---:|---:|---|
| `ENTRY` | `$1000-$1102` | `$0103` | Tiny entry, cold/warm discriminator, early hidden/bridge copies. |
| `RESIDENT` | `$1200-$1BC1` | `$09C2` | Visible parser, vector hooks, BASIC ROM calls, REU DMA wrappers, result commit. |
| Low overlay slot | `$1C00-$23FF` | 2 KB slot | Runtime destination for command slices copied from REU bank `$45`. |
| `LOWPACK` image | `$1C00-$1EF2` | `$02F3` | Linker run image for packed low commands before REU prestash. |
| Shared frames | `$2400-$27FF` | 1 KB | Call frame, result frame, descriptor buffer, command-name buffer, page buffer. |
| Command pack load image | `$2800-$2FFF` | 2 KB file range | Low and hidden overlay seed bytes before cold prestash. |
| BASIC sentinel | `$3000` | 1 byte | Must stay zero before stored-program `RUN`. |
| BASIC workspace | `$3001-$95FF` | app-owned BASIC space | Program text, variables, arrays, string heap. |
| Runtime snapshot | `$9600-$99FF` | 1 KB | Saved zero page, stack page, SP, resume mode, line-chain guards. |
| Hidden shadow | `$9A00-$9FFF` | 1.5 KB | Preserved source for restoring `$A000` helper on warm resume. |
| `HIDDEN` | `$A000-$A237` | `$0238` | Helper code run with RAM mapped under BASIC ROM. |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` | Hidden worker overlay image. |
| `BRIDGE` | `$C000-$C164` | `$0165` | Persistent bridge state, saved vectors, overlay variables, handle metadata, debug bytes. |
| ReadyOS REU metadata | `$C600-$C7FF` | shared | ReadyBASIC only marks REU bank ownership here. |
| ReadyOS shim ABI | `$C800-$C9FF` | shared | ReadyOS jump table and data; not ReadyBASIC RAM. |

The PRG load image is larger than the live resident core. On cold entry,
ReadyBASIC copies the hidden helper seed from the load image to `$A000` and
`$9A00`, copies the bridge seed to `$C000`, and prestashes registry/code seed
data into REU. After that, BASIC owns `$3001-$95FF`. Warm resume must therefore
not reread load-only seed tables at `$4000+`, because that address range may now
be BASIC program or variable storage.

## BASIC Free RAM Compared With Stock C64 BASIC

Stock C64 BASIC V2 starts at `$0801` and normally has memory top at `$A000`,
which gives about `38911` bytes free on an empty machine.

ReadyBASIC relocates BASIC to `$3001` and uses `$9600` as the BASIC memory top.
On an empty ReadyBASIC workspace, variables begin at `$3003`, so the practical
empty BASIC free space is:

```text
$9600 - $3003 = 26109 bytes
```

That is `12802` bytes less than stock C64 BASIC, or about `67.1%` of the stock
empty BASIC free space. The trade is intentional: the lower app window holds the
ReadyBASIC resident core, overlay slots, shared frames, and cold-load seed
images, while the upper app window holds runtime snapshot and hidden helper
state needed for ReadyOS suspend/resume.

| Environment | BASIC text start | BASIC top | Empty free bytes |
|---|---:|---:|---:|
| Stock C64 BASIC V2 | `$0801` | `$A000` | `38911` |
| ReadyBASIC current layout | `$3001` | `$9600` | `26109` |
| Difference | - | - | `-12802` |

Strategies to maximize BASIC RAM while adding many more commands:

- Keep the resident core below `$1C00`; every resident byte is permanent C64 RAM
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
| New command needing a larger fixed C64 buffer | Permanent C64 RAM cost only if it expands `$2400-$27FF`, the overlay slots, resident RAM, or bridge state. | Depends on whether the data can be moved to REU instead. |

## Page-3 Vector Ownership

ReadyBASIC saves the original BASIC vectors, then installs:

| Vector | Address | ReadyBASIC role |
|---|---:|---|
| Crunch | `$0304/$0305` | Calls ROM crunch first, then normalizes tokenized `THEN !` into `THEN :!`. |
| Execute | `$0308/$0309` | Peeks for `!` or `EXIT`; otherwise tail-calls the original execute vector without advancing `TXTPTR`. |
| List | `$0306/$0307` | Saved/restored, but V1 leaves normal ROM listing behavior. |

Page-3 vectors are global machine state. `EXIT` restores the original vectors
before jumping back through the ReadyOS shim so the launcher or another app
cannot accidentally dispatch through stale ReadyBASIC code.

## Command Dispatch Pipeline

1. BASIC dispatches a statement through the execute vector.
2. ReadyBASIC peeks at the next non-space byte without mutating `TXTPTR`.
3. If the statement is neither `!` nor `EXIT`, ReadyBASIC tail-calls the saved
   ROM execute vector.
4. For `!`, ReadyBASIC advances past the raw bang, parses and normalizes the
   command name into `$26A0`, and rejects an empty name, a too-long name, or a
   leading comma.
5. Command lookup linearly scans fixed 32-byte descriptors in REU bank `$44`
   offset `$0100`.
6. The resident parser dispatches by signature id and uses BASIC ROM helpers to
   parse parameters and capture output references.
7. Output variables are cleared before command execution.
8. The call frame at `$2400` is mirrored to REU bank `$44` offset `$0400`.
9. Command code is fetched from REU bank `$45` into the low overlay slot
   `$1C00` or hidden overlay slot `$A800`.
10. The worker writes a compact result frame at `$2500`.
11. The result frame is mirrored to REU bank `$44` offset `$0500`.
12. Resident code checks status, prints `?RB ERROR n` on failure, or commits
    integer, string, or array results to the captured BASIC output reference.

The command-name parser accepts normal letters/digits, folds lowercase ASCII to
uppercase, maps shifted uppercase/PETSCII-like `$C1-$DA` bytes back to `A-Z`,
and handles a small number of tokenization edge cases that can appear inside
names.

## Frames And ABI Surfaces

| Surface | Address or offset | Role |
|---|---:|---|
| Call frame | `$2400` | Command id, parameter count, numeric slots, pointer/count slots, string input buffer. |
| Result frame | `$2500` | Status, error number, value tag, scalar value, string output buffer, array output buffer. |
| Descriptor buffer | `$2680` | One descriptor fetched from REU bank `$44`. |
| Command buffer | `$26A0` | Uppercase normalized command name. |
| Page buffer | `$2700` | 256-byte staging page for REU handle operations. |
| REU call snapshot | Bank `$44`, `$0400` | Copy of the current call frame. |
| REU result snapshot | Bank `$44`, `$0500` | Copy of the current result frame. |

The descriptor ABI is fixed-size and compact:

| Descriptor offset | Field |
|---:|---|
| `0` | Command id. |
| `1` | Flags: low overlay, hidden overlay, or both. |
| `2-3` | Low code offset in REU bank `$45`. |
| `4-5` | Low code size. |
| `6-7` | Hidden code offset in REU bank `$45`. |
| `8-9` | Hidden code size. |
| `10-11` | Low entry offset from `$1C00`. |
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
| `$0100` | 11 command descriptors, 32 bytes each. |
| `$0400` | Current call-frame snapshot. |
| `$0500` | Current result-frame snapshot. |
| `$0600` | Reserved debug ring area. |
| `$0800` | Persistent handle metadata snapshot. |
| `$0900` | Reserved transient heap/staging area. |
| `$8000-$8FFF` | V1 sample data heap: 16 pages of 256 bytes. |

The persistent handle model supports eight handles. Each handle is represented
to BASIC as a small integer, while bridge/REU metadata records the backing bank,
start page, page count, type, and page bitmap state. The current sample heap
uses pages `$80-$8F` inside bank `$44`; future large or long-lived objects
should allocate additional REU banks and keep the same small handle model.

### Bank `$45`: Packed Command Code

| Offset | Region |
|---:|---|
| `$0000-$02DC` | Low overlay pack copied into `$1C00-$23FF`. |
| `$02F3-$033F` | Hidden overlay pack copied into `$A800-$A84C`. |

Descriptors point into these packed bytes. Normal low commands fetch only their
slice. The REU handle commands currently fetch the whole low pack because shared
allocator helpers live there.

## Cold Boot Lifecycle

1. ReadyOS loads `readybasic.prg` at `$1000`.
2. Entry code checks its local warm/cold magic.
3. On cold path, it maps RAM under BASIC ROM long enough to copy the hidden
   helper seed to `$A000` and `$9A00`.
4. It copies bridge seed bytes from the load image to `$C000`.
5. The resident core resets KERNAL/BASIC vectors, saves originals, and installs
   ReadyBASIC crunch/execute hooks.
6. BASIC is relocated to `TXTTAB=$3001` with top at `$9600`.
7. `$3000`, `$3001`, and `$3002` are cleared. `$3000` is the sentinel byte
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
4. Saves zero page `$0000-$00FF` to `$9600-$96FF`.
5. Saves stack page `$0100-$01FF` to `$9700-$97FF`.
6. Saves SP, mode, runtime magic, and line-chain guards under `$9800+`.
7. Restores the original page-3 BASIC/KERNAL vectors.
8. Jumps to the ReadyOS shim return entry at `$C80C`.

On warm resume, ReadyOS restores the app window and jumps back to `$1000`.
ReadyBASIC:

1. Sees entry-local warm magic.
2. Restores the hidden helper at `$A000` from the preserved `$9A00` shadow.
3. Reinstalls ReadyBASIC-owned vectors.
4. Re-marks REU bank ownership for `$44/$45`.
5. Does not reread cold-only `REGSEED` or command-pack load images.
6. Restores zero page, stack, SP, and runtime metadata from `$9600-$99FF`.
7. Preserves live BASIC pointers such as `FRETOP`, `VARTAB`, `ARYTAB`, and
   `STREND`.
8. In READY-mode resume, clears the launcher surface, redraws the ReadyBASIC
   banner, positions the prompt, and enters `BASIC_READY`.

## Hidden Code And Banking Contract

ReadyBASIC uses hidden code in two places:

| Code | Range | Purpose |
|---|---:|---|
| Hidden helper | `$A000-$A237` | REU prestash, save/restore helpers, bank-sensitive work. |
| Hidden overlay | `$A800-$A84C` | Current `HCRC` worker example. |

Before calling hidden code, ReadyBASIC saves flags, disables interrupts, forces
the low CPU data-direction bits in `$0000` to outputs, saves `$0001`, maps RAM
under BASIC ROM while keeping KERNAL visible, performs the copy or call, then
restores `$0001` and flags. This keeps BASIC ROM/RAM banking explicit and keeps
KERNAL-visible calls safe where needed.

## Invariants

- ReadyBASIC is verified through normal ReadyOS run/profile flows, not by
  loading an individual app directly.
- `BASIC_START` is `$3001`.
- `$3000` must remain zero before stored-program `RUN`.
- `RESIDENT` must stay below `$1C00`.
- `BRIDGE` must stay below `$C600`.
- `$C600-$C7FF` is shared ReadyOS REU metadata, not ReadyBASIC scratch.
- `$C800-$C9FF` is ReadyOS shim ABI, not app RAM.
- Warm resume restores `$A000` from `$9A00` before hidden helper calls.
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
| `ENTRY` | `$1000-$1102` | `$0103` |
| `RESIDENT` | `$1200-$1BC1` | `$09C2` |
| `LOWPACK` | `$1C00-$1EF2` | `$02F3` |
| `REGSEED` | `$4000-$416F` | `$0170` |
| `HIDDEN` | `$A000-$A237` | `$0238` |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` |
| `BRIDGE` | `$C000-$C164` | `$0165` |

Recent VICE coverage includes:

| Probe | Coverage |
|---|---|
| Plugin command probe | Direct `!` commands, direct `IF 1 THEN !PING`, string/REM safety, leading-comma rejection, resume. |
| Program probe | Stored line start, colon chains, true/false `IF ... THEN !`, `FOR/NEXT`, strings, REM, DATA, arrays, hidden worker, handles, failure clearing. |
| Full visual verification | Human-watchable command, program, resume, and error coverage. |
| Lifecycle probe | Cold entry, `EXIT`, launcher re-entry, READY-mode redraw. |
| State probe | BASIC variable/string survival and command availability after resume. |
| `rbtest1` probe | Sample program assembled at the relocated BASIC workspace. |
| Large-vars probe | BASIC workspace and variable behavior under heavier state. |
| Cross-app resume stress | ReadyBASIC survives repeated app switches. |
| Second-entry/editor stress | ReadyBASIC survives editor/launcher round trips and later re-entry. |

Some harness wrappers can report a process-level `partial` status even when
every step is `ok` and `FailedStep` is `null`; for ReadyBASIC these were treated
as harness shutdown-status quirks, not command failures.
