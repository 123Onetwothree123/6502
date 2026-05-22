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
| Persistent REU Handles | `BUFNEW`, `BUFFILL`, `BUFFREE`, `SCRCAP`, `SCRPUT` | Prove stable BASIC-visible handles for persistent REU-backed data, including typed screen text+color resources. |
| Temporary REU Workspace | `TEMPSCRATCH` | Prove temporary page allocation and cleanup. |
| Error/Failure Contract | `FAIL` | Prove outputs are cleared before execution and stale results are not committed. |
| Runtime Introspection | `FREEMEM` | Prints live BASIC free memory and refreshes the header value without returning an output variable. |
| ReadyOS Yield | `EXIT` | Save BASIC runtime state, restore vectors, and return through the ReadyOS shim. |

### Command Inventory

| Command | Code placement | Parameters | Result behavior |
|---|---|---|---|
| `!PING OUT%` | Low overlay at `$A900+$0000`, copy `$0015` | output integer | Returns `1`. |
| `!ADD16 A,B,OUT%` | Low overlay at `$A900+$0015`, copy `$001E` | two numeric expressions, output integer | Returns 16-bit sum. |
| `!STRUP S$,OUT$` | Low overlay at `$A900+$0033`, copy `$003B` | string variable or quoted literal, output string | Uppercases staged bytes. |
| `!HCRC S$,OUT%` | Hidden overlay at `$A800`, copy `$004D` (77B) | string variable or quoted literal, output integer | Returns a simple uppercase-byte checksum. |
| `!SUMAI A%(0),COUNT,OUT%` | Low overlay at `$A900+$006E`, copy `$0044` | integer array base, count, output integer | Sums integer array elements. |
| `!RANGEAI START,COUNT,A%(0)` | Low overlay at `$A900+$00B2`, copy `$003D` | start value, count, output array base | Stages consecutive integers, then resident code writes them to the array. |
| `!BUFNEW LEN,H%` | Low overlay entry `$00EF`, copy full `$04E0` (1.2K) low pack | byte length, output handle | Allocates buffer pages in REU bank `$44` and returns a one-based handle. |
| `!BUFFILL H%,BYTE` | Low overlay entry `$00F3`, copy full `$04E0` (1.2K) low pack | buffer handle, fill byte | Fills buffer handles through the `$C500` page buffer and rejects non-buffer handles. |
| `!BUFFREE H%` | Low overlay entry `$00F7`, copy full `$04E0` (1.2K) low pack | handle | Frees any valid handle type and clears metadata/page bitmap state. |
| `!TEMPSCRATCH LEN,OUT%` | Low overlay entry `$00FB`, copy full `$04E0` (1.2K) low pack | byte length, output integer | Allocates and frees temporary pages, returning page count. |
| `!FAIL CODE,OUT%` | Low overlay at `$A900+$00FF`, copy `$001B` | error code, output integer | Clears output first, then reports `?RB ERROR code`. |
| `!FREEMEM` | Low overlay at `$A900+$011A`, copy `$0016` | none | Prints current live BASIC free bytes and refreshes the header. |
| `!SCRCAP H%` | Low overlay entry `$0130`, copy full `$04E0` (1.2K) low pack | output handle | Captures screen text `$0400-$07E7` and color RAM `$D800-$DBE7` into a typed screen handle. |
| `!SCRPUT H%` | Slot 128 descriptor; low overlay entry `$0159`, copy full `$04E0` (1.2K) low pack | screen handle | Validates the screen handle type and restores text plus color RAM. |

The handle-oriented commands copy the full low pack because their wrappers share
allocator helper routines that currently live in the packed low overlay. That
keeps the resident core lean at the cost of copying more overlay bytes for these
sample commands.

`SCRCAP`/`SCRPUT` were named to avoid C64 BASIC tokenizer conflicts with
embedded `SAVE`/`LOAD` tokens. They are the implemented forms of the original
screen save/load concept.

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

| Segment | Size | Load/source role | Runtime role |
|---|---:|---|---|
| `LOWPACK` | `$04E0` (1.2K) | Packed low command bytes loaded from `CMDPACK` and prestashed to REU bank `$45` offset `$0000`. | Fetched on demand into the banked low overlay slot at `$A900+`, under BASIC ROM. |
| `HIDDENPACK` | `$004D` (77B) | Packed hidden worker bytes loaded after `LOWPACK` in `CMDPACK` and prestashed to REU bank `$45` offset `$04E0`. | Fetched on demand into hidden RAM at `$A800-$A84C`. |
| `REGSEED` | `$1010` (4112B) | Load-only registry header and 128 command descriptors at `$5000-$600F`. | Copied on cold boot into REU bank `$44` offsets `$0000` and `$1000`. |

