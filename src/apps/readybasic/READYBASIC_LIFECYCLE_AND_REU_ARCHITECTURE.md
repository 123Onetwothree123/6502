# ReadyBASIC Lifecycle And REU Architecture Deep Dive

This document describes the current ReadyBASIC REU plugin spine as implemented
in `src/apps/readybasic/readybasic.s` and linked by
`cfg/ready_app_readybasic.cfg`. It focuses on lifespan management: initial
loading, cold setup, command dispatch, REU prestash, overlay execution, result
commit, `EXIT`, and warm suspend/resume.

Current evidence base:

- `src/apps/readybasic/readybasic.s`
- `cfg/ready_app_readybasic.cfg`
- `obj/readybasic.map`
- `src/apps/readybasic/READYBASIC_PLUGIN_ARCH.md`
- `src/apps/readybasic/READYBASIC_PLUGIN_PROGRESS.md`
- `src/apps/readybasic/readybasiclessonslearnt.md`
- `src/apps/readybasic/READYBASIC_MICROMODULE_SYNC.md`

## Executive Summary

ReadyBASIC is a ReadyOS app that hosts a relocated C64 BASIC workspace and adds
a raw-text `!COMMAND args` command spine. It is not currently a custom BASIC
token system. Stored lines preserve `!` command text visibly, and the wedge
recognizes it when BASIC dispatches statements through the `$0308` execute vector.
A tiny crunch hook only handles the `IF ... THEN !COMMAND` edge by delegating to
ROM crunch first, then rewriting the real `THEN` token followed by `!` as
`THEN :!` so the normal statement dispatcher is used.

The design is deliberately lean:

- All ReadyBASIC-specific code is assembler.
- The visible resident core is the only code that calls BASIC ROM helpers.
- Command implementations are packed in REU bank `$45` and copied into a small
  overlay slot only when needed.
- Registry, call-frame, result-frame, handle metadata, and persistent sample
  heap state live in fixed REU bank `$44`.
- BASIC string heap mutation happens only in visible resident code after a
  command succeeds.
- Hidden `$A000` code is used only when the CPU banking contract is explicit and
  restored immediately afterward.

The current map confirms this layout:

| Segment | Runtime range | Size | Role |
|---|---:|---:|---|
| `ENTRY` | `$1000-$1102` | `$0103` (259B) | App entry, cold/warm discriminator, early copies. |
| `RESIDENT` | `$1200-$1BB3` | `$09B4` (2.4K, 2484 exact bytes) | Visible parser, ROM calls, REU DMA wrappers, result commit. |
| `REGSEED` | `$5000-$600F` | `$1010` (4.0K, 4112 exact bytes) | Load-only registry header and 128 command descriptors used on cold seed. |
| `HIDDEN` | `$A000-$A376` | `$0377` (0.9K, 887 exact bytes) | Hidden helper routines under BASIC ROM. |
| `HIDDENPACK` | `$A800-$A84C` | `$004D` (77B) | Hidden worker overlay image, loaded to REU bank `$45`. |
| `LOWPACK` | `$A900-$AF19` | `$061A` (1.5K, 1562 exact bytes) | Banked low overlay image under BASIC ROM, loaded from REU bank `$45`. |
| `BRIDGE` | `$C000-$C19A` | `$019B` (411B) | Persistent bridge/state bytes, no general scratch. |

## Technical Philosophy

ReadyBASIC treats BASIC as a live ROM interpreter with fragile state, not as a
stateless command shell. The main rule is that **BASIC-facing work happens in
visible resident RAM, and worker code stays dumb**.

That rule has several consequences:

- Parameter parsing uses BASIC ROM helpers from visible RAM:
  - `CHKCOM`
  - `FRMNUM`
  - `GETADR`
  - `PTRGET`
- Output variable references are captured before command execution.
- Output variables are cleared before command execution so failure does not show
  stale data.
- Overlays write only a compact result frame.
- The resident core commits results after success, including string heap writes.
- Hidden workers do not allocate BASIC strings.
- REU stores code and metadata, but the live BASIC interpreter state remains in
  C64 RAM and is protected by the ReadyBASIC suspend/resume snapshot.

The V1 spine intentionally avoids a few attractive but expensive abstractions:

- No generic object/value VM.
- No nested value serialization.
- No per-command REU bank.
- No command-per-bank storage.
- No private command token or custom lister yet.
- Only a tiny post-ROM-crunch `THEN !` normalizer is installed.
- No generalized signature bytecode interpreter yet; signatures are dispatched
  by compact hand-written routines.

