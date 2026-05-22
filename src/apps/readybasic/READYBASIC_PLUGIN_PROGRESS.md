# ReadyBASIC Plugin Progress

This is a chronological progress log. Older entries intentionally preserve the
layout and addresses that were current when the tests were run. For the current
memory map, use `READYBASIC_CURRENT_DESIGN.md`.

## 2026-05-22: REU-Backed 128 Handles And 48KB Typed Heap

- Commands:
  - `make readybasic-plugin-static-check`
  - `make bin/reuviewer.prg`
  - `make verify`
  - ReadyBASIC direct, program, lifecycle, state, large-vars, and full visual
    VICE suites through normal ReadyOS boot paths.
- Result: static/build verification passed. VICE harness runs completed every
  concrete assertion with `FailedStep: null`; the wrapper still reported
  `partial`, matching the current harness behavior when no concrete step fails.
- Run dirs:
  - Direct: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_153017`
  - Program: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154145`
  - Lifecycle: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154246`
  - State: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154309`
  - Large vars: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154359`
  - Full visual: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260522_154424`
- Current static layout:
  - `ENTRY` `$1000-$1102`, size `$0103` (259B).
  - `RESIDENT` `$1200-$1BAF`, size `$09B0` (2480B).
  - `REGSEED` `$5000-$600F`, size `$1010` (4112B).
  - `HIDDEN` `$A000-$A376`, size `$0377` (887B).
  - `HIDDENPACK` `$A800-$A84C`, size `$004D` (77B).
  - `LOWPACK` `$A900-$AEDE`, size `$05DF` (1503B).
  - `BRIDGE` `$C000-$C19A`, size `$019B` (411B).
- BASIC workspace:
  - `BASIC_START=$1C01`, BASIC top `$A000`.
  - Empty free space remains `33789` bytes (33.0K), a `0` byte reduction from
    the pre-change baseline.
- Handles and heap:
  - `RB_HANDLE_COUNT=128`.
  - `RB_HEAP_PAGES=192`, with the typed heap at REU bank `$44:$4000-$FFFF`.
  - The handle directory is REU-backed at `$44:$0800-$09FF`.
  - The 192-page heap bitmap is REU-backed at `$44:$0C00`.
  - Bridge RAM keeps only the current handle descriptor scratch, not a 128-entry
    resident table.
- Probe coverage added:
  - handle `1..128` allocation and handle-table-full on handle 129;
  - low-handle reuse after free;
  - 48KB buffer allocation and heap-full rejection;
  - screen text+color handles filling the 48KB heap;
  - type rejection and freeing behavior after the expanded table.

## 2026-05-22: 128-Slot Registry And Typed Screen Handles

- Commands:
  - `make readybasic-plugin-static-check`
  - `make bin/reuviewer.prg`
  - `make verify`
  - ReadyBASIC direct, program, lifecycle, state, large-vars, and full visual
    VICE suites through normal ReadyOS boot paths.
- Result: static/build verification passed. VICE harness runs completed all
  concrete steps with `FailedStep: null`; the harness process status remained
  `partial`, matching the pre-change baseline wrapper behavior.
- Current static layout:
  - `ENTRY` `$1000-$1102`, size `$0103` (259B).
  - `RESIDENT` `$1200-$1BF9`, size `$09FA` (2554B).
  - `REGSEED` `$5000-$600F`, size `$1010` (4112B).
  - `HIDDEN` `$A000-$A336`, size `$0337` (823B).
  - `HIDDENPACK` `$A800-$A84C`, size `$004D` (77B).
  - `LOWPACK` `$A900-$ADDF`, size `$04E0` (1248B).
  - `BRIDGE` `$C000-$C1C4`, size `$01C5` (453B).
  - PRG payload `$5200` (20992B).
- BASIC workspace:
  - `BASIC_START=$1C01`, BASIC top `$A000`.
  - Empty free space remains `33789` bytes (33.0K), a `0` byte reduction from
    the memory-reclaim baseline.
- Registry:
  - `RB_CMD_DESC_COUNT=128`.
  - Descriptor table is cold-seeded from `REGSEED` to REU bank `$44`
    `$1000-$1FFF`.
  - Lookup fetches 256-byte descriptor pages into `$C500`, scans eight
    descriptors locally, and copies a match to `$C480`.
  - Filler descriptors are zero-filled empty slots.
  - `SCRCAP` is near the front in slot 13; `SCRPUT` is in slot 128.
