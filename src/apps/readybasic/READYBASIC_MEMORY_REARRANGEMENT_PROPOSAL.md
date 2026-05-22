# ReadyBASIC Memory Rearrangement Proposal

This is a speculative design note for increasing ReadyBASIC BASIC workspace
while preserving the ReadyOS app contract. It does not describe current code.
The current implementation remains documented in `READYBASIC_CURRENT_DESIGN.md`.

## Current Baseline

ReadyBASIC currently gives BASIC an empty workspace of `26109` bytes:

```text
BASIC text starts at $3001
variables start at   $3003
BASIC top is         $9600

$9600 - $3003 = 26109 bytes
```

For comparison, stock C64 BASIC V2 gives about `38911` bytes:

```text
stock BASIC text starts at $0801
stock BASIC top is         $A000

$A000 - $0801 = 38911 bytes
```

ReadyBASIC is therefore `12802` bytes below stock today. That space buys
ReadyOS integration, resident parser code, overlay slots, shared frames, hidden
helpers, bridge state, and suspend/resume safety.

## Normal ReadyOS Interactive Run

For manual testing, run ReadyOS normally and do not override `runappfirst`:

```sh
bash ./run.sh --skipbuild
```

The default `precog-dual-d71` profile currently has `runappfirst=` blank, so
this boots the launcher instead of autoloading ReadyBASIC. From there,
ReadyBASIC can be launched manually through the ReadyOS menu.

Do not use invalid single-app verification paths such as `run.sh readybasic`.
ReadyBASIC should be exercised through the normal ReadyOS launcher/shim flow.

## Candidate Memory Areas

| Area | Current use | Candidate use | ReadyOS safety |
|---|---|---|---|
| `$2800-$2FFF` | Command-pack load image only after cold seed. | BASIC workspace after cold boot if `BASIC_START` moves lower. | Safe after cold seed; must not be reread on warm resume. |
| `$2400-$27FF` | Call/result/descriptor/name/page frames. | Move to `$C200-$C5FF`, then let BASIC start at `$2401`. | Safe if `$C600-$C7FF` and `$C800-$C9FF` remain untouched. |
| `$1C00-$23FF` | Low overlay execution slot. | Move low command execution under BASIC ROM RAM, then let BASIC start at `$1C01`. | Safe if worker code never needs BASIC ROM visible while executing there. |
| `$9600-$99FF` | Runtime snapshot: zero page, stack, SP, mode, line guards. | Store snapshot in REU bank `$44` or a dedicated ReadyBASIC state bank. | Safe if `EXIT` and warm resume can restore without relying on this RAM. |
| `$9A00-$9FFF` | Hidden helper shadow. | Store helper image in REU and fetch it back on warm resume. | Safe if a tiny visible warm loader can fetch helper before hidden calls. |
| `$A000-$BFFF` RAM under BASIC ROM | Hidden helper and hidden overlay only. | Main command overlay arena for most or all command workers. | Safe inside ReadyOS app window, but only visible when banking out BASIC ROM. |
| `$C000-$C5FF` | Bridge uses `$C000-$C164`; rest is mostly free. | Shared frames, small visible trampolines, loader scratch. | Safe only below `$C600`; do not touch ReadyOS REU metadata or shim ABI. |
| `$C600-$C7FF` | ReadyOS REU metadata. | Not available. | Reserved. |
| `$C800-$C9FF` | ReadyOS shim ABI. | Not available. | Reserved. |
| `$D000-$FFFF` | I/O, ROM, KERNAL, machine state. | Avoid for ReadyBASIC workspace. | Not part of the normal ReadyOS app RAM contract. |

## Loading-Only Or Rarely Needed Code

Some ReadyBASIC bytes are only needed during cold seed, command loading, or
resume. These are good candidates for REU-backed relocation.