## Full RAM Layout

The ReadyOS app working region is `$1000-$C5FF`; `$C600-$C7FF` is shared
ReadyOS REU metadata and `$C800-$C9FF` is shim ABI territory. ReadyBASIC must
live inside that contract while also hosting BASIC.

```mermaid
flowchart TB
  A["$1000-$1102 ENTRY<br/>load entry and cold/warm cookie"]
  B["$1200-$1BB3 RESIDENT<br/>visible parser, vector hook, REU DMA, commit"]
  C["$1C00 SENTINEL<br/>must be zero for BASIC RUN"]
  D["$1C01-$9FFF BASIC WORKSPACE<br/>33789 free bytes / 33.0K"]
  E["$2800-$3FFF CMDPACK LOAD IMAGE<br/>low and hidden overlay seed bytes before cold prestash"]
  F["REU $44:$0A00-$0BFF RUNTIME SNAPSHOT<br/>zero page and stack / 0.5K"]
  G["$C200-$C5FF SHARED FRAMES<br/>call/result/descriptor/name/page buffers / 1.0K"]
  I["$C280-$C5F6 HIDDEN SHADOW<br/>refreshed on EXIT / 0.9K"]
  J["$A000-$A376 HIDDEN HELPER<br/>runs under BASIC ROM RAM"]
  K["$A800-$A84C HIDDEN OVERLAY<br/>ZHIDDENRAM worker copied from REU bank $45"]
  O["$A900-$AF19 LOW OVERLAY<br/>low workers under BASIC ROM RAM"]
  L["$C000-$C19A BRIDGE STATE<br/>magic, saved vectors, overlay vars, handle scratch, debug"]
  M["$C600-$C7FF READYOS REU METADATA<br/>only bank ownership tags here"]
  N["$C800-$C9FF SHIM ABI<br/>ReadyOS jump table/data, not app RAM"]

  A --> B --> C --> D --> G
  G --> F --> J --> K --> O --> L --> M --> N
```

### Load Image Versus Runtime Image

The PRG load address is `$1000`. The linker emits a larger load image than the
runtime-visible resident core:

| Load-time range | Purpose |
|---:|---|
| `$1000-$11FF` | Entry image, including entry-local warm cookie. |
| `$1200-$1BFF` | Resident core image. |
| `$1C00-$27FF` | Padding in the PRG load image; after cold setup, BASIC uses `$1C01+`. |
| `$2800-$3FFF` | Command pack seed bytes, copied to REU bank `$45` only on cold entry. |
| `$4000+` | Hidden helper seed bytes, copied to `$A000` and the visible `$C280` shadow. |
| `$4800+` | Bridge seed bytes, copied to `$C000`. |
| `$5000-$600F` | Registry seed bytes, copied to REU bank `$44` only on cold entry. |

After cold setup, BASIC owns `$1C01-$9FFF`. This is why warm resume must **not**
try to reread the load-only seed tables at `$2800+`, `$4000+`, `$4800+`, or
`$5000+`: that memory may now be BASIC program or variable storage.

### Cold-Load Versus Steady-State Ownership

ReadyBASIC has two different memory pictures that must not be merged:

| Stage | What is in C64 RAM | What counts against BASIC free bytes |
|---|---|---|
| ReadyOS load | The PRG load image includes `CMDPACK` at `$2800-$3FFF`, `HIDLOAD` at `$4000+`, `BRLOAD` at `$4800+`, and `REGSEED` at `$5000-$600F`. | Nothing user-visible yet; BASIC has not been handed `$1C01-$9FFF`. |
| Cold seed | Hidden helper code copies the registry/header to REU bank `$44`, copies packed command code to REU bank `$45`, and copies live hidden/bridge code to `$A000/$C000`. | The load-only ranges are still temporary seed bytes. |
| Ready prompt | BASIC owns `$1C01-$9FFF`, including the former load-image addresses. `CMDPACK`, `HIDLOAD`, `BRLOAD`, and `REGSEED` must be treated as gone. | Empty BASIC free bytes are `33789`. |
| Command execution | Packed command code is fetched from REU bank `$45` into `$A800/$A900` under BASIC ROM RAM, then control returns to resident commit code. | No per-command BASIC workspace loss. |

`CMDPACK` is therefore both visually inside the BASIC address span and
steady-state free. The current reservation is `$1800` (6.0K); the implemented
packed content is `LOWPACK` `$061A` plus `HIDDENPACK` `$004D`, about 1.6K. That
reserved command-pack area can grow toward 6.0K during cold load without
changing `BASIC_START`, `BASIC_LIMIT`, or the `33789` empty BASIC free-byte
measurement, because it is prestashed to REU before BASIC owns the range.

