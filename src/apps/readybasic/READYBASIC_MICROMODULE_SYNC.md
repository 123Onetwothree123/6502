# ReadyBASIC Micromodule Sync Ledger

ReadyBASIC now duplicates a small amount of ReadyOS REU and shim knowledge in assembler. Keep this file updated whenever either side changes.

## REU DMA Registers

- ReadyBASIC source: `src/apps/readybasic/readybasic.s`
- Mirrored concepts from:
  - `src/lib/reu_mgr_dma.c`
  - `src/lib/reu_mgr.h`
- Constants:
  - `$DF01`: command register.
  - `$DF02-$DF03`: C64 address.
  - `$DF04-$DF05`: REU offset.
  - `$DF06`: REU bank.
  - `$DF07-$DF08`: transfer length.
  - `$90`: C64 to REU stash.
  - `$91`: REU to C64 fetch.

## Fixed ReadyBASIC REU Banks

- ReadyBASIC assembler:
  - `RB_REU_CORE_BANK = $44`
  - `RB_REU_CODE_BANK = $45`
  - `RB_REU_TYPE_CORE = 14`
  - `RB_REU_TYPE_CODE = 15`
- ReadyOS C mirrors:
  - `src/lib/reu_mgr.h`
  - `src/lib/reu_mgr_init.c`
  - `src/apps/reuviewer/reuviewer.c`
- Static checker:
  - `build_support/verify_readybasic_plugin.py`

## Shim / Resume Boundary

- ReadyBASIC still uses:
  - `SHIM_RETURN = $C80C`
  - bridge state at `$C000-$C1BD`
  - shared frames and visible helper shadow at `$C200-$C5FF`
  - app runtime zero-page/stack save in REU bank `$44` offsets `$0A00/$0B00`
- Do not place ReadyBasic state in `$C800-$C9FF`; that remains shim ABI territory.
- Do not use `$C600-$C7FF` as ReadyBASIC scratch; it remains ReadyOS REU metadata.

## Banking Discipline

- Visible resident code calls BASIC ROM helpers only with normal `$01=$37`.
- Hidden helper and hidden worker calls set low CPU port bits for RAM under BASIC while keeping KERNAL visible.
- Any future hidden worker that needs KERNAL calls must preserve this mode and restore `$01`.
- Any future worker that disables KERNAL too needs its own ledger entry and a tighter trampoline contract.

## Future Full-System Commands

The current plugin spine can support a command that takes over most of the machine only if the command returns through ReadyBasic's resident completion path. A custom suspend/resume command that bypasses the launcher would need new ABI notes; a command that wants ReadyOS-visible app switching or global storage still needs shim/launcher-level coordination rather than only plugin changes.
