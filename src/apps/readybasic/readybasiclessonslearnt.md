# ReadyBASIC Lessons Learnt

This is the running lab notebook for ReadyBASIC. Keep entries small, falsifiable,
and updated when a hypothesis turns out to be wrong. The goal is to preserve the
actual C64/ReadyOS evidence trail rather than a pile of confident guesses.

## Current Model

- ReadyBASIC is a ReadyOS-native PRG host for BASIC, not a normal C64 BASIC PRG.
- The app PRG loads at `$1000` and must obey the ReadyOS app/shim window:
  `$1000-$C5FF` is app-owned, `$C600-$C9FF` is reserved metadata/shim space.
- BASIC programs are data inside the host. The scoped BASIC workspace is
  currently `$1201-$95FF`, with save/load relocating line links to/from the
  standard C64 BASIC `$0801` format.
- `$9600-$99FF` is reserved for ReadyBASIC suspend metadata, zero-page snapshot,
  stack snapshot, saved SP, and line-chain guards.
- Hidden services live under BASIC ROM RAM at `$A000-$BFFF` and visible
  trampolines/state/mailbox live at `$C000-$C5FF`.
- A shadow copy of the hidden helper image lives at `$9A00-$9FFF`, inside the
  ReadyOS app snapshot window but above BASIC's managed top-of-memory. Warm
  entry restores `$A000` from that shadow before using hidden helpers.

## Proven

### 6502/C64 Assembly Discipline That Mattered Here

- Treat `$0000` and `$0001` as a pair. `$0001` only drives memory banking bits
  whose data-direction bits in `$0000` are configured as outputs. ReadyOS can
  leave `$0000` in a state that makes a normal-looking `$01` value ineffective.
- Do not map out KERNAL ROM while calling KERNAL routines. Hidden helper calls
  that only touch RAM can use RAM-under-BASIC-ROM mapping; helpers that call
  `SETLFS`, `OPEN`, `CHRIN`, `CHROUT`, etc. must keep KERNAL visible.
- Keep interrupt state explicit around banking changes. Save flags with `PHP`,
  `SEI` before remapping, restore `$01`, then `PLP`.
- Do not trust registers or flags after probing ROM BASIC unless the ROM
  contract says they are yours to change. Wedge fallbacks must leave `TXTPTR`,
  accumulator/flags expectations, and line length behavior intact.
- Page-zero BASIC pointers are live interpreter state, not cache. `TXTTAB`,
  `VARTAB`, `ARYTAB`, `STREND`, `FRETOP`, `MEMSIZ`, `TXTPTR`, and the BASIC
  line-link chain must agree before entering ROM BASIC.
- Global vectors in page 3 are outside the ReadyOS app snapshot. Restore owned
  vectors before yielding through the shim, and reinstall only after app memory
  is restored.

### Cold/Warm Entry Must Not Trust `$C000` First

Cold launcher loads can leave stale bytes in `$C000-$C5FF`. A cold/warm decision
based first on bridge magic at `$C000` can falsely take a resume path before the
bridge has been copied into place.

Current rule: use an entry-local cookie in the `$1000` entry segment as the
first discriminator. A disk load resets that cookie from the PRG image; a REU
resume preserves it in the app snapshot.

### `$01` Restore Must Happen Last

Hidden restore state under `$A000` is only readable while RAM is mapped under
BASIC ROM. Restoring saved `$0001` too early can make BASIC ROM visible again
mid-copy, so the rest of the restore reads ROM instead of the hidden buffer.

Current rule: keep RAM-under-ROM forced while restoring, copy stack and zero page
first, and restore `$0000/$0001` last.

### Hidden `$A000` Helpers Are Outside The ReadyOS Snapshot

Proven by the `EXIT` resume crash. The ReadyOS shim snapshots `$1000-$C5FF`
when an app returns to the launcher. ReadyBASIC's hidden helper code under
`$A000-$BFFF` is not part of that transfer, so warm entry cannot assume it is
still valid after the launcher or another app has run.

Current rule: reserve `$9A00-$9FFF` as a shadow image, lower BASIC's memory
limit to `$9A00`, and restore `$A000` from the shadow on every warm entry.
`EXIT` refreshes the shadow before jumping to `$C80C`.

### `$0000` DDR Is Part Of The Banking Contract

Proven on 2026-05-09 with the binary-monitor probe. ReadyOS/launcher state left
`$0000 == $12`, so writing a value such as `$36` to `$0001` did not reliably
drive the LORAM banking bit. Hidden calls intended to run from RAM under BASIC
ROM could accidentally execute BASIC ROM bytes around `$A000` instead of
ReadyBASIC's helper code.