There are two separate limits:

| Layer | Current size | What it means |
|---|---:|---|
| C64 `CMDPACK` cold-load window | `$1800` / 6.0K | The linker currently places the initial packed command seed bytes at `$2800-$3FFF` before cold setup copies them out. This is a seed window, not the architectural command-code ceiling. |
| REU bank `$45` command-code bank | `$10000` / 64.0K | The current descriptor format uses 16-bit offsets/sizes into this bank, so one code bank can address up to 64K of packed command bodies. Current used space is `$0667` / 1.6K, leaving `$F999` / 62.4K in bank `$45`. |
| Beyond one code bank | More than 64K | Requires a descriptor/loader extension for additional code banks or a bank-selection field. That is future architecture, not the current single-bank ABI. |

So, with the current descriptor and REU command-code architecture, packed command
code can grow to one 64K REU code bank. The current PRG/load linker only seeds a
6.0K `CMDPACK` window today; filling more of bank `$45` would require expanding
or adding cold-load seed windows and copying them before BASIC owns the memory.
That kind of seed expansion should still be reclaimed and should not reduce
steady-state BASIC free bytes.

The proportional HTML view uses these exact subranges inside the raw
`$1C01-$9FFF` span (`$83FF`, 33.0K, 33791 exact bytes):

| Subrange | Cold-load role | Hex size | Display size | Exact bytes |
|---|---|---:|---:|---:|
| `$1C01-$27FF` | Future BASIC bytes before `CMDPACK`. | `$0BFF` | 3.0K | 3071 |
| `$2800-$3FFF` | `CMDPACK` reserved cold-load image. | `$1800` | 6.0K | 6144 |
| `$4000-$4376` | `HIDLOAD` seed. | `$0377` | 0.9K | 887 |
| `$4377-$47FF` | Padding / future BASIC after cold seed. | `$0489` | 1.1K | 1161 |
| `$4800-$499A` | `BRLOAD` seed. | `$019B` | 411B | 411 |
| `$499B-$4FFF` | Padding / future BASIC after cold seed. | `$0665` | 1.6K | 1637 |
| `$5000-$600F` | `REGSEED` header plus 128 descriptors. | `$1010` | 4.0K | 4112 |
| `$6010-$9FFF` | Future BASIC bytes after `REGSEED`. | `$3FF0` | 16.0K | 16368 |

Inside `CMDPACK`, the current packed content is `LOWPACK` `$2800-$2E19`
(`$061A`, 1.5K, 1562 exact bytes), `HIDDENPACK` `$2E1A-$2E66`
(`$004D`, 77B), and reserved room `$2E67-$3FFF` (`$1199`, 4.4K,
4505 exact bytes).

## REU Layout

ReadyBASIC reserves two fixed REU banks:

- Bank `$44`: ReadyBASIC common/system storage.
- Bank `$45`: packed command-code storage.

The mirrored ReadyOS type constants are:

| Type | Value | Meaning |
|---|---:|---|
| `REU_RB_CORE` | `14` | ReadyBASIC core/system bank. |
| `REU_RB_CODE` | `15` | ReadyBASIC packed command-code bank. |

ReadyBASIC marks these in the ReadyOS REU allocation table at `$C600+$44` and
`$C600+$45`. It does not treat `$C600` as general app scratch.

### Bank `$44`: Common/System Bank

```mermaid
flowchart TB
  H["$0000 Header<br/>RBPL, version, descriptor count, frame offsets"]
  D["$1000-$1FFF Descriptors<br/>128 x 32-byte command slots"]
  C["$0400 Call frame snapshot<br/>copy of $C200 frame"]
  R["$0500 Result frame snapshot<br/>copy of $C300 frame"]
  DBG["$0600 Debug ring reserved<br/>parser/command breadcrumbs"]
  HM["$0800-$09FF Handle directory<br/>128 x 4-byte descriptors"]
  ZP["$0A00 Zero-page snapshot<br/>ReadyOS suspend/resume"]
  ST["$0B00 Stack-page snapshot<br/>ReadyOS suspend/resume"]
  BM["$0C00 Heap bitmap<br/>192 pages tracked in REU"]
  RS["$2000-$3FFF Reserved common space<br/>future typed metadata"]
  DATA["$4000-$FFFF Typed handle heap<br/>48KB / 192 pages"]

  H --> C --> R --> DBG --> HM --> ZP --> ST --> BM --> D --> RS --> DATA
```

