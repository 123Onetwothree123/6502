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
- A 64-entry launcher catalog has a real RAM cost. The first dynamic
  implementation accidentally doubled that cost with a resident
  `LauncherCatalogCacheV1` resume copy and dropped launcher headroom by 8583
  bytes. Saving the real arrays as segmented REU resume payloads recovered
  more than 5.5KB and left the accepted launcher delta at 3060 bytes.
- Low logical app banks cannot be treated as permanently unavailable just
  because the bank table marks their physical slots `REU_RESERVED` at boot.
  For the dynamic app allocator, low logical banks `1..23` remain valid app
  snapshot candidates so the existing loaded-bank bitmap and switch behavior
  stay useful for normal catalogs.
- Do not implement manifest dependency loading by adding a broad runtime parser
  to the launcher. The stable path is generated dependency/resource records
  first, then ReadyShell and ReadyBASIC consumers, then runtime manifest syntax
  only when the binary contract is boring.
- The shim bitmap remains a three-byte low-bank compatibility field. Any
  cartridge or dynamic path that uses logical banks above 23 must record loaded
  state outside the shim bitmap and must not expect `set_bitmap` to represent
  those banks.
- Cartridge preload has its own correctness boundary. The booter can stash
  logical banks above 23, but the launcher must explicitly mark embedded
  preloads as loaded and mirror their physical banks into `$C600`/bank `0`.
- Load-all UI code that was harmless with 23 app slots can become unsafe with
  64. Progress/status displays must wrap or window visible rows rather than
  writing unique rows for every catalog entry.
- Normal app impact stayed at 0 or 1 byte only because dynamic allocator and
  bank `0` mirror code stayed out of shared app libraries. Keep that boundary.
- Unload belongs to the launcher or future ReadyOS manager. The shim remains a
  direct-bank transfer primitive and must not grow owner/free-list policy.
- ReadyShell overlay cache banks can be dynamic without making ReadyShell own
  allocation. The launcher/loader should allocate the `rsovl` banks, write the
  existing `$4880F0` metadata block, and let ReadyShell consume only the bank
  ids it needs.
- Preserve ReadyShell's slot geometry when changing ownership. Keeping
  `+$0000`, `+$3800`, `+$7000`, `+$A800` avoided a broad ReadyShell rewrite and
  confined app impact to metadata read/registry patching.
- Do not use the shim app preload path for ReadyShell overlay sidecars. They
  are PRGs for the `$8E00-$C5FF` overlay window, not normal app snapshots, so
  the disk launcher needs a small streaming loader into the assigned REU slots.
- Once a resource set is loader-owned, do not leave an app-side fallback that
  silently recreates ownership. Removing ReadyShell's overlay self-loader made
  metadata failure explicit and improved resident headroom.
- Cartridge/EasyFlash dynamic banks must be generated, not guessed. The boot
  assembly can still preload ReadyShell overlays, but its cache bank constants
  now come from generated layout artifacts.
- The ReadyShell `$48` scratch/state/value bank intentionally stayed fixed in
  this phase. Moving overlay cache banks first kept the resource refactor small
  enough to verify with host tests, disk VICE probes, and EasyFlash smoke.