Current rule: before every hidden-helper call, force the low three bits of
`$0000` to outputs. Non-KERNAL hidden helpers use `$01 & $FD` so HIRAM makes
RAM visible under `$A000`; KERNAL-calling file helpers use `$01 & $FE` so KERNAL
ROM stays callable.

### `CHRIN` Hooks Must Preserve Carry Semantics

BASIC checks carry after KERNAL input calls. The VICE C64 ROM disassembly shows
the BASIC/KERNAL wrapper around `CHRIN` branches to the BASIC error path if
carry is set after `$FFCF`.

Bug seen: `print "hello"` executed, then reported `?C error`. That was caused by
ReadyBASIC calling original `CHRIN`, comparing the returned byte with hotkeys,
and returning with the carry flag left by `CMP`.

Current rule: if original `CHRIN` returns carry set, return carry set unchanged;
for ordinary successful input, explicitly return carry clear.

### Gate Prompt Hooks By Current Input Device

`DFLTN` at `$99` is the current/default input device. Value `0` means keyboard.
ReadyBASIC must only treat bytes as app navigation when `DFLTN == 0`; otherwise
file/device input used by BASIC or `RB 10/RB 11` must pass through untouched.

### BASIC Prompt `CHRIN` Does Not Return Every Key

At the READY prompt, KERNAL `CHRIN` enters the screen editor and usually returns
only after Return, not after every keypress. That means a wrapper around `$0324`
can be too late to see `CTRL+B` or `F2`.

Revised rule: do not busy-wait in the `$0324` `CHRIN` vector before ROM's screen
editor runs. The screen editor owns cursor blink, logical-line editing, keyboard
buffer draining, and Return handling. Prompt-level ReadyOS navigation needs a
deeper editor-safe hook or a later explicit command, not a pre-editor blocking
loop.

### ReadyBASIC Must Restore Global Vectors Before Shim Yield

ReadyOS snapshots the app window `$1000-$C5FF`, but BASIC/KERNAL vectors in page
3 are global machine state outside that snapshot. If ReadyBASIC yields through
`$C80C/$C80F` with `$0304/$0306/$0308` or `$0324/$032A` still pointing into its
bridge, the launcher or next app can run with vectors into stale app memory.

Current rule: cold entry resets KERNAL I/O vectors with `$FF8A` and BASIC
vectors with `$E453`, saves the originals once, installs ReadyBASIC vectors only
while active, and restores the originals before every shim yield.

### Do Not Replace The BASIC Error Vector With `$A43A`

The stock `$0300` vector points at `$E38B`, not directly at `$A43A`. `$E38B`
checks for negative `X` values used by the ROM STOP/end-of-direct-command path
and returns to READY when appropriate. Pointing `$0300` directly at `$A43A`
bypasses that wrapper and can turn a successful direct command into a spurious
`?C error`.

Current rule: ReadyBASIC only owns the vectors it needs for the wedge
(`$0304/$0306/$0308` for now). `$0300/$0302/$030A` are preserved from the ROM
defaults unless a future hook deliberately wraps and preserves their contracts.

### IGONE Fallback Should Tail-Call The Saved Original Vector

The BASIC command dispatcher enters via `$0308`; the ROM path calls `CHRGET` and
then relies on the text pointer and processor flags in ways that are easy to
disturb. A wedge that probes a statement and then jumps into the middle of the
ROM dispatcher can leave direct-mode commands apparently working but followed by
spurious BASIC errors.

Current rule: probe the next non-space byte without changing `TXTPTR`. If the
statement is not ReadyBASIC's command, jump through the saved original `$0308`
vector so ROM BASIC performs its own `CHRGET`/dispatch path from an untouched
state. Only after `RB`/`rb`/private token is proven does ReadyBASIC advance
`TXTPTR`.

### ICRNCH Must Preserve The Tokenized Line Length

The BASIC line insertion path calls the crunch vector at `$0304`, then stores
`Y` as the tokenized line length. Any custom cruncher that changes the line but
returns the wrong `Y` can corrupt line insertion.

Current POC rule: do not tokenize `RB` yet. Leave `ICRNCH` forwarding to ROM
`$A57C`, and recognize raw `RB`/`rb` from `IGONE` instead. Proper private token
support must be reintroduced only with a cruncher that preserves all required
register and buffer contracts.

### RB Parsing Worked; The Hidden Draw Path Was Invisible

Proven on 2026-05-09 with the binary-monitor probe. After `RB 2,0,12,"OK",1`,
ReadyBASIC state showed `rb_cmd_seen == $02`, `rb_arg_y == $0C`, and
`rb_strbuf == "OK"`, but screen RAM at row 12 did not contain the text. That
rules out the raw `RB` matcher and argument parser as the cause of the invisible
manual command.