Exact bank `$44` suballocation sizes:

| Offset range | Role | Hex size | Display size | Exact bytes |
|---|---|---:|---:|---:|
| `$0000-$000F` | Header. | `$0010` | 16B | 16 |
| `$0010-$03FF` | Reserved common/system metadata space before frames. | `$03F0` | 1.0K | 1008 |
| `$0400-$04FF` | Call frame snapshot. | `$0100` | 256B | 256 |
| `$0500-$05FF` | Result frame snapshot. | `$0100` | 256B | 256 |
| `$0600-$07FF` | Reserved REU debug ring. | `$0200` | 0.5K | 512 |
| `$0800-$09FF` | 128-handle directory, 4 bytes per descriptor. | `$0200` | 0.5K | 512 |
| `$0A00-$0AFF` | Zero-page snapshot. | `$0100` | 256B | 256 |
| `$0B00-$0BFF` | Stack-page snapshot. | `$0100` | 256B | 256 |
| `$0C00-$0FFF` | Heap bitmap page; 192B used, remainder reserved. | `$0400` | 1.0K | 1024 |
| `$1000-$1FFF` | 128 command descriptors, 32 bytes each. | `$1000` | 4.0K | 4096 |
| `$2000-$3FFF` | Reserved common/system expansion space. | `$2000` | 8.0K | 8192 |
| `$4000-$FFFF` | Typed handle heap, 192 pages. | `$C000` | 48.0K | 49152 |

The command descriptor table at `$1000-$1FFF` is intentionally sparse:

| Descriptor range | REU offset | Role | Slots | Size |
|---|---:|---|---:|---:|
| Slots 1-14 | `$1000-$11BF` | Current front commands from `ZECHO1` through `SCRCAP`. | 14 | `$01C0` / 448B |
| Slots 15-127 | `$11C0-$1FDF` | Zero-filled filler descriptors reserved for future commands. | 113 | `$0E20` / 3.5K / 3616 exact bytes |
| Slot 128 | `$1FE0-$1FFF` | `SCRPUT`, placed at the end to prove full-table lookup. | 1 | `$0020` / 32B |

`SCRCAP` is adjacent to the current front command set in slot 14. `SCRPUT` is
separated from it by 113 empty filler slots, so the visual/test coverage proves
that ReadyBASIC fetches descriptor pages and scans the whole 128-slot registry.

Persistent buffers use the typed heap in bank `$44`, pages `$40-$FF`. Each
handle records a bank, starting page, page count, and type in the REU-backed
directory. The page bitmap is also canonical in REU, so resident/bridge RAM only
needs the current descriptor scratch and a 256-byte page buffer. Type `1` is a
byte buffer, and type `2` is a screen text+color buffer.

### Bank `$45`: Packed Command-Code Bank

```mermaid
flowchart LR
  LP["$0000-$0619 Low overlay pack<br/>copied into $A900-$AF19"]
  HP["$061A-$0666 Hidden overlay pack<br/>copied into $A800-$A84C"]
  LP --> HP
```

The descriptor stores offsets and sizes inside bank `$45`. Normal low commands
copy only their own slice. Heap commands currently copy the whole low pack
because their wrappers call shared allocator helper routines in the same packed
low segment.

Exact bank `$45` suballocation sizes:

| Offset range | Role | Hex size | Display size | Exact bytes |
|---|---|---:|---:|---:|
| `$0000-$0619` | Low overlay pack fetched into `$A900-$AF19`. | `$061A` | 1.5K | 1562 |
| `$061A-$0666` | Hidden overlay pack fetched into `$A800-$A84C`. | `$004D` | 77B | 77 |
| `$0667-$FFFF` | Available packed-code bank space. | `$F999` | 62.4K | 63897 |

## Descriptor ABI

Each command descriptor is 32 bytes:

| Offset | Field |
|---:|---|
| `0` | Command id. |
| `1` | Flags: low, hidden, or both. |
| `2-3` | Low code offset in REU bank `$45`. |
| `4-5` | Low code size. |
| `6-7` | Hidden code offset in REU bank `$45`. |
| `8-9` | Hidden code size. |
| `10-11` | Low entry offset from `$A900`. |
| `12-13` | Hidden entry offset from `$A000`. |
| `14` | Signature id. |
| `15` | Uppercase command-name length. |
| `16-31` | Uppercase command-name bytes, zero padded. |

