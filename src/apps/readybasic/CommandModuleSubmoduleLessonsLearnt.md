# ReadyBASIC Command Module/Submodule Lessons Learnt

This log tracks implementation lessons for the ReadyBASIC command
module/submodule experiment. It is intentionally separate from the design plan:
the plan describes the target architecture, while this file records what was
proven, adjusted, or rejected during implementation.

## Baseline

- Branch: `codex/readybasic-command-modules`.
- Scope is slices 1 through 4 only.
- Baseline static gate passed with:
  `make bin/readybasic.prg && make readybasic-plugin-static-check`.
- Baseline VICE gate passed with:
  `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh`.
  Result was `success`, 167/167 steps, failed step `null`, no degraded steps.
  Run dir:
  `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260525_205922`.
- Baseline memory:
  - `BASIC_START=$2AC1`.
  - Formula BASIC free bytes: `30013 ($753D)`.
  - `RESIDENT $1200-$2AB9`, size `$18BA` / 6330B.
  - `HIDDEN $A000-$A376`, size `$0377` / 887B.
  - `HIDDENPACK $A800-$A84C`, size `$004D` / 77B.
  - `LOWPACK $A900-$AF3C`, size `$063D` / 1597B.
  - `BRIDGE $C000-$C1F3`, size `$01F4` / 500B.
  - `REGSEED $5000-$600F`, size `$1010` / 4112B.
  - `readybasic.prg` payload bytes: `$5200` / 20992B.
- Next hypothesis: descriptor fields can be repacked without changing
  descriptor size if command name bytes stay at offset 16 and signature stays at
  offset 14 for the existing lookup/parser paths during Slice 1.

## Slice 1: Descriptor Refactor

- Changed the 32-byte command descriptor semantics from low/hidden flags to a
  compact module-aware shape while preserving signature offset 14 and command
  name offset 16.
- Routed low and hidden command payloads through one generic under-ROM
  fetch/call path.
- Converted `ZHIDDENRAM` to that generic path without changing its public
  behavior.
- Static gate:
  `make bin/readybasic.prg && make readybasic-plugin-static-check` passed.
- VICE gate:
  `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh`
  passed with `success`, 167/167 steps, failed step `null`, no degraded steps.
  Run dir:
  `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260525_210853`.
- Memory delta versus baseline:
  - `BASIC_START` unchanged at `$2AC1`.
  - Formula BASIC free bytes unchanged at `30013 ($753D)`.
  - `RESIDENT` changed from `$18BA` / 6330B to `$1891` / 6289B, delta `-41B`.
  - `HIDDEN`, `HIDDENPACK`, `LOWPACK`, `BRIDGE`, `REGSEED`, and PRG payload
    size were unchanged.
- Lesson: unifying low and hidden dispatch actually removed resident code
  because the old two-branch loader carried duplicate copy/call setup.
- Next hypothesis: moving the payload layout to 2KB slots should be done by
  changing linker segments and descriptor copy offsets first, then adding
  residency checks as a separate step inside Slice 2.

## Slice 2: Slot 0 Layout

- Moved the packed command payload from the old `$A900` LOWPACK run address to
  the new 2KB slot 0 address at `$A800-$AFFF`.
- Removed the separate `HIDDENPACK` segment; former hidden command payload code
  now uses the same generic slot 0 path as the rest of the under-ROM commands.
- Widened the common/helper under-ROM region to `$A000-$A7FF` in the linker
  config and static checker.
- Added slot residency mirror fields in the bridge area, but deferred the
  copy-skip decision until Slice 4 proof commands can measure it explicitly.
- Static gate:
  `make bin/readybasic.prg && make readybasic-plugin-static-check` passed.
- VICE gate:
  `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh`
  passed with `success`, 167/167 steps, failed step `null`, no degraded steps.
  Run dir:
  `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260525_212413`.
- Memory delta versus baseline:
  - `BASIC_START` unchanged at `$2AC1`; formula BASIC free bytes unchanged at
    `30013 ($753D)`.
  - `RESIDENT` changed from `$18BA` / 6330B to `$18B3` / 6323B, delta `-7B`.
  - `HIDDEN` changed from `$0377` / 887B to `$0368` / 872B, delta `-15B`.
  - `LOWPACK` and `HIDDENPACK` merged from `$063D + $004D` / 1674B total into
    one slot 0 `LOWPACK` of `$068A` / 1674B.
  - `BRIDGE` changed from `$01F4` / 500B to `$01F8` / 504B, delta `+4B`.
  - `REGSEED` and PRG payload size were unchanged.
- Failed experiment: the first resident-skip implementation passed early integer
  commands but produced a syntax error on `T$=UPPER(S$)` in the visual suite.
  The slot bytes themselves were present at `$A800`, so the risky part was the
  new skip decision, not the segment move.
- Lesson: land the physical layout separately from no-recopy optimization.
  Slice 4 should add copy-count instrumentation and prove skip behavior with
  new commands instead of trusting it implicitly.
- Next hypothesis: the built-in demo module can be modeled in the descriptor
  table first, with compact proof commands using existing integer-return
  plumbing before richer copy-count and overlay behavior are added.