| Component | Current location | Lifetime | Reuse idea |
|---|---:|---|---|
| `CMDPACK` load image | `$2800-$2FFF` | Cold seed only. | Let BASIC own this range after `LOWPACK`/`HIDDENPACK` are copied to REU bank `$45`. |
| `REGSEED` | `$4000-$416F` | Cold seed only. | Already load-only; never reread after BASIC owns memory. |
| Runtime snapshot | `$9600-$99FF` | Needed only across `EXIT`/warm resume. | Save zero page/stack/mode directly to REU during `EXIT`; restore from REU on warm entry. |
| Hidden shadow | `$9A00-$9FFF` | Needed only to restore `$A000` helper after app switch. | Keep helper image in REU bank `$45` or a small state bank and fetch on warm entry. |
| Low overlay slot | `$1C00-$23FF` | Needed only while a command is executing. | Run low workers from banked RAM under BASIC ROM instead, using the hidden-overlay discipline. |
| Shared frames | `$2400-$27FF` | Needed during parse/execute/commit, not as BASIC storage. | Move to mostly free visible RAM below `$C600`, for example `$C200-$C5FF`. |

The key distinction: code/data can be reused only if it is not needed while a
BASIC program is stored in that address range. Load-only seed bytes are easy.
Runtime parser, command dispatch, and result commit code are not easy because
they must remain callable whenever BASIC dispatches a statement.

## Proposed Rearrangement Stages

### Stage 1: Move Shared Frames To `$C200-$C5FF`

Move the fixed shared frame block out of `$2400-$27FF`:

| Current frame | Current address | Proposed address |
|---|---:|---:|
| Call frame | `$2400` | `$C200` |
| Result frame | `$2500` | `$C300` |
| Descriptor buffer | `$2680` | `$C480` |
| Command buffer | `$26A0` | `$C4A0` |
| Page buffer | `$2700` | `$C500` |

Keep the bridge at `$C000-$C164`; leave a small gap before `$C200`. Stay below
`$C600`, because `$C600-$C7FF` is ReadyOS REU metadata.

After this, `$2400-$2FFF` can become BASIC workspace after cold seed, and
`BASIC_START` could move from `$3001` to `$2401`.

Expected free BASIC RAM:

```text
$9600 - $2403 = 29181 bytes
gain over current = 3072 bytes
```

### Stage 2: Move Command Workers Under BASIC ROM

Move low command execution out of `$1C00-$23FF`. Use RAM under BASIC ROM as the
main worker overlay arena, just as `HCRC` already proves for hidden code.

This would make `$1C00-$23FF` available to BASIC and let `BASIC_START` move to
`$1C01`, immediately after the resident core.

Expected free BASIC RAM while keeping the current `$9600` top:

```text
$9600 - $1C03 = 31229 bytes
gain over current = 5120 bytes
```

Design constraints:

- Worker overlays must not call BASIC ROM while BASIC ROM is banked out.
- The resident visible core still owns parsing and result commit.
- Hidden worker calls need the same careful `$0000/$0001` banking discipline as
  current hidden helper calls.
- The hidden helper at `$A000` and worker arena at `$A800+` need a clear layout
  so they do not overlap.

### Stage 3: Move Resume Snapshot And Hidden Shadow To REU

Move `$9600-$99FF` runtime snapshot and `$9A00-$9FFF` hidden helper shadow out
of C64 BASIC-visible RAM and into REU.

This would allow BASIC top to move from `$9600` back to `$A000`, the normal
BASIC ROM boundary.

With Stage 2 also done:

```text
$A000 - $1C03 = 33789 bytes
gain over current = 7680 bytes
remaining gap below stock = 5122 bytes
```

Design constraints:

- `EXIT` must save zero page, stack, SP, mode, and line-chain guards directly to
  REU before yielding to ReadyOS.
- Warm entry must have a tiny visible path that can fetch the hidden helper from
  REU before any `$A000` helper call.