The current descriptors are seeded from `REGSEED` during cold boot and copied
to bank `$44` offset `$1000`. Lookup fetches 256-byte pages, scans eight
descriptors per page, and treats zero-filled filler descriptors as empty slots.

## Cold Boot Lifecycle

```mermaid
flowchart TD
  L["ReadyOS launcher loads readybasic.prg at $1000"]
  E["ENTRY checks entry-local magic"]
  C["Cold path"]
  H1["Map RAM under BASIC ROM"]
  H2["Copy hidden helper seed $3000 -> $A000"]
  H3["Copy hidden helper seed -> $C280 shadow"]
  B1["Copy bridge seed $3800 -> $C000"]
  RB["Jump to rb_boot"]
  V["Reset KERNAL/BASIC vectors"]
  I["Install $0308 execute hook"]
  W["Initialize BASIC workspace at $1C01"]
  S["Cold seed REU banks $44/$45"]
  P["Clear screen, lowercase VIC mode, banner"]
  R["Enter BASIC_READY"]

  L --> E --> C --> H1 --> H2 --> H3 --> B1 --> RB --> V --> I --> W --> S --> P --> R
```

The cold setup performs these important operations:

1. It copies hidden helper code before BASIC owns `$1C01+`.
2. It stores a visible shadow copy at `$C280` because `$A000` code cannot be trusted
   after a ReadyOS app switch.
3. It copies bridge state to `$C000`.
4. It resets KERNAL and BASIC vectors, then installs only the execute vector
   hook at `$0308/$0309`.
5. It relocates BASIC:
   - `TXTTAB = $1C01`
   - `VARTAB = ARYTAB = STREND = $1C03`
   - `FRETOP = MEMSIZ = $A000`
   - KERNAL memory bottom/top = `$1C00/$A000`
6. It clears `$1C00`, `$1C01`, and `$1C02`. The `$1C00` byte is a hard
   invariant: C64 BASIC `RUN` expects the byte before `TXTTAB` to be zero.
7. It seeds REU bank `$44` and `$45`.
8. It draws the ReadyBASIC banner and enters `BASIC_READY`.

## Warm Resume Lifecycle

```mermaid
flowchart TD
  R0["ReadyOS restores app window and jumps to $1000"]
  E["ENTRY sees entry-local warm magic"]
  RH["Map RAM under BASIC ROM"]
  RS["Copy $C280 shadow -> $A000 hidden helper"]
  RB["Jump to rb_boot"]
  M["Bridge magic says READY or RUN"]
  IV["Install $0308 execute hook"]
  MK["Re-mark REU bank ownership"]
  SKIP["Do not reread load-only CMDPACK/REGSEED"]
  REST["restore_basic_runtime_state"]
  OK{"Runtime magic and line chain ok?"}
  READY["READY resume:<br/>console reset, banner, prompt, BASIC_READY"]
  RUN["RUN resume candidate:<br/>restore SP, BASIC_NEXT_STMT"]
  FALL["Fallback:<br/>empty workspace and BASIC_READY"]

  R0 --> E --> RH --> RS --> RB --> M --> IV --> MK --> SKIP --> REST --> OK
  OK -->|yes, mode READY| READY
  OK -->|yes, mode RUN| RUN
  OK -->|no| FALL
```

Warm resume is intentionally different from cold boot:

- It restores the hidden helper from `$C280`, not from the old load image.
- It reinstalls ReadyBASIC-owned vectors.
- It re-marks REU ownership for `$44/$45`.
- It does **not** rebuild the registry/code banks from load-only RAM.
- It restores BASIC stack and zero page from REU bank `$44` offsets `$0A00/$0B00`.
- It resets KERNAL memory bounds, but it does not reset live BASIC pointers such
  as `FRETOP`, `VARTAB`, `ARYTAB`, or `STREND`.
- READY-mode resume clears/redraws the screen so the launcher menu does not
  remain visible underneath a BASIC prompt.

## EXIT And Suspend Management

The supported V1 return path is manual prompt `EXIT`. The execute hook detects
`EXIT` before falling back to ROM BASIC.

```mermaid
flowchart TD
  X["User enters EXIT at ReadyBasic prompt"]
  D["cmd_exit checks TXTPTR<br/>below BASIC_START means READY-mode return"]
  M["Store bridge and entry magic<br/>READY or RUN candidate"]
  S["call_hidden_save_state"]
  Z["Save zero page $0000-$00FF -> REU $44:$0A00"]
  ST["Save stack $0100-$01FF -> REU $44:$0B00"]
  META["Save SP, mode, line-chain guards -> bridge metadata"]
  V["Restore BASIC/KERNAL page-3 vectors"]
  SHIM["Jump SHIM_RETURN $C80C"]
  L["Launcher regains control"]

  X --> D --> M --> S --> Z --> ST --> META --> V --> SHIM --> L
```

