# REU Refactor Lessons Learnt

## 2026-06-02

- The refactor must be treated as a whole-system contract change. Old app,
  shim, EasyFlash, overlay, and micromodule binaries do not need compatibility
  support, but stale generated artifacts must be invalidated and rebuilt.
- Do not put bank-0 mirror/control code into `reu_mgr_init.c` until the size
  impact is proven. Many normal apps link that file, so doing so would risk
  broad code growth.
- First implementation target is mirror/audit, not authority: `$C600-$C7FF`
  remains runtime truth while logical bank `0` records are initialized and
  checked.
- ReadyShell cartridge preload already proves the desired dependency concept:
  app resources can be loaded before app entry. The first step is to describe
  those dependencies as generated records, not to redesign ReadyShell.
- The fixed-resource mirror must describe every fixed resource that the
  resident bank table marks. Missing ReadyShell scratch `$48` from the compact
  records made the mirror internally incomplete even though the bitmap table
  was correct.
- EasyFlash verification must be rerun after launcher-control changes because
  the cartridge launcher is a separate binary and preload behavior is separate
  from the disk launcher path.
- A passed shim verifier is the hard guardrail for this phase: the bank `0`
  mirror work can change launcher/reuviewer behavior, but must not grow or
  reinterpret the `$C800-$C9FF` shim ABI.
- Runtime REU-content verification should use C64-side code or a proven VICE
  monitor I/O-address-space sequence. A quick monitor-side attempt to poke
  `$DF01-$DF0A` did not reliably change the live REU transfer registers, so it
  is not a sound basis for accepting the bank `0` runtime contents.
- ReadyBASIC is currently the tightest app-window binary in the generated
  report, with 1031 bytes of headroom. Any later shared-library change that
  links into normal apps needs a before/after report, not just a successful
  rebuild.