- If REU state is missing or corrupt, warm entry must fall back to a safe cold
  BASIC workspace rather than resuming bad pointers.
- ReadyBASIC must continue to re-mark REU bank ownership on warm resume.

## BASIC RAM Scenarios

| Scenario | BASIC start | BASIC top | Empty free bytes | Gain over current |
|---|---:|---:|---:|---:|
| Current layout | `$3001` | `$9600` | `26109` | `0` |
| Reclaim load-only `CMDPACK` only | `$2801` | `$9600` | `28157` | `+2048` |
| Move shared frames to `$C200` | `$2401` | `$9600` | `29181` | `+3072` |
| Move all command workers under ROM | `$1C01` | `$9600` | `31229` | `+5120` |
| Move workers under ROM and resume state to REU | `$1C01` | `$A000` | `33789` | `+7680` |
| Stock C64 BASIC V2 | `$0801` | `$A000` | `38911` | `+12802` versus current |

The practical high-value target is `33789` bytes free. Getting beyond that
would require moving or radically shrinking the visible resident core below
`$1C00`, or moving parts of resident dispatch into a banked/trampoline model.
That is much riskier because the execute hook must be callable from normal BASIC
statement dispatch and must use BASIC ROM helpers safely.

## Command Growth Model

The REU registry remains the right scaling model.

Current incremental cost for a new command that reuses an existing
parameter/result signature:

- `0` bytes of BASIC workspace.
- Usually `0` bytes of permanent resident RAM.
- `32` bytes for one descriptor in REU bank `$44`.
- Command implementation bytes in a packed REU code bank.
- Matching load-image bytes, unless future tooling can build command packs
  directly into REU-backed media.

If many more commands are added, the next design step should not be lowering
BASIC top or adding resident command bodies. It should be:

1. Keep descriptors in REU.
2. Add more packed command-code banks when `$45` fills.
3. Add a bank id or pack id to the descriptor format.
4. Keep shared parser/commit code resident only when several commands reuse it.
5. Store large command-private state in REU and expose BASIC integer handles.

## Recommended Rearranged Layout

This is the most attractive medium-risk target:

| Region | Proposed use |
|---|---|
| `$1000-$1102` | Tiny entry/warm trampoline. Keep only what must run before resident setup. |
| `$1200-$1BC1` | Visible resident parser, vector hooks, ROM calls, REU DMA, result commit. |
| `$1C00` | BASIC sentinel byte. |
| `$1C01-$9FFF` | BASIC workspace if resume state moves to REU and command workers move under ROM. |
| `$A000-$A1FF` | Hidden helper, fetched from REU on cold/warm setup. |
| `$A200-$BFFF` | Hidden command overlay arena for workers. |
| `$C000-$C164` | Bridge state and saved vectors. |
| `$C165-$C1FF` | Guard or small spare visible bytes. |
| `$C200-$C5FF` | Shared frames and page buffer. |
| `$C600-$C7FF` | ReadyOS REU metadata; do not use. |
| `$C800-$C9FF` | ReadyOS shim ABI; do not use. |

This keeps the ReadyOS app-window contract intact and does not ask BASIC to use
RAM above `$A000`. It gets ReadyBASIC back to `33789` empty BASIC bytes while
still supporting many more commands through REU-packed overlays.

## Risks And Required Proofs

- Prove hidden-worker-only execution for every current command, not just `HCRC`.
- Prove no worker calls BASIC ROM while BASIC ROM is banked out.
- Prove shared frames at `$C200-$C5FF` do not collide with bridge growth or
  ReadyOS metadata.
- Prove `EXIT` can save runtime state to REU and warm entry can restore it
  before BASIC resumes.
- Prove missing/corrupt REU state falls back safely.
- Rebuild VICE probes to cover direct mode, stored programs, `IF ... THEN !`,
  strings/REM/DATA safety, arrays, handles, failures, `EXIT`, and cross-app
  resume under the new layout.