The vector restore is not optional. Page-3 vectors are global machine state, not
ReadyOS app-private RAM. If ReadyBASIC yielded with `$0308` still pointing into
its resident core, the launcher or another app could dispatch through stale
ReadyBASIC state.

The runtime snapshot lives here:

| Range | Meaning |
|---:|---|
| REU `$44:$0A00-$0AFF` | Saved zero page. |
| REU `$44:$0B00-$0BFF` | Saved hardware stack page. |
| Bridge metadata | Runtime magic, saved SP, resume mode, line-chain validation. |
| `$C280-$C5B6` | Hidden helper shadow, refreshed during `EXIT`. |

## Raw ! Dispatch

ReadyBASIC installs the BASIC crunch and execute vectors:

- Save originals from `$0304-$0309`.
- Install `rb_crunch` into `$0304/$0305`.
- Install `rb_execute` into `$0308/$0309`.
- Leave the list vector forwarding to ROM behavior for V1.

The dispatch rule is:

1. Crunch delegates to ROM BASIC, then inserts `:` before `!` only after a
   tokenized `THEN`.
2. Execute peeks at the next non-space byte without advancing `TXTPTR`.
3. If it is not `!` or `EXIT`, tail-call the saved ROM execute vector.
4. If it is `!`, advance through the raw bang and parse a ReadyBASIC
   command name.
5. If it is `EXIT`, take the ReadyOS yield path.

This is why `LIST` still shows `!COMMAND args`: there is no private token to
hide or pretty-print.

The command name parser normalizes:

- Host/lowercase ASCII command bytes to uppercase.
- Shifted uppercase/PETSCII-like `$C1-$DA` bytes by subtracting `$80`.
- A couple of BASIC token bytes (`FN`, `FRE`) if ROM tokenization produces them
  inside a name.

That last detail exists because ASCII/lowercase/PETSCII/tokenized BASIC input
is a real source of C64 wedge bugs.

## Command Execution Pipeline

```mermaid
sequenceDiagram
  participant BASIC as BASIC ROM dispatch
  participant RES as ReadyBASIC resident
  participant R44 as REU bank $44
  participant R45 as REU bank $45
  participant LOW as Low overlay $A900
  participant HID as Hidden overlay $A800

  BASIC->>RES: $0308 execute vector
  RES->>RES: Match raw "!"
  RES->>RES: Normalize command name
  RES->>R44: Fetch descriptors one at a time from $0100
  R44-->>RES: Descriptor -> $C480
  RES->>RES: Parse signature with BASIC ROM helpers
  RES->>RES: Clear output variables
  RES->>R44: Stash call frame $C200 -> $0400
  alt Low command
    RES->>R45: Fetch code slice
    R45-->>LOW: Copy into $A900 slot
    RES->>LOW: JSR command entry
    LOW-->>RES: Result frame at $C300
  else Hidden command
    RES->>R45: Fetch hidden code slice
    R45-->>HID: Copy into RAM under BASIC ROM
    RES->>HID: Call with RAM under BASIC visible
    HID-->>RES: Result frame at $C300
  end
  RES->>R44: Stash result frame $C300 -> $0500
  RES->>RES: Commit result to BASIC variable/string/array
  RES-->>BASIC: BASIC_NEXT_STMT
```

### Shared Frames In Low RAM

| Frame | Address | Contents |
|---|---:|---|
| Call frame | `$C200` | Command id, parameter count, numeric slots, pointer/count slots, string buffer. |
| Result frame | `$C300` | Status, error, value tag, scalar value, string buffer, array buffer. |
| Descriptor buffer | `$C480` | One 32-byte descriptor fetched from REU bank `$44`. |
| Command buffer | `$C4A0` | Normalized command name. |
| Page buffer | `$C500` | 256-byte descriptor/bitmap page buffer for handle operations and warm-resume stack staging. |

The call and result frames are also mirrored to REU bank `$44` offsets `$0400`
and `$0500`. This gives crash/debug visibility and gives future worker models a
stable mailbox shape.

## Parameter And Result Semantics

V1 supports the sample command signatures directly:

