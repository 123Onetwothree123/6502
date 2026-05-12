# ReadyBASIC Plugin Progress

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
  - Add VICE command-level probes through normal ReadyOS boot once the launcher-side automation is updated for raw `RB COMMAND,...` samples.
  - Existing ReadyBasic lifecycle probe still drives old demo commands such as `RB 2,...` and `RB 3,...`; do not treat it as a valid plugin-spine probe until it is regenerated for `PING`, `ADD16`, `STRUP`, and the handle commands.

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
  - Private `RB` token experiments. The visible probe showed the `$CC` token/list attempt can crash/blank `LIST`; V1 keeps raw direct `RB COMMAND,...` only.
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
  - READY-mode resume cleared/redrew the ReadyBasic screen and `RB PING` still worked after resume.
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
  - Asserted `RESUME 1` from `RB PING` after the state check.
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
  - Post-resume `RB PING,P%` returned `RESUME 1`.
- First failing step/code: none.
- Next hypothesis:
  - Commit the source/config/docs/static-check delta as the known-good fallback point.