Cold boot is the only time the load-image command pack and `REGSEED` are trusted.
The hidden helper copies the registry/header to REU bank `$44` and copies
`LOWPACK` plus `HIDDENPACK` to REU bank `$45`. After that, BASIC may own the
former load-image addresses, so warm resume reuses the REU copies and does not
reseed from `$2800+` or `$4000+`.

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
   and screen-handle commands fetch the whole `$04E0` low pack because their
   shared allocator and screen-copy helpers live there.

## C64 RAM Layout

ReadyBASIC runs inside the ReadyOS app working region `$1000-$C5FF`. ReadyOS
metadata and shim space above that are not general ReadyBASIC scratch.

| Region | Current range | Size | Owner and role |
|---|---:|---:|---|
| `ENTRY` | `$1000-$1102` | `$0103` (259B) | Tiny entry, cold/warm discriminator, early hidden/bridge copies. |
| `RESIDENT` | `$1200-$1BF9` | `$09FA` (2554B) | Visible parser, vector hooks, BASIC ROM calls, REU DMA wrappers, result commit. |
| BASIC sentinel | `$1C00` | 1 byte | Must stay zero before stored-program `RUN`. |
| BASIC workspace | `$1C01-$9FFF` | `$83FF` region, `33789` free bytes (33.0K) | Program text, variables, arrays, string heap. |
| Command pack load image | `$2800-$3FFF` | `$1800` (6.0K) file range | Low and hidden overlay seed bytes before cold prestash. |
| Runtime snapshot | REU bank `$44`, offsets `$0A00-$0BFF` | `$0200` (0.5K) plus bridge metadata | Saved zero page, stack page, SP, resume mode, line-chain guards. |
| `HIDDEN` | `$A000-$A336` | `$0337` (0.8K) | Helper code run with RAM mapped under BASIC ROM. |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` (77B) | Hidden worker overlay image. |
| `LOWPACK` runtime | `$A900-$ADDF` | `$04E0` (1.2K) | Banked low command pack fetched from REU bank `$45`. |
| `BRIDGE` | `$C000-$C1C4` | `$01C5` (453B) | Persistent bridge state, saved vectors, overlay variables, handle metadata, debug bytes. |
| Shared frames | `$C200-$C5FF` | `$0400` (1.0K) | Call frame, result frame, descriptor buffer, command-name buffer, page/runtime buffers. |
| Hidden shadow | `$C280-$C5B6` | `$0337` (0.8K) | Visible-RAM source for restoring `$A000` helper on warm resume; refreshed during `!EXIT`. |
| ReadyOS REU metadata | `$C600-$C7FF` | `$0200` (0.5K) shared | ReadyBASIC only marks REU bank ownership here. |
| ReadyOS shim ABI | `$C800-$C9FF` | `$0200` (0.5K) shared | ReadyOS jump table and data; not ReadyBASIC RAM. |

The PRG load image is larger than the live resident core. On cold entry,
ReadyBASIC copies the hidden helper seed from the load image to `$A000` and
the visible shadow at `$C280`, copies the bridge seed to `$C000`, and prestashes
registry/code seed data into REU. After that, BASIC owns `$1C01-$9FFF`. Warm resume must therefore
not reread load-only seed tables at `$4000+`, because that address range may now
be BASIC program or variable storage.

## BASIC Free RAM Compared With Stock C64 BASIC

Stock C64 BASIC V2 starts at `$0801` and normally has memory top at `$A000`,
which gives about `38911` bytes free on an empty machine.

ReadyBASIC relocates BASIC to `$1C01` and uses `$A000` as the BASIC memory top.
On an empty ReadyBASIC workspace, variables begin at `$1C03`, so the practical
empty BASIC free space is:

```text
$A000 - $1C03 = 33789 bytes (33.0K)
```

That is `5122` bytes (5.0K) less than stock C64 BASIC, or about `86.8%` of the stock
empty BASIC free space. The trade is intentional: the lower app window holds the
ReadyBASIC resident core and cold-load seed images, while banked RAM under
BASIC ROM holds command workers and REU holds the runtime stack/zero-page
snapshot needed for ReadyOS suspend/resume.

| Environment | BASIC text start | BASIC top | Empty free bytes |
|---|---:|---:|---:|
| Stock C64 BASIC V2 | `$0801` | `$A000` | `38911` (38.0K) |
| ReadyBASIC current layout | `$1C01` | `$A000` | `33789` (33.0K) |
| Difference | - | - | `-5122` (-5.0K) |

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
| New command needing a larger fixed C64 buffer | Permanent C64 RAM cost only if it expands `$C200-$C5FF`, the overlay slots, resident RAM, or bridge state. | Depends on whether the data can be moved to REU instead. |

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
   command name into `$C4A0`, and rejects an empty name, a too-long name, or a
   leading comma.
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
| Call frame | `$C200` | Command id, parameter count, numeric slots, pointer/count slots, string input buffer. |
| Result frame | `$C300` | Status, error number, value tag, scalar value, string output buffer, array output buffer. |
| Descriptor buffer | `$C480` | One descriptor fetched from REU bank `$44`. |
| Command buffer | `$C4A0` | Uppercase normalized command name. |
| Page buffer | `$C500` | 256-byte staging page for REU handle operations and warm-resume stack buffer. |
| REU call snapshot | Bank `$44`, `$0400` | Copy of the current call frame. |
| REU result snapshot | Bank `$44`, `$0500` | Copy of the current result frame. |
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
| `$1000-$1FFF` | 128 command descriptor slots, 32 bytes each. Slot 13 is `SCRCAP`; slot 128 is `SCRPUT`; zero-filled slots are unused fillers. |
| `$0400` | Current call-frame snapshot. |
| `$0500` | Current result-frame snapshot. |
| `$0600` | Reserved debug ring area. |
| `$0800` | Persistent handle metadata snapshot. |
| `$0900` | Reserved transient heap/staging area. |
| `$0A00` | Saved zero page for ReadyOS suspend/resume. |
| `$0B00` | Saved stack page for ReadyOS suspend/resume. |
| `$8000-$8FFF` | V1 sample data heap: 16 pages of 256 bytes. |

The persistent handle model still supports eight live handles in this change.
Each handle is represented to BASIC as a small integer, while bridge/REU
metadata records the backing bank, start page, page count, type, and page bitmap
state. Type `1` is a byte buffer, and type `2` is a screen text+color buffer.
`BUFFILL` accepts only buffer handles; `BUFFREE` frees any valid handle;
`SCRPUT` accepts only screen handles. The current sample heap uses pages
`$80-$8F` inside bank `$44`; future large or long-lived objects should allocate
additional REU banks and keep the same small handle model.

### Bank `$45`: Packed Command Code

| Offset | Region |
|---:|---|
| `$0000-$04DF` | Low overlay pack copied into `$A900-$ADDF`. |
| `$04E0-$052C` | Hidden overlay pack copied into `$A800-$A84C`. |

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
   ReadyBASIC crunch/execute hooks.
6. BASIC is relocated to `TXTTAB=$1C01` with top at `$A000`.
7. `$1C00`, `$1C01`, and `$1C02` are cleared. `$1C00` is the sentinel byte
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
| Hidden overlay | `$A800-$A84C` | Current `HCRC` worker example. |

Before calling hidden code, ReadyBASIC saves flags, disables interrupts, forces
the low CPU data-direction bits in `$0000` to outputs, saves `$0001`, maps RAM
under BASIC ROM while keeping KERNAL visible, performs the copy or call, then
restores `$0001` and flags. This keeps BASIC ROM/RAM banking explicit and keeps
KERNAL-visible calls safe where needed.

## Invariants

- ReadyBASIC is verified through normal ReadyOS run/profile flows, not by
  loading an individual app directly.
- `BASIC_START` is `$1C01`.
- `$1C00` must remain zero before stored-program `RUN`.
- `RESIDENT` must stay below `$1C00`.
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
| `RESIDENT` | `$1200-$1BF9` | `$09FA` (2554B) |
| `REGSEED` | `$5000-$600F` | `$1010` (4112B) |
| `HIDDEN` | `$A000-$A336` | `$0337` (0.8K) |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` (77B) |
| `LOWPACK` | `$A900-$ADDF` | `$04E0` (1248B) |
| `BRIDGE` | `$C000-$C1C4` | `$01C5` (453B) |

