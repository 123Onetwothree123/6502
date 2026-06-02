# REU Refactor Progress

## Branch

- Branch: `codex/reu-control-bank-refactor`

## Current Focus

- Phase 0/1/2 only:
  - baseline and audit support;
  - minimal logical bank `0` schema;
  - mirror current `$C600` bank-type table into logical bank `0`;
  - keep shim unchanged;
  - keep normal-app code-size impact minimal.

## Non-Goals For Current Focus

- No dynamic app snapshot allocation.
- No catalog capacity increase.
- No runtime manifest parser.
- No ReadyShell or ReadyBASIC dynamic bank consumption.
- No service invocation implementation.

## Implemented In This Milestone

- Created logical REU bank `0` control mirror module:
  - `src/lib/reu_control_bank.h`
  - `src/lib/reu_control_bank.c`
- Schema:
  - magic `RCB0`;
  - schema version `1`;
  - header at `$0000`;
  - mirrored 256-byte resident bank table at `$0100`;
  - 10 compact fixed-resource records at `$0200`;
  - no shim growth.
- Fixed-resource records now describe:
  - ReadyOS global/control bank;
  - launcher snapshot and launcher overlay;
  - ReadyShell cache `$40/$41/$42`, debug `$43`, scratch `$48`;
  - ReadyBASIC core/code `$44/$45`.
- Linked the writer only into launcher and reuviewer.
- Launcher refreshes the bank `0` mirror after bitmap sync and app preload
  state changes.
- Launcher has an initial fixed-bank snapshot resolver for shim-facing launch
  handoff paths.
- Reuviewer refreshes the mirror and displays bank `0` header/generation
  status.
- Added `build_support/verify_reu_control_bank.py` and wired it into
  `make verify`.
- Added `build_support/report_app_headroom.py` and generated
  `agentworkijg/reu_refactor_headroom_current.json`.

## Verification Log

- `make bin/launcher.prg bin/launcher_easyflash.prg bin/reuviewer.prg`
  - passed;
  - EasyFlash launcher still reports existing unused-function warnings for
    disk-only paths excluded by the cartridge variant.
- `python3 build_support/verify_reu_control_bank.py`
  - passed with 10 fixed-resource records.
- `python3 build_support/report_app_headroom.py --output agentworkijg/reu_refactor_headroom_current.json`
  - passed;
  - current tightest app-window case is ReadyBASIC with 1031 bytes of headroom.
- `python3 build_support/verify_memory_map.py`
  - passed.
- `python3 build_support/verify_readyos_shim.py --check-easyflash-bin`
  - passed;
  - shim remains 512 bytes;
  - EasyFlash shim binary remains byte-identical to `readyos_shim.inc`.
- `make verify`
  - passed.
- `make easyflash-verify`
  - passed;
  - VICE EasyFlash smoke reported preload bitmap `fe ff 3f`.
- Experimental runtime bank-0 probe:
  - deferred;
  - direct VICE monitor writes to REU I/O registers did not reliably drive the
    live transfer registers, so the next probe should run C64-side code or use
    a proven monitor I/O-address-space command sequence.

## Next Work

- Add a runtime VICE probe for logical bank `0` contents.
- Capture a clean mainline report and compare against
  `agentworkijg/reu_refactor_headroom_current.json` before making bank `0`
  authoritative.
- Extend resolver coverage before introducing dynamic bank assignment.
- Convert existing ReadyShell EasyFlash preload facts into generated dependency
  metadata before changing ReadyShell runtime bank use.
