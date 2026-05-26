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