- Handles:
  - Existing live handle count remains eight.
  - Type `1` is a byte buffer; type `2` is screen text+color.
  - `BUFFILL` rejects non-buffer handles with `?RB ERROR 40`.
  - `BUFFREE` frees any valid handle type.
  - `SCRCAP H%` captures `$0400-$07E7` and `$D800-$DBE7`.
  - `SCRPUT H%` validates type `2` and restores screen text plus color RAM.
  - The originally proposed `SCRSAVE`/`SCRLOAD` names were changed to
    `SCRCAP`/`SCRPUT` to avoid C64 BASIC tokenizer conflicts.
- Probe coverage added:
  - screen capture/restore;
  - slot-128 lookup;
  - filler descriptor scanning;
  - wrong-handle-type rejection in both directions;
  - freeing a screen handle.

## 2026-05-21: Memory-Reclaim Layout

- Command: `make readybasic-plugin-static-check`
- Result: pass.
- Current static layout:
  - `ENTRY` `$1000-$1102`, size `$0103` (259B).
  - `RESIDENT` `$1200-$1BAB`, size `$09AC` (2.4K).
  - `REGSEED` `$4000-$418F`, size `$0190` (400B).
  - `HIDDEN` `$A000-$A336`, size `$0337` (0.8K).
  - `HIDDENPACK` `$A800-$A84C`, size `$004D` (77B).
  - `LOWPACK` `$A900-$ABF2`, size `$02F3` (0.7K).
  - `BRIDGE` `$C000-$C1BD`, size `$01BE` (446B).
- Current BASIC workspace:
  - `BASIC_START=$1C01`.
  - BASIC top is `$A000`.
  - Empty free space is `33789` bytes (33.0K), up from `26109` bytes (25.5K).
  - Recovered space is `7680` bytes (7.5K).
- Current suspend/resume layout:
  - Shared frames live at `$C200-$C5FF` (`$0400`, 1.0K).
  - Hidden helper shadow is refreshed at `$C280-$C5B6` (`$0337`, 0.8K).
  - Zero page and stack snapshots live in REU bank `$44` offsets `$0A00/$0B00`.