Recent VICE coverage includes:

| Probe | Coverage |
|---|---|
| Plugin command probe | Direct `!` commands, direct `IF 1 THEN !PING`, string/REM safety, leading-comma rejection, `SCRCAP`/`SCRPUT`, slot-128 lookup, wrong-handle-type rejection, screen-handle free, resume. |
| Program probe | Stored line start, colon chains, true/false `IF ... THEN !`, `FOR/NEXT`, strings, REM, DATA, arrays, hidden worker, handles, failure clearing. |
| Full visual verification | Human-watchable command, program, screen-handle, resume, and error coverage. |
| Lifecycle probe | Cold entry, `EXIT`, launcher re-entry, READY-mode redraw. |
| State probe | BASIC variable/string survival and command availability after resume. |
| `rbtest1` probe | Sample program assembled at the relocated BASIC workspace. |
| Large-vars probe | BASIC workspace and variable behavior under heavier state. |
| Cross-app resume stress | ReadyBASIC survives repeated app switches. |
| Second-entry/editor stress | ReadyBASIC survives editor/launcher round trips and later re-entry. |

Some harness wrappers can report a process-level `partial` status even when
every step is `ok` and `FailedStep` is `null`; for ReadyBASIC these were treated
as harness shutdown-status quirks, not command failures.
