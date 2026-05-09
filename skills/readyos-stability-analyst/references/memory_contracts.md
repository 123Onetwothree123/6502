# ReadyOS Memory Contracts

Canonical sources:
- `MEMORY_MAP.md`
- `build_support/memory_map_spec.json`

## Critical RAM windows
- App runtime snapshot: `$1000-$C5FF` (`$B600` bytes)
- REU metadata/system table: `$C600-$C7FF`
- Shim resident region: `$C800-$C9FF`
- Hardware I/O: `$D000-$DFFF`

## Shim jump/data anchors
- Jump table starts at `$C800`
- Shim data window: `$C820-$C83F`
- Core logical-bank state bytes: `$C834-$C838`
- Physical REU region skip byte: `$C83B`

## REU physical/logical bank contract
- `Start` means physical REU bank `READYOS_REU_BANK_SKIP`.
- `Start+0` is the system/global bank.
- `Start+1` is the launcher snapshot/resume bank; app-visible logical bank `0`.
- `Start+2` is reserved for future launcher overlays and is typed as launcher-owned.
- `Start+3..Start+25` hold logical app banks `1..23`.
- `Start+26+` is the dynamic allocation pool.
- The shim bitmap width remains 24 logical bits; app ABI-visible bank numbers are unchanged.

## ReadyShell overlay contract
- `__HIMEM__ = $C600`
- Overlay size is profile-based:
- release/default (`READYSHELL_PARSE_TRACE_DEBUG=0`): `READYSHELL_OVERLAYSIZE = $3800`, `__OVERLAYSTART__ = $8E00`
- debug trace (`READYSHELL_PARSE_TRACE_DEBUG=1`): `READYSHELL_OVERLAYSIZE = $3B00`, `__OVERLAYSTART__ = $8B00`
- ReadyShell fixed REU bank ownership:
- `0x40` -> ReadyShell overlay cache bank for overlays 1, 2, 3, and 5
- `0x41` -> ReadyShell overlay cache bank for overlays 4, 6, 7, and 8
- `0x43` -> `REU_RS_DEBUG` (debug/probe region `0x43F000+`)
- `0x48` -> ReadyShell scratch, registry, metadata, and value arena
- These banks must not be handed out by dynamic allocation.
- Overlay REU cache offsets:
- `0x400000+` overlays cached in bank `0x40`
- `0x410000+` overlays cached in bank `0x41`
- `0x43F000` debug head
- `0x43F010` debug ring data
- `0x480000+` ReadyShell shared scratch/registry/value arena

Profile control commands:
- build release/default: `make -j1 READYSHELL_PARSE_TRACE_DEBUG=0`
- build debug trace: `make -j1 READYSHELL_PARSE_TRACE_DEBUG=1`
- verify release/default contract: `READYSHELL_PARSE_TRACE_DEBUG=0 python3 build_support/verify_memory_map.py`
- verify debug contract: `READYSHELL_PARSE_TRACE_DEBUG=1 python3 build_support/verify_memory_map.py`

## Hard gates
- `python3 build_support/verify_memory_map.py`
- `python3 build_support/verify_resume_contract.py`
- `python3 verify.py`

Contract drift in shim/app/REU reserved windows is a blocking failure.