- Latest full visual verification:
  - Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_202657`
  - Result: 98/98 steps, `FailedStep: null`, no degraded steps.

## 2026-05-11: Assembler Spine Build

- Command: `make bin/readybasic.prg`
- Result: pass.
- Key trace:
  - `ENTRY` size `$0103`.
  - `RESIDENT` `$1200-$1ABE`, size `$08BF`.
  - `LOWPACK` `$1C00-$1EEE`, size `$02EF`.
  - `HIDDEN` `$A000-$A141`, size `$0142`.
  - `HIDDENPACK` `$A800-$A82F`, size `$0030`.
  - `BRIDGE` `$C000-$C075`, size `$0076`.
- First failing step before pass: resident overflowed `$1200-$1BFF` by `$0286`, then `$0116`, then `$008E`.
- Fixes applied:
  - Moved registry seed data to `REGSEED`.
  - Moved REU prestash code to hidden helper.
  - Moved handle/page allocator implementation into the low overlay pack.
  - Added `CMD_LOW_ALL` for heap commands that need the low overlay helper cluster.
  - Prevented warm resume from rereading `REGSEED` after BASIC may own `$4000+`.
- Next hypothesis:
  - Run static guardrail target after each layout-sensitive edit.
  - Add VICE command-level probes through normal ReadyOS boot once the launcher-side automation is updated for raw `!COMMAND args` samples.
  - Existing ReadyBasic lifecycle probe still needed regeneration for the new
    plugin-spine commands before it could be treated as authoritative.

## 2026-05-11: Static Guardrail

- Command: `make readybasic-plugin-static-check`
- Result: pass.
- Checks:
  - `BASIC_START=$3001`.
  - Resident below `$1C00`.
  - Low overlay in `$1C00-$23FF`.
  - Hidden helper below `$A600`.
  - Hidden overlay in `$A000-$BFFF`.
  - Bridge below `$C600`.
  - ReadyBasic REU bank/type constants synced with `src/lib/reu_mgr.h`.

## 2026-05-11: REU Viewer Compile Check

- Command: `make bin/reuviewer.prg`
- Result: pass.
- Reason: ReadyBASIC added REU bank types `14/15`, so the C-side viewer and fixed-bank sync needed a compile check.

## 2026-05-11: Baseline Contract Review

- Command: `git show HEAD:src/apps/readybasic/readybasic.s` plus targeted `rg` over `readybasiclessonslearnt.md`.
- Still relevant and must be carried forward:
  - Cold entry must reset KERNAL and BASIC vectors before installing ReadyBASIC's vector ownership.
  - ReadyBASIC-owned vectors must be restored before jumping through the ReadyOS shim.
  - Warm entry must restore hidden helper code from `$9A00` before calling any `$A000` helper.
  - Manual prompt `EXIT` must save BASIC zero page, stack, line-chain validity, and app mode before returning to the launcher.
  - READY-mode resume must clear the screen/editor surface, clear pending key buffer bytes, restore lowercase VIC text mode, redraw ReadyBasic's banner, position the prompt, and then enter `BASIC_READY`.
  - Warm restore must preserve live BASIC pointers such as `FRETOP`, `VARTAB`, `ARYTAB`, and `STREND`; those are restored from the runtime snapshot and must not be reset to the cold empty-program layout.
  - Fallback to ROM BASIC must not leave `TXTPTR` advanced unless ReadyBASIC has proven it owns the statement.
  - `BASIC_START=$3001` changes addresses, not the lifecycle contract.
- No longer relevant or intentionally replaced:
  - Demo commands `RB 1/2/3/10/11/12`, hidden screen drawing, mailbox text drawing, and PRG save/load helpers.
  - `$1201` BASIC workspace and old `$1000-$3FFF` compact load assumptions.
  - Private `RB` token experiments. The visible probe showed the `$CC` token/list attempt can crash/blank `LIST`; V1 keeps raw direct `!COMMAND args` only.
  - Direct app-bank hotkeys in probes. Acceptance should navigate the launcher menu for ReadyBasic re-entry.
- Fixes from this review:
  - `cmd_exit` now identifies manual prompt `EXIT` by `TXTPTR < BASIC_START` instead of `CURLIN`; this matches the direct input buffer path and keeps program-line resume as a later candidate.
  - `cmd_exit` writes `RUNTIME_MODE` directly in visible RAM before the hidden save helper. The hidden helper preserves that byte instead of recomputing it from `CURLIN` or bridge state, preventing direct prompt `EXIT` from resuming via `BASIC_NEXT_STMT`.
  - READY-mode restore now uses the baseline console-reset steps (`K_CLRCHN`, lowercase VIC text mode, key buffer clear, banner redraw, prompt positioning).
  - Warm restore now sets only KERNAL memory bounds after restoring zero page; cold initialization remains responsible for resetting BASIC pointers and `FRETOP`.
- Next hypothesis:
  - Rerun visible `run_readybasic_plugin_command_probe.sh` with menu-based re-entry and add a variable/string-after-resume probe before committing the safe branch.

## 2026-05-11: Interrupted Visible Boot/Resume Run

- Command: `make readybasic-plugin-static-check && READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_plugin_command_probe.sh`
- Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_201407`
- Result: interrupted/terminated manually after VICE appeared locked before the ReadyBasic banner.
- Key trace:
  - Static guardrail passed before launch.
  - Probe started 44-step visible plan and reached `wait_readybasic_prompt`.
  - Only `boot_initial` artifacts were captured; no memory dump was produced before termination.
  - The decoded boot screen showed the same uninitialized screen pattern seen in earlier healthy runs, but unlike earlier runs it had not advanced to the ReadyBasic banner quickly enough.
- First failing step/code:
  - Treat as `wait_readybasic_prompt` until a complete harness timeout or monitor dump proves otherwise.
- Follow-up checks:
  - Process table cleanup confirmed no lingering `x64sc`/`ViceTasks.Binary` probe processes.
  - `$C600-$C7FF` was rechecked against ReadyOS docs and source: it is reserved ReadyOS REU metadata, and `src/lib/reu_mgr.c` uses `$C600` as the allocation table. ReadyBasic may mark `$C600+$44/$45` only as shared REU ownership metadata; it must not treat this range as app-private scratch.
  - Static guardrail rerun after cleanup: `make readybasic-plugin-static-check` passed.
- Next hypothesis:
  - The persistent functional regression remains the menu-based resume path: the previous complete run reached all direct command probes, returned to the launcher, then failed `wait_readybasic_after_resume`.
  - Re-run the visible probe with an interrupt-capable terminal session. If cold boot stalls again, capture a monitor dump before killing VICE. If cold boot succeeds, focus on `RUNTIME_MODE`, bridge magic, and READY-mode screen redraw after menu resume.

## 2026-05-11: Visible Plugin Probe Passed