| Input kind | Implementation rule |
|---|---|
| Numeric expression | `CHKCOM`, `FRMNUM`, `GETADR`; stores 16-bit value from `LINNUM`. |
| Integer output variable | `PTRGET`, require numeric/integer, clear two bytes before execution. |
| String input | String variable descriptor or quoted literal, max 64 bytes copied to call frame. |
| String output variable | `PTRGET`, require string, clear descriptor before execution. |
| Integer array input | Require explicit base element and count, e.g. `A%(0),N`. |
| Integer array output | Require explicit base element and count from prior argument. Clears destination first. |
| REU handle | V1 handle is represented as an integer variable/value. |

Result tags are:

| Tag | Meaning |
|---:|---|
| `0` | none |
| `1` | integer |
| `2` | string |
| `3` | integer array |

If `RF_STATUS` is nonzero, ReadyBASIC prints `?RB ERROR n` and returns to
`BASIC_READY`. On a clean result, resident code commits to the captured output
reference.

String output is special: overlays stage bytes into `RF_STR_BUF`, then resident
code allocates from the BASIC string heap by lowering `FRETOP`. This is the
correct side of the contract because only resident visible code should mutate
BASIC's string heap.

## Command Inventory

| Command | Code placement | REU code bytes copied | Parameters | Result behavior |
|---|---|---:|---|---|
| `!ZECHO1 OUT%` | Low overlay at `$A900+$0000` | `$0015` (21B) | output int | Returns `1`. |
| `!ZADD16 A,B,OUT%` | Low overlay at `$A900+$0015` | `$001E` (30B) | two numeric expressions, output int | Returns 16-bit sum. |
| `!UPPER S$,OUT$` | Low overlay at `$A900+$0033` | `$003B` (59B) | string variable or literal, output string | Uppercases staged bytes. |
| `!LOWER S$,OUT$` | Low overlay at `$A900+$006E` | `$003B` (59B) | string variable or literal, output string | Lowercases staged byte values; tests assert `ASC()` bytes because C64 display case is charset-dependent. |
| `!ZHIDDENRAM S$,OUT%` | Hidden overlay at `$A800` | `$004D` (77B) | string variable or literal, output int | Sums uppercase bytes. |
| `!ZSUMNUMARRAY A%(0),COUNT,OUT%` | Low overlay at `$A900+$00A9` | `$0044` (68B) | integer array base/count, output int | Sums integer array values. |
| `!ZRANGENUMARRAY START,COUNT,A%(0)` | Low overlay at `$A900+$00ED` | `$003D` (61B) | start/count, output array | Stages consecutive integers. |
| `!BUFNEW LEN,H%` | Low overlay entry `$012A` | `$061A` (1.5K) | length, output handle | Allocates persistent buffer pages in bank `$44`. |
| `!BUFFILL H%,BYTE` | Low overlay entry `$012E` | `$061A` (1.5K) | buffer handle, byte | Fills buffer handle pages using `$C500` page buffer. |
| `!BUFFREE H%` | Low overlay entry `$0132` | `$061A` (1.5K) | handle | Frees any valid handle type and clears metadata. |
| `!ZTEMPSCRATCH LEN,OUT%` | Low overlay entry `$0136` | `$061A` (1.5K) | length, output int | Allocates then frees pages, returns page count. |
| `!ZFAIL CODE,OUT%` | Low overlay at `$A900+$013A` | `$001B` (27B) | code, output int | Clears output first, then returns `?RB ERROR code`. |
| `!FREEMEM` | Low overlay at `$A900+$0155` | `$0016` (22B) | none | Prints live free BASIC bytes and refreshes the header. |
| `!SCRCAP H%` | Slot 14; low overlay entry `$016B` | `$061A` (1.5K) | output screen handle | Captures screen text and color RAM into a type-2 handle. |
| `!SCRPUT H%` | Slot 128; low overlay entry `$0194` | `$061A` (1.5K) | screen handle | Restores screen text and color RAM after type validation. |

The heap-oriented commands copy the full `$061A` low pack because allocator,
REU descriptor, bitmap, and screen-copy helpers live in the same overlay pack.
That is an implementation choice to keep resident RAM lean; a later pass could
split a smaller allocator resident helper or use finer overlay slices.

## Persistent Handle Model

ReadyBASIC supports up to 128 live handles and a 48KB typed heap.