Current POC rule: visible `RB 2`/`RB 3` feedback uses KERNAL `PLOT`/`CHROUT`
from the bridge, with the cursor position saved and restored around the output.
The direct hidden screen-writer path needs separate repair before it should be
used for user-visible diagnostics again.

Verification artifacts:
`../agenticdevharness/logs/vice_auto_20260509_173427/` demonstrated the hidden
draw failure, and `../agenticdevharness/logs/vice_auto_20260509_174140/`
demonstrated visible `RB 2`, visible `RB 3`, mailbox `$C004/$C005 == $000F`,
and `EXIT` returning to the launcher.

### EXIT Is The Current Supported Launcher Return

`CTRL+B`/F-key prompt interception is deferred until the editor-safe keyboard
hook is proven. `EXIT`/`exit` is now the explicit ReadyBASIC wedge command for
returning to the launcher: it restores ReadyBASIC-owned vectors, clears pending
keyboard input, marks the app ready, and jumps to the ReadyOS shim return entry.

Automation caveat: the current harness key helper sends lowercase host ASCII in
a way that does not match manual C64 lowercase/PETSCII entry. Automated `exit`
therefore uses uppercase key codes for now, while the command matcher still
accepts both byte forms.

### EXIT Resume Must Snapshot BASIC Runtime State

Revised on 2026-05-10. The late first-link repair made `EXIT`/resume appear to
work for a tiny program, but it was the wrong model. BASIC is a live runtime
image: program text, variables, arrays, string heap, `TXTPTR`, stack, and page
zero must stay coherent together.

Current rule: manual prompt `EXIT` saves BASIC zero page to `$9600-$96FF`,
hardware stack page to `$9700-$97FF`, SP and line-chain guards under
`$9800`, refreshes the hidden helper shadow, restores ReadyBASIC vectors, and
then yields through `$C80C`. Warm entry restores hidden helpers first,
reinstalls ReadyBASIC vectors, restores the saved BASIC runtime state, and
returns to ROM BASIC without clearing the screen or reconstructing variable
pointers from line links.

The old unconditional `$1201/$1202` repair from saved first-link bytes was
removed. It could resurrect old program text after `NEW` or `RB 12`, which
explained reports where `NEW`/`CLR` still left distorted old listings visible
after resume.

Verification artifact:
`../agenticdevharness/logs/vice_auto_20260510_162036/` passed manual prompt
`EXIT`/resume cases for a multi-line program, `NEW` staying empty across
resume, variables/strings/arrays surviving resume, `CLR` keeping program text,
and a stored `RB` line surviving resume.

Baseline lifecycle artifact:
`../agenticdevharness/logs/vice_auto_20260510_162159/` passed direct `PRINT`,
numbered line entry, `LIST`, `RUN`, direct `RB 2`, direct `RB 3`, stored `RB`,
manual `EXIT`, resume, and `LIST` after resume.

Scope note: this verification deliberately covers manual prompt `EXIT`.
Program-line continuation through `EXIT` is deferred. Raw `EXIT` inside
`IF ... THEN` is not expected to work until `EXIT` is tokenized or the wedge
hooks more of BASIC's command dispatch.

## Disproven Or Revised

### Hypothesis: The Headless Harness Proved Numbered Line Entry Stable

Disproven on 2026-05-09 by a visible binary-monitor run:

```sh
READYBASIC_SKIP_BUILD=1 READYBASIC_VISIBLE=1 READYBASIC_KEEP_VICE=1 \
  bash ../agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_lifecycle_probe.sh
```

Artifacts:
`../agenticdevharness/logs/vice_auto_20260509_142432/`.

Direct `PRINT 1` and `PRINT "HELLO"` return to `READY.` without a spurious
`?C ERROR`, but `10 PRINT 1` still shifts the visible screen eight columns to
the right and leaves `@@@@@@@@` on row 0. The previous assertion only checked
for `?`, so it missed the screen corruption and falsely reported success.
Future acceptance must assert screen layout/content, not just absence of BASIC
errors.

### Finding: Numbered Line Entry Needs Pointer Enforcement At Crunch Time

Proven on 2026-05-09. ReadyOS can leave BASIC low-memory pointers unsuitable
for ROM BASIC line insertion even after ReadyBASIC has claimed KERNAL memory
bounds. The failure signature was:

- `$0283/$0284` set to `$1200`, but `TXTTAB`/`VARTAB` low-memory state still
  aimed into `$0100-$05xx`.
- Entering `10 PRINT 1` made ROM BASIC move memory through screen/vector areas,
  leaving `@@@@@@@@` at row 0 and shifting visible output.
- `$1201` stayed empty, proving the line was not being inserted into the scoped
  BASIC workspace.