- Command: `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_plugin_command_probe.sh`
- Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_202147`
- Result: pass, 44/44 steps.
- Key trace:
  - Cold boot reached `READYBASIC REU PLUGINS`.
  - Direct command probes passed for `PING`, `ADD16`, `STRUP`, `HCRC`, `SUMAI`, `RANGEAI`, `BUFNEW`, `BUFFILL`, `BUFFREE`, `TEMPSCRATCH`, `FAIL`, and unknown-command error.
  - `EXIT` returned to the launcher.
  - ReadyBasic was relaunched by menu navigation, not `CTRL+3`.
  - READY-mode resume cleared/redrew the ReadyBasic screen and `!PING` still worked after resume.
- First failing step/code: none.
- Next hypothesis:
  - Add an explicit BASIC variable/string survival check across the same launcher round trip before committing a known-good fallback branch.

## 2026-05-11: Visible Resume-State Probe Passed

- Command: `READYBASIC_SKIP_BUILD=1 READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_plugin_command_probe.sh`
- Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_202329`
- Result: pass, 47/47 steps.
- Key trace:
  - Reused the already-built `precog-d81` image from the previous passing run.
  - Added `V%=321:VS$="OK"` before `EXIT`.
  - Returned to launcher, relaunched ReadyBasic by menu navigation, and asserted `STATE 321 :OK` after resume.
  - Asserted `RESUME 1` from `!PING` after the state check.
  - Final bridge dump starts with `52 a6`, confirming READY resume magic after the round trip.
- First failing step/code: none.
- Next hypothesis:
  - Safe branch can be created and committed as the current fallback point.
  - Stored-line/private-token support remains out of scope for this checkpoint and needs a separate crunch/list contract probe before reintroduction.

## 2026-05-11: Fresh Build Visible Probe Passed On Branch

- Branch: `codex/readybasic-reu-plugin-spine`
- Static command: `make readybasic-plugin-static-check`
- Static result: pass.
- Automation command: `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_plugin_command_probe.sh`
- Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_202716`
- Result: pass, 47/47 steps after a fresh `precog-d81` profile build with `runappfirst=readybasic`.
- Key trace:
  - Cold ReadyOS boot autoloaded ReadyBasic through the generated app config.
  - All direct plugin sample commands passed.
  - `FAIL` cleared the output variable before reporting `?RB ERROR 7`.
  - Unknown command reported `?RB ERROR 1`.
  - Menu-based ReadyBasic re-entry passed; no `CTRL+3` path was used.
  - `V%=321` and `VS$="OK"` survived `EXIT` -> launcher -> menu relaunch.
  - Post-resume `!PING P%` returned `RESUME 1`.
- First failing step/code: none.
- Next hypothesis:
  - Commit the source/config/docs/static-check delta as the known-good fallback point.

## 2026-05-11: Program-Mode Probe Passed

- First failing command: `READYBASIC_SKIP_BUILD=1 READYBASIC_VISIBLE=1 bash /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_program_probe.sh`
- First failing run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_203414`
- First failing step/code: `assert_program_ping_run`, screen contained `?SYNTAX ERROR` instead of `PRPING 1`.
- Key diagnosis:
  - `LIST` showed `10 !PING`, so raw stored text survived crunch/list.
  - Bridge debug state showed `$0308` was not reached during the stored line.
  - Dumping BASIC text proved `$3000`, the byte before relocated `BASIC_START=$3001`, contained `$20`.
  - C64 BASIC `NEWSTT` expects the byte before `TXTTAB` to be zero; otherwise it reports syntax before advancing into the first stored line.
- Fixes applied:
  - Restored the older IGONE-style non-mutating peek/tail-call contract for `$0308` fallback.
  - Cold BASIC workspace initialization now clears `BASIC_SENTINEL` (`$3000`) as well as the empty line-link bytes at `$3001/$3002`.
  - Removed the now-unused saved-`TXTPTR` bridge bytes after switching back to non-mutating peek; final `BRIDGE` remains `$C000-$C075`.
- Static command: `make readybasic-plugin-static-check`
- Static result: pass.
- Passing program command: `READYBASIC_VISIBLE=1 bash /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_program_probe.sh`
- Passing program run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_204630`
- Program result: pass, 24/24 steps after a fresh `precog-d81` profile build with `runappfirst=readybasic`.
- Program trace:
  - `!PING OUT%` works from stored BASIC and survives `LIST`.
  - Same-line continuation works: `!ADD16 ...:PRINT ...`.
  - String input/output works: `!STRUP S$,T$`.
  - Hidden `$A000` worker works: `!HCRC "AB",H%`.
  - Integer array input/output works: `SUMAI` and `RANGEAI`.
  - Persistent REU handle lifecycle works: `BUFNEW`, `BUFFILL`, `BUFFREE`.
  - Error path works: `!FAIL 7,X%` reports `?RB ERROR 7` and leaves the pre-cleared output variable at zero.
- Regression command: `READYBASIC_SKIP_BUILD=1 READYBASIC_VISIBLE=1 bash /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_plugin_command_probe.sh`
- Regression run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260511_204727`
- Regression result: pass, 47/47 steps.
- Next hypothesis:
  - The raw `!COMMAND args` path is now proven for both direct mode and stored program mode.
  - Future token/crunch work must keep the sentinel, IGONE fallback, and line-length contracts under explicit tests.