```mermaid
flowchart LR
  BASIC["BASIC H% handle<br/>small integer 1-128"]
  SCRATCH["Bridge scratch<br/>current bank/page/pages/type"]
  DIR["REU bank $44 $0800-$09FF<br/>128 handle descriptors"]
  BITMAP["REU bank $44 $0C00<br/>192-page bitmap"]
  DATA["REU bank $44 $4000-$FFFF<br/>48KB typed heap"]

  BASIC --> SCRATCH --> DIR
  SCRATCH --> BITMAP --> DATA
```

`BUFNEW` converts byte length to 256-byte pages, finds contiguous free pages,
records type-1 metadata, and returns a one-based handle. `BUFFILL` accepts only
type-1 buffer handles, fills `$C500` with the byte, and stashes it page by page
into bank `$44` at page offsets `$40-$FF`. `SCRCAP` creates a type-2 handle and
stashes screen text plus color RAM; `SCRPUT` validates type `2` before restore.
`BUFFREE` clears both the handle descriptor and bitmap for any valid handle type.
`ZTEMPSCRATCH` proves temporary allocation by finding pages without persisting a
live descriptor.

This handle model is the right direction for future commands that maintain
screen buffers, network buffers, caches, or large results. The current fixed
bank heap is intentionally typed and compact; larger future resources can add
extra banks while keeping the same small BASIC-visible handle.

## Hidden Code And Banking Contract

ReadyBASIC uses two kinds of hidden code:

- Hidden helper at `$A000-$A336`.
- Hidden worker overlay at `$A800-$A84C`.

Before calling hidden code, ReadyBASIC:

1. Saves flags.
2. Disables interrupts.
3. Forces the low CPU data-direction bits in `$0000` to outputs.
4. Saves `$0001`.
5. Maps RAM under BASIC ROM while keeping KERNAL visible.
6. Performs the copy or call.
7. Restores `$0001`.
8. Restores flags.

That discipline matters because `$0001` is only meaningful when `$0000` drives
the banking bits as outputs. It also matters because hidden code that still uses
KERNAL-visible helpers must not map KERNAL out.

## What Must Stay True

These invariants are the current safety rails:

- ReadyBASIC must be booted through normal ReadyOS profile/run flow, not as a
  standalone app.
- `BASIC_START` stays `$1C01`.
- `$1C00` stays zero before stored-program `RUN`.
- `RESIDENT` stays below `$1C00`.
- `BRIDGE` stays below `$C200`, leaving `$C200-$C5FF` for shared frames.
- `$C600-$C7FF` is ReadyOS REU metadata, not ReadyBASIC scratch.
- `$C800-$C9FF` remains shim ABI.
- Warm resume must restore `$A000` from `$C280` before hidden helper calls.
- Warm resume must not reset `FRETOP`, `VARTAB`, `ARYTAB`, or `STREND`.
- ReadyBASIC-owned vectors must be restored before yielding to ReadyOS.
- Non-ReadyBASIC BASIC statements must tail-call the original `$0308` vector
  without mutated `TXTPTR`.
- String heap writes happen only in resident visible code.
- Acceptance re-entry uses launcher menu navigation, not `CTRL+3`.

## Current Verification

The current full visual suite is:

```sh
READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh
```

Latest documented pass on the REU-backed 128-handle branch:

- Run dir:
  `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154424`
- Result: 133/133 concrete steps, `FailedStep: null`, no degraded steps; the
  wrapper reports `partial`, matching the current no-failed-step harness
  behavior.
- It validates:
  - Cold ReadyOS boot with `READYOS_CONFIG_RUN_FIRST=readybasic`.
  - Direct-mode scalar, string, hidden worker, array, REU handle, temp heap,
    128-handle edge, 48KB heap edge, screen heap exhaustion, failure, and
    unknown-command paths.
  - Menu-based launcher round trip and ReadyBasic redraw.
  - BASIC variable/string state plus registry survival after resume.
  - Stored-program `LIST` and `RUN` for the major command families.

## Design Notes For Future Expansion

The current architecture can scale to many commands if the command registry and
code pack remain compact:

- Keep command code packed inside banks, not one bank per command.
- Keep descriptors fixed-size for v1.
- Move large command-private state to dynamic REU banks referenced by small
  BASIC integer handles.
- Consider moving reusable allocator helpers into a separate resident or common
  overlay only if it reduces total copied bytes without bloating resident RAM.
- Add a real crunch/list token path only after its register, length, and lister
  contracts have a dedicated probe.
- Treat program-line `EXIT` resume as future work; manual prompt `EXIT` is the
  proven path.
- Any full-system command that bypasses ReadyBasic's normal completion path will
  need an explicit suspend/resume ABI and likely shim/launcher coordination.