Fix: enforce ReadyBASIC's scoped BASIC pointers immediately before the
`ICRNCH` pass and before wedge execution. If `VARTAB` is outside the scoped
workspace, reset the empty-program pointers before ROM BASIC inserts the line.

Verification artifact:
`../agenticdevharness/logs/vice_auto_20260509_144003/`.

That run passed direct `PRINT 1`, direct `PRINT "HELLO"`, `10 PRINT 1`, `LIST`,
`RUN`, direct `RB 2`, direct `RB 3` mailbox result `$000F`, and a stored `20 RB
2,...` executed by `RUN`, with assertions rejecting `?` errors and `@` screen
artifacts.

### Hypothesis: The Launch Lockup Was Only A ReadyOS ABI Load-Bounds Problem

Revised. Load bounds did matter and are now verified, but later symptoms proved
there were independent BASIC/KERNAL vector contract bugs after the app loaded.

### Hypothesis: Hooking `CHRIN` After Original Return Is Enough For Prompt Hotkeys

Disproven. The ROM screen editor consumes the interactive key stream internally
and returns the completed logical line. Prompt navigation needs a pre-editor
keyboard-buffer check or a deeper screen-editor hook.

### Hypothesis: Pre-Editor `CHRIN` Keyboard-Buffer Peek Is Safe

Disproven. The pre-editor peek was changed into a blocking wait for `$C6 != 0`.
That starved the ROM screen editor before it could manage cursor/input state,
matching delayed prompts, missing cursor blink, and fragile line entry. The
stabilization pass removes it and accepts that prompt-level hotkeys need a
separate, editor-safe design.

### Hypothesis: Tokenizing `RB` Immediately Is The Best POC Path

Revised. It is desirable, but the first priority is a stable scoped BASIC host.
Raw `RB` recognized at execution time is safer until the crunch/list/execute
contract is fully proven.

## Current Verification Checklist

- Build through normal profile flow, not direct app launching:
  `bash ./run.sh --profile precog-d81 --vice-fast`
- For headless probe runs, use the VICE binary monitor harness outside this
  repo:
  `bash ../agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_lifecycle_probe.sh`
  The script builds the D81 with `runappfirst=readybasic`, boots `PREBOOT`, and
  stores artifacts under `../agenticdevharness/logs/vice_auto_*`.
- For manual-`EXIT` BASIC-state probes, use:
  `bash ../agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_state_probe.sh`
- Confirm `readybasic.prg` load address is `$1000`.
- Confirm compact PRG load span remains below `$C600`.
- Confirm runtime `BRIDGE` remains below `$C600`.
- In ReadyBASIC direct mode:
  - `print "hello"` should print `hello` and return to `ready.` with no error.
  - `10 print 1` should enter without screen corruption or lockup.
  - `list` should show the line.
  - `run` should print `1` and return cleanly.
- At the ReadyBASIC prompt:
  - `exit` should restore vectors and return to the ReadyOS launcher.
- After relaunching ReadyBASIC from the launcher:
  - existing BASIC text, variables, strings, arrays, screen state, and `NEW`
    state should resume coherently after a manual prompt `exit`.
- `CTRL+B`/F-key interception remains deferred until the editor-safe hook is
  implemented and proven.

## Open Questions

- Deferred hypothesis: ReadyBASIC may leave KERNAL `MSGFLG` (`$009D`) nonzero
  when returning to ReadyOS, which would make later shim/ReadyShell `LOAD` calls
  print `SEARCHING FOR` / `LOADING` chatter that normally stays hidden. Prove
  later by dumping `$009D` before ReadyBASIC, after direct BASIC use, after
  `exit`, and immediately before launcher/shim/ReadyShell loads. Likely fix, if
  proven: save/restore or clear `MSGFLG` around ReadyBASIC yield, and consider
  defensive `SETMSG 0` around shim/overlay loads.
- Should the prompt hotkey handler eventually hook the screen editor more
  directly instead of peeking `KEYD_COUNT/KEYD_BUFFER`?
- What exact register/flag contract should the future `RB` token cruncher
  preserve beyond `Y` as length?
- Should `RB 3` keep its visible debug output long term, or become mailbox-only
  once there is a better inspection UI?
- How much of `$C000-$C5FF` should remain free for future app/shim state before
  moving more bridge code into hidden helpers?

## Useful References

- C64 BASIC-ROM map: https://www.c64-wiki.com/wiki/BASIC-ROM
- C64 vectors overview: https://www.c64-wiki.com/wiki/Vector
- Mapping the C64, `DFLTN` and KERNAL input: https://cx16.dk/mapping_c64.html
- C64 OS BASIC wedge discussion: https://c64os.com/post/basicwedgeprograms
