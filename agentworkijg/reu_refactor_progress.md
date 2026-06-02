# REU Refactor Progress

## Branch

- Branch: `codex/reu-control-bank-refactor`

## Current Focus

- Dynamic app snapshot allocation milestone:
  - keep the bank `0` mirror baseline intact;
  - allow 64 app catalog entries;
  - allocate app snapshot logical banks lazily at load time;
  - keep the shim unchanged and keep `$C836-$C838` as the legacy low-bank
    bitmap only;
  - support cartridge-preloaded app state above the shim bitmap;
  - add unload for disk launcher app snapshots.

## Non-Goals For Current Focus

- No runtime manifest parser.
- No ReadyShell or ReadyBASIC dynamic bank consumption.
- No service invocation implementation.
- No arbitrary dependency/overlay loader yet. Existing app manifests can add a
  single app entry, but generalized `requires`/overlay/module preload records
  are not implemented in this milestone.

## Implemented In This Milestone

- Baseline bank `0` mirror remains:
  - `src/lib/reu_control_bank.h`
  - `src/lib/reu_control_bank.c`
  - magic `RCB0`, schema version `1`;
  - header at `$0000`;
  - mirrored resident bank table at `$0100`;
  - fixed-resource records at `$0200`;
  - no shim growth.
- Created logical REU bank `0` control mirror module:
  - linked only into launcher and reuviewer;
  - launcher and reuviewer refresh the mirror.
- Fixed-resource records now describe:
  - ReadyOS global/control bank;
  - launcher snapshot and launcher overlay;
  - ReadyShell cache `$40/$41/$42`, debug `$43`, scratch `$48`;
  - ReadyBASIC core/code `$44/$45`.
- Launcher now supports dynamic app snapshot allocation:
  - `APP_SLOT_CAPACITY` is `64`;
  - `MAX_APPS` is `65` including the optional disk launcher "load all" row;
  - `apps.cfg` entries start with `app_banks[idx] = 0`;
  - snapshot banks are allocated lazily when an app is loaded or launched;
  - the allocator scans logical banks `1..223`, skips duplicates, converts to
    physical with `skip + 2 + logical`, and skips physical banks that the
    resident `$C600` table marks non-free;
  - low banks still use the shim bitmap, while high banks are tracked through
    launcher state and the mirrored resident table.
- Disk launcher unload:
  - `F7` unloads the selected loaded app snapshot;
  - clears the low shim bitmap bit when applicable;
  - frees the physical bank in `$C600`;
  - clears the selected app bank, loaded flag, size, and matching hotkey
    binding.
- Cartridge launcher support:
  - embedded EasyFlash catalogs still describe preloaded apps from the
    cartridge table;
  - launcher now records cartridge-preloaded app banks in the resident bank
    table and treats them as loaded even when their logical bank is above the
    three-byte shim bitmap;
  - this prevents catalogs beyond 23 entries from being invisible to the
    launcher after boot.
- Launcher resume cache was tightened:
  - removed the duplicate resident `LauncherCatalogCacheV1` catalog copy;
  - launcher now saves/restores the real catalog arrays as segmented REU
    resume payloads;
  - schema bumped to `6` because no backward compatibility is required.
- Host/catalog tooling:
  - `build_support/build_apps_catalog_petscii.py` now accepts up to 64 app
    entries;
  - `verify.py` now recognizes the 64-entry dynamic contract and the expanded
    hotkey bank range;
  - `build_support/verify_dynamic_launcher.py` checks dynamic allocation,
    unload, 64-entry generation, load-all screen-row wrapping, and cartridge
    preloaded-state tracking.
- Added `build_support/verify_reu_control_bank.py` and wired it into
  `make verify`.
- Added `build_support/report_app_headroom.py` and generated
  `agentworkijg/reu_refactor_headroom_current.json`.

## Verification Log

- `make bin/launcher.prg bin/launcher_easyflash.prg`
  - passed after dynamic allocation changes;
  - EasyFlash launcher still reports unused-function warnings for disk-only
    paths excluded by the cartridge variant.
- `python3 build_support/verify_dynamic_launcher.py`
  - passed.
- `python3 verify.py`
  - passed after updating stale contract checks for the 64-entry dynamic
    launcher model.
- `make verify`
  - passed after final source changes;
  - includes `verify_reu_control_bank.py` and `verify_dynamic_launcher.py`.
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
- `make readybasic-demo-vice`
  - passed separately after fixing low-bank allocation;
  - previous Editor-return failure no longer reproduces.
- `make readybasic-vice-suites`
  - passed;
  - included demo, repeat-label, lifecycle, module-overlay, plugin-command,
    program, rbtest1, state, large-vars, cross-app resume, second-entry
    Editor, and full visual ReadyBASIC VICE suites.
- Experimental runtime bank-0 probe:
  - deferred;
  - direct VICE monitor writes to REU I/O registers did not reliably drive the
    live transfer registers, so the next probe should run C64-side code or use
    a proven monitor I/O-address-space command sequence.

## Next Work

- Add a runtime VICE probe for logical bank `0` contents.
- Add VICE coverage for disk launcher:
  - load all to REU;
  - load selected app lazily;
  - unload selected app and confirm reload gets a bank again;
  - browse/load an app manifest and then launch it.
- Add cartridge VICE coverage for app counts above 23 once a synthetic
  EasyFlash catalog fixture is added.
- Convert existing ReadyShell EasyFlash preload facts into generated dependency
  metadata before changing ReadyShell runtime bank use.
- Design the dependency manifest record as a build-time generated resource
  contract first. Do not implement arbitrary runtime dependency loading until
  ReadyShell/ReadyBASIC can consume the same record format.