## 2026-05-12: Full Suite Visual Verification Passed

- Script: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh`
- Generated plan id: `readybasic_full_suite_visual_verification`
- Command: `READYBASIC_VISIBLE=1 /Users/karlprosserpp/dev/c64projects/agenticdevharness/tools/vice_tasks_dotnet/AGENTWORKING/run_readybasic_full_suite_visual_verification.sh`
- Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260512_002033`
- Result: pass, 84/84 steps after a fresh `precog-d81` profile build with `READYOS_CONFIG_RUN_FIRST=readybasic`.
- Visual pacing:
  - All input sections use `post_delay_s: 3.0`, so the current result or `LIST` output remains visible for three seconds before the next screen-clearing section begins.
- Key trace:
  - Cold ReadyOS boot autoloaded ReadyBasic through the generated app config.
  - Direct-mode sample commands passed across scalar, string, hidden worker, array, REU handle, temporary heap, failure, and unknown-command paths.
  - Launcher round trip used menu navigation, not `CTRL+3`; ReadyBasic redrew on return and variables plus registry state survived.
  - Stored BASIC program tests passed for `PING`, same-line `ADD16`, `STRUP`, hidden `HCRC`, `SUMAI`, `RANGEAI`, `BUFNEW/BUFFILL/BUFFREE`, and failure output clearing.
- First failing step/code: none.
- Next hypothesis:
  - Keep this script as the human-watchable acceptance suite while shorter direct/program probes remain better for tight edit-run loops.

## 2026-05-21: Bang Command Syntax Migration

- Syntax changed from `RB NAME,...` to `!NAME args`, with the first argument
  separated by spaces and later arguments still comma-separated.
- Parser changes:
  - `$0308` execute hook now recognizes raw `!` at BASIC statement start,
    including after `:`.
  - Command-name parsing uses raw `TXTPTR` reads so `!PING P%` does not absorb
    `P%` as part of the command name.
  - Parameter parsing allows whitespace before the first argument and commas for
    subsequent arguments.
  - A leading comma after the command name is rejected as syntax.
- `IF ... THEN !COMMAND` fix:
  - Added a tiny `$0304` crunch hook that calls ROM crunch first.
  - After ROM tokenization, only a real `THEN` token followed by `!` is rewritten
    to `THEN :!`, letting ROM BASIC reach the normal `$0308` statement dispatch.
  - Quoted strings, `REM`, and `DATA` text containing `THEN !` are not rewritten.
- Static command: `make readybasic-plugin-static-check`
- Static result: pass; `RESIDENT $1200-$1BC1` (`$09C2`), `BRIDGE $C000-$C164`
  (`$0165`).
- Fresh-build command probe:
  - Command: `READYBASIC_VISIBLE=1 bash .../run_readybasic_plugin_command_probe.sh`
  - Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_010753`
  - Follow-up run with direct `IF 1 THEN !PING`: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_011815`
  - All steps reported `ok`; wrapper status was `partial` with no failed step.
- Program probe:
  - Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012044`
  - All steps reported `ok`, including stored `IF 1 THEN !PING`, `IF 0 THEN`,
    `FOR/NEXT`, and `THEN !` inside string/`REM`/`DATA` text.
- Full visual suite:
  - Run dir: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012154`
  - All 98 steps reported `ok`; wrapper status was `partial` with no failed step.
- Additional probes:
  - Lifecycle: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012603`, all 47 steps `ok`.
  - State: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012627`, all 57 steps `ok`.
  - `RBTEST1`: `/Users/karlprosserpp/dev/c64projects/readyosprecog/logs/vice_auto_20260521_012719`, all 12 steps `ok`.
  - Large vars: `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012739`, all 19 steps `ok`.
- Harness instability:
  - Cross-app resume reached step 200/206 before VICE exited with code 137:
    `/Users/karlprosserpp/dev/c64projects/agenticdevharness/logs/vice_auto_20260521_012802`.
  - A rerun failed near launch with the same VICE exit code 137, and the
    second-entry editor probe also failed before reaching ReadyBASIC due VICE
    monitor/exit-137 launch failures.
