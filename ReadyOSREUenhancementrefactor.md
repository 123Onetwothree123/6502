# ReadyOS REU Enhancement Refactor Plan

## Purpose

This plan describes a future refactor that turns logical REU bank `0` into a
ReadyOS control bank while preserving the current ReadyOS memory contracts,
especially the resident shim and shim-adjacent metadata area.

The intended long-term end state is:

- logical REU bank `0` is the canonical ReadyOS REU control bank;
- the resident `$C600-$C9FF` area remains small, fixed, and ABI-stable;
- the shim itself does not grow;
- app snapshots, overlays, modules, clipboard payloads, ReadyShell resources,
  ReadyBASIC resources, and app-requested banks are tracked by owner;
- apps can be loaded/preloaded dynamically instead of being tied to fixed app
  banks;
- ReadyOS can eventually support more app catalog entries, with an initial
  target of up to `64`;
- future app/service invocation has reserved design space for REU-backed
  request/result data, including headless calls and modal UI service calls such
  as shared file open/save dialogs;
- all changes are proven against before/after code size, BSS, heap/headroom,
  overlay, micromodule, suspend/resume, and launcher/shim behavior.

This document is now both the plan and the source-of-truth implementation
tracker for the REU enhancement refactor. Completed implementation status is
recorded explicitly; future design notes remain design notes until marked
implemented here.

## Implementation Status 2026-06-02

Completed in branch `codex/reu-control-bank-refactor`:

- committed baseline `e7b5487 Add REU control bank mirror baseline`;
- logical REU bank `0` mirror schema `RCB0`, version `1`;
- header at bank `0` offset `$0000`;
- resident `$C600-$C6FF` bank table mirror at offset `$0100`;
- fixed-resource records at offset `$0200`;
- launcher and reuviewer mirror writers;
- no shim growth and no `$C800-$C9FF` ABI expansion;
- 64 app catalog capacity for disk-generated `apps.cfg`;
- lazy app snapshot logical-bank allocation in the launcher;
- no preallocated app banks in disk catalog entries;
- disk launcher `F7` unload for selected loaded app snapshots;
- load-all progress display wraps visible rows safely for 64-entry catalogs;
- global hotkeys accept logical app banks through `223`;
- cartridge launcher records embedded preloaded apps as loaded even above the
  shim bitmap range;
- launcher duplicate resident catalog resume cache removed; launcher now saves
  catalog arrays as segmented REU resume payloads;
- dynamic launcher static verifier added to `make verify`.

Not implemented yet:

- generic manifest dependency loading for overlays/modules/resources;
- dynamic ReadyShell resource banks;
- dynamic ReadyBASIC resource banks;
- ownership records rich enough to unload every bank owned by an app;
- headless/service/modal invocation records;
- runtime VICE probe that reads and validates logical bank `0` contents.

Important correction: the current implementation supports lazy app snapshot
allocation and 64-entry catalogs. It does not yet implement the full dependency
manifest/resource ownership architecture. That is intentional; implementing an
arbitrary dependency loader before ReadyShell and ReadyBASIC share a generated
resource contract would be unstable and likely to bloat the launcher.

Current measured dynamic-allocation headroom impact against the committed bank
`0` mirror baseline:

- launcher: `11122` bytes to `8062` bytes, `-3060`;
- normal apps: unchanged or `-1` byte from the broadened shared hotkey helper;
- ReadyBASIC remains at `1031` bytes;
- Dizzy remains at `1834` bytes;
- ReadyShell remains at `16585` bytes measured by its main runtime/heap model.

The launcher cost is the real cost of holding a 64-entry catalog in RAM. A
larger hidden duplicate was removed before acceptance: the initial dynamic
implementation dropped launcher headroom by `8583` bytes, and removing the
duplicate resident resume cache recovered more than `5.5KB`.

### Verification Matrix

Static/build verification passed for this milestone:

- `make verify`;
- `make easyflash-verify`;
- `python3 verify.py`;
- `python3 build_support/verify_reu_control_bank.py`;
- `python3 build_support/verify_dynamic_launcher.py`;
- `python3 build_support/report_app_headroom.py --output agentworkijg/reu_refactor_headroom_current.json`.

VICE verification passed for this milestone:

- `make readybasic-vice-suites`;
- `make readybasic-demo-vice`;
- EasyFlash VICE smoke through `make easyflash-verify`.

The aggregate `make readybasic-vice-suites` target includes demo, repeat-label,
lifecycle, module-overlay, plugin-command, program, rbtest1, state, large-vars,
cross-app resume, second-entry Editor, and full visual ReadyBASIC VICE suites.

New VICE coverage still needed after this milestone:

- disk launcher lazy-load selected app, return, and relaunch;
- disk launcher load-all with a synthetic 64-entry catalog;
- disk launcher unload selected app, verify bank table/free state, then reload;
- disk launcher browse/load `app.*` manifest and launch the added app;
- cartridge launcher synthetic catalog above 23 entries, proving high logical
  app banks are marked loaded without shim bitmap bits;
- runtime bank `0` content probe that validates header, `$C600` mirror, and at
  least one dynamic app-bank allocation record after load/unload.

## Principal Engineering Corrections

The broad goal is sound, but the implementation must be narrower than a full
"dynamic OS registry" rewrite. The safest path is to make logical REU bank `0`
useful as an auditable control record first, then promote pieces of it to
runtime authority only after the old path and the new path can be compared.

Corrected principles:

- Do not start by replacing the `$C600-$C7FF` table. Start by mirroring and
  validating it.
- Do not make every app link a new manager library. Keep manager code in the
  launcher, boot/cartridge loader, reuviewer, and dedicated test utilities.
- Do not invent a rich manifest language early. Start with fixed-width records
  generated by the build, then add manifest syntax only when one real app needs
  it.
- Do not make app id lookup part of suspend/resume hot paths until the resolved
  physical bank path is proven.
- Do not move ReadyShell or ReadyBASIC fixed banks until generic app snapshots
  and clipboard ownership are stable. This is a sequencing rule, not a
  backward-compatibility requirement.
- Do not implement unload, eviction, headless services, or modal services in the
  first tranche. Reserve schema space and validate the direction, but keep them
  non-goals until the core allocator is boring.
- Do not allow the refactor to reduce app headroom through shared helper bloat.
  Any helper pulled into normal apps must have a measured size budget.

The first valuable result should be observability and correctness: ReadyOS can
describe who owns REU banks, prove that this description matches the live shim
and `$C600` state, and do so without changing app behavior.

## Non-Negotiable Contracts

### Whole-System Rebuild Assumption

ReadyOS does not need binary compatibility with older app builds, older shim
images, older EasyFlash loader images, or older ReadyBASIC micromodule layouts.
All apps, micromodules, overlays, launcher variants, boot paths, and cartridge
artifacts may be rebuilt together against one new contract.

This removes the need for compatibility shims for old binaries. It does not
remove the need for discipline:

- every generated artifact must be rebuilt from one coherent contract;
- every app must still fit the `$1000-$C5FF` runtime window;
- every app must still avoid `$C600-$C9FF` as private memory;
- every app must pass memory/headroom comparison after contract changes;
- disk and EasyFlash paths must agree on the same generated REU contract;
- ReadyShell overlay metadata and ReadyBASIC micromodule/submodule metadata must
  be updated in the same change as their code;
- stale generated artifacts must be treated as invalid, not supported.

Prefer a clean versioned contract over compatibility glue. If an ABI changes,
update all producers and consumers together, then verify the complete rebuilt
system.

### C64 RAM Layout

The existing ReadyOS runtime memory map remains the baseline contract:

- app runtime window: `$1000-$C5FF`
- ReadyOS REU metadata/system table: `$C600-$C7FF`
- resident shim ABI: `$C800-$C9FF`
- hardware I/O region: `$D000-$DFFF`

The active app owns `$1000-$C5FF`. The app snapshot saved to REU is still
`$B600` bytes unless a later, explicitly validated change says otherwise.

The resident `$C600-$C9FF` range is not app scratch. ReadyBASIC, ReadyShell,
normal C apps, overlays, and micromodules must continue to treat it as ReadyOS
resident state.

### Shim Constraint

The shim at `$C800-$C9FF` must not grow.

The shim remains a small execution primitive:

- load from disk and run;
- fetch from REU and run;
- preload/stash/fetch the app window;
- return to launcher;
- switch apps;
- use the existing compact shim data bytes for immediate bank/run state.

The shim must not become a full allocator, app registry, manifest parser,
overlay registry, or service dispatcher.

### Shim-Adjacent 1KB Clarification

For this plan, "shim-adjacent 1KB" means the full resident ReadyOS control area:

- `$C600-$C7FF`: current REU allocation table and system metadata;
- `$C800-$C9FF`: resident shim jump table, data bytes, and helper routines.

This 1KB is precious and resident. It should hold only hot state and ABI fields
needed for fast switching and compatibility. The full REU registry eventually
moves to logical REU bank `0`, after mirror/audit phases prove the model.

The new model is:

- logical REU bank `0` becomes the long-form control record;
- `$C600-$C7FF` remains the fast resident state during the early phases;
- `$C800-$C9FF` is still the shim ABI and remains size-fixed;
- duplicate state is allowed when it keeps the shim simple.

Do not make bank `0` canonical on day one. During the first phases, the
canonical runtime truth remains the existing resident path and bank `0` is a
mirror plus audit record. Promote bank `0` to canonical authority only after the
mirror has survived boot, preload, app switching, cartridge preload, and
ReadyShell/ReadyBASIC runs without divergence.

### Boot And Verification Rules

ReadyOS must continue to be built and verified through the normal full system
flow. Do not validate this refactor by launching individual apps directly.

Use normal ReadyOS boot paths, including disk and EasyFlash/cartridge paths as
appropriate. Preserve the project rule that normal verification goes through
plain `run.sh` / `run.ps1`, not single-app load modes.

### cc65 And C64 Constraints

Implementation should prefer `unsigned char` and `unsigned int`. Avoid `long`
and large stack locals in hot paths. Inline asm should stay conservative and
explicit. Do not stomp cc65 runtime zero page, especially `$02-$1B`.

Any change crossing C/asm boundaries must keep the calling convention explicit
and small.

## Current Baseline Summary

The current code reserves the first ReadyOS logical REU bank but does not yet
use it as a rich control plane.

Current effective REU model:

- physical bank base is controlled by `READYOS_REU_BANK_SKIP`;
- current generated config uses a skip value of `32`;
- `REU_READYOS_GLOBAL_PHYSICAL()` maps to `skip + 0`;
- launcher snapshot maps to `skip + 1`;
- launcher overlay reserve maps to `skip + 2`;
- current app slots map through fixed logical-to-physical assumptions;
- `$C600-$C7FF` contains a 256-byte bank type table and system metadata;
- `$C836-$C838` contains the shim loaded-bank bitmap for current app-slot
  assumptions;
- ReadyShell uses fixed banks such as `$40`, `$41`, `$42`, `$43`, and `$48`;
- ReadyBASIC uses fixed banks `$44` and `$45`;
- some comments and docs still carry older "launcher bank 0" wording.

Long term, this plan changes bank `0` from a mostly reserved marker into the
canonical ReadyOS control bank. Early phases only mirror and audit the existing
resident runtime facts.

## Target Architecture

### Logical REU Bank 0 As ReadyOS Control Bank

Logical REU bank `0` should become a versioned control bank. It stores the
eventual canonical registry and ownership state that is too large or too
structured for the resident 1KB area. It should not become runtime authority all
at once.

Suggested long-term bank `0` layout:

```text
$0000-$00FF  control header, schema, flags, bank skip, totals, checksums
$0100-$01FF  resident export/mirror image for $C600-$C7FF hot state
$0200-$05FF  app registry, target initial capacity 64 entries
$0600-$0DFF  resource registry for app overlays, modules, data, heaps
$0E00-$11FF  256-bank ownership table
$1200-$17FF  invocation records for headless/modal/full service calls
$1800-$1FFF  result/status records, diagnostics, service return state
$2000-$FFFF  parameter/result payload arena and future variable records
```

This is a map of possible future regions, not permission to build all regions
immediately. The first implemented schema should be much smaller:

```text
$0000-$003F  header: magic, schema, flags, generation, bank skip, table sizes
$0040-$00FF  reserved, zero-filled
$0100-$01FF  mirror of current $C600-$C6FF bank type table
$0200-$027F  compact fixed-resource records for current launcher/ReadyShell/
             ReadyBASIC/clipboard assumptions
$0280-$02FF  audit/status records and divergence counters
```

Everything beyond that should remain reserved until a phase needs it. Reserved
bytes must be zero-filled and verified so later schema expansion has a known
starting point.

The exact offsets should be finalized in a dedicated C header. Add assembler
includes only for fields that assembler actually reads. Avoid spreading bank `0`
offset constants into many assembler files.

### Canonical Versus Hot State

State should be split deliberately:

- long-form registry/audit record: logical REU bank `0`;
- hot resident runtime state: `$C600-$C7FF`;
- shim immediate fields: existing bytes in `$C800-$C9FF`;
- app-local state: optional temporary copies while an app runs.

The resident path remains authoritative until a later explicit phase promotes
bank `0` to authority for a specific subset of state. The promotion must be
piecemeal: for example, bank ownership may become canonical before app launch
resolution, and app launch resolution may become canonical before subsystem
resources.

Any duplicated field needs a documented owner:

- allocator changes update the resident table and then mirror to bank `0` in
  early phases;
- after promotion, allocator changes update bank `0` and then export selected
  hot fields to `$C600-$C7FF`;
- shim fields are written immediately before shim calls;
- app return/suspend paths update only the minimal records needed for the next
  dispatch.

Avoid read-modify-write cycles against all of bank `0`. Every API should update
small fixed ranges and maintain a generation byte/counter for debugging.

### Bank Ownership Model

Every allocated REU bank needs an ownership record. A one-byte type table is no
longer enough for unload and dynamic resource management.

Suggested long-term bank ownership fields:

```text
state        free, used, reserved, pinned, unavailable
owner_kind   system, launcher, app, service, readyshell, readybasic, clipboard
owner_id     app id, service id, subsystem id, or 0
role         snapshot, overlay, module, heap, clipboard, scratch, parameter
resource_id  resource registry index or 0xff
flags        dirty, evictable, preload, cartridge-backed, shared, volatile
```

For the first implementation, prefer a smaller fixed record to avoid parsing
and code-size bloat:

```text
bank         physical bank number
type         existing REU_* type id
owner_kind   compact owner enum
owner_id     compact owner/app/subsystem id
role         compact role enum
flags        compact flags byte
```

Do not store strings in per-bank records. Names belong in build-time catalogs,
launcher-local catalog text, or optional later resource records. Bank ownership
must be cheap to scan and cheap to validate.

This enables future unload behavior:

```text
free every bank where owner_kind == app and owner_id == selected app id
```

It also allows partial cleanup:

- unload only app overlays;
- free only temporary service banks;
- preserve app snapshot but drop evictable resources;
- release clipboard payload chains;
- free ReadyShell or ReadyBASIC resources through subsystem ownership.

### App Identity Versus Bank Location

The refactor must separate:

- app identity;
- app catalog position;
- runtime instance/suspended state;
- physical REU snapshot bank;
- overlay/resource banks;
- hotkey slot.

Current bank numbers do too much. The target model uses:

- stable app token, such as `readyshell`;
- compact runtime `app_id`, target range `0..63`;
- snapshot bank assigned dynamically;
- resource entries assigned dynamically;
- hotkeys point to app ids, not banks.

The shim should receive already-resolved bank numbers. It should not resolve
app ids.

Important correction: `64` is a catalog capacity target, not an immediate
loaded/suspended app target. Runtime REU can hold many snapshots, but the C64
resident UI and launcher state should not grow just because the catalog can
describe more apps. The first target is "more than fixed slots can be described
and loaded on demand," not "64 apps are all preloaded and hot at once."

## Dynamic Loading And Preloading

### App Load Policies

Catalog or manifest data should describe load policy independently of fixed bank
placement.

Long-term load policies:

```text
on_demand
preload_snapshot
preload_required_resources
preload_all_resources
cartridge_preloaded
```

The same allocator/register path should be used by:

- EasyFlash/cartridge preload;
- launcher load-all-to-REU;
- one-by-one launcher preload;
- on-demand app selection;
- future app manifest resource loading.

The goal is that all paths produce the same logical bank `0` registry shape.

Early implementation should support only the current behavior expressed through
the new records:

- normal launcher preload;
- launcher load-all-to-REU;
- cartridge preload;
- on-demand app load if already supported by the existing path.

Do not add new load policy behavior until these existing paths produce matching
audit records.

### App Kinds

Long-term app kinds:

```text
regular
resource_preload
headless_capable
service
service_headless_only
service_modal_ui
```

App kind is a capability and dispatch hint. It must not replace the normal
resource ownership model.

Do not implement these kinds early. Existing apps remain existing apps. The only
near-term app metadata should be enough to identify the app, its current
snapshot bank, and whether its currently known resources are fixed or dynamic.

### Manifest Resources

Apps should be able to declare resources such as overlays and modules.

Suggested resource fields:

```text
app token / app id
resource id
resource name
resource type: overlay, module, data, heap, help, dialog, service-temp
required flag
preload group: minimal, normal, full, debug
source kind: disk, cartridge, generated, runtime
source file or cartridge descriptor
load address or target C64 address
REU bank and offset after allocation
size
flags: pinned, evictable, shared, dirty, compressed
```

ReadyShell overlays should eventually move from hard-coded banks to resource
registry lookups. ReadyBASIC command/module banks should eventually do the same,
but only after the lower-risk C paths are proven.

The important near-term concept is dependency preloading, not a large manifest
language. An app may have a compact dependency list that the loader satisfies
before entering the app:

```text
app snapshot
required overlays
required command modules
required data/help resources
optional preload groups
```

This already exists in spirit in the EasyFlash ReadyShell path: the cartridge
version preloads ReadyShell overlays, including command overlays, before
ReadyShell runs. The future disk/load-all/on-demand paths should converge on
that same principle. The difference is that the dependency list should become
data generated by the build instead of hard-coded bank constants.

ReadyBASIC should use the same dependency model for modules and micromodule
payloads: core/runtime resources plus required command/module resources are
declared as dependencies and loaded or confirmed before entering ReadyBASIC.

Avoid a general-purpose manifest parser in the C64 runtime. Prefer build-time
generation of compact resource records. If human-authored manifests are added,
parse them on the host and emit a PETASCII/binary record format that the C64 can
consume with small, bounded code.

## Service Invocation

### Unified Invocation Model

Headless app calls and modal UI calls should share one invocation mechanism.

Suggested invocation modes:

```text
headless
modal_ui
full_ui_handoff
background_later
```

Suggested capability flags:

```text
service
headless
modal_ui
reu_params
returns_result
no_screen_touch
caller_redraw_required
os_screen_save_supported
```

### Future-Proofing Status

Headless and modal UI service invocation are included here as future-proofing.
They should shape the bank `0` schema so the later service model is not boxed
out, but they are not part of the first implementation milestone.

Do not let the headless/service design delay the first practical REU ownership
work. The early phases should reserve schema space and define stable concepts;
actual service apps can come later after bank ownership and dynamic snapshot
allocation are proven.

Principal correction: service invocation should not affect the initial bank `0`
schema beyond a reserved region and a schema version note. It should not add
resident fields, app code, or launcher dispatch code in the core REU ownership
tranche.

### Headless Flow

Headless calls allow one app to invoke another app/service without visible user
interaction.

Flow:

1. Caller allocates or selects a request buffer in REU.
2. Caller writes request metadata and payload.
3. Caller asks ReadyOS to invoke a target app/service headlessly.
4. ReadyOS stashes caller state.
5. ReadyOS loads or fetches target app/service.
6. Target reads invocation block and request payload.
7. Target does its work without touching screen/keyboard unless explicitly
   allowed.
8. Target writes result/status to REU.
9. Target returns through ReadyOS.
10. ReadyOS restores the caller.
11. Caller reads the result.

Headless apps must be opt-in. Arbitrary existing apps should not be treated as
headless-safe.

### Modal UI Service Flow

Modal UI service calls use the same request/result mechanism but allow the
callee to present UI.

Example services:

- file open dialog;
- file save dialog;
- drive/path picker;
- confirmation dialog;
- text input dialog;
- clipboard picker;
- help viewer;
- search dialog.

Initial file save request example:

```text
operation: save
suggested filename
default drive/path
file type: SEQ, PRG, REL, USR
filters
payload bank/offset
payload size
format id
overwrite policy
```

Initial result example:

```text
status: saved, cancelled, error
chosen filename
chosen drive/path
bytes written
DOS status code
error token or short error text
```

For the first modal implementation, use the simplest screen contract:

- service may draw;
- caller redraws after return.

Later, optional OS save/restore of screen RAM and color RAM can be added for
services that need invisible UI preservation. Because the app snapshot window
does not include normal screen RAM or color RAM, this must be explicit.

## Shim And Shim-Adjacent Implementation Strategy

### Keep Shim Unchanged In Size

The shim should continue to operate on direct bank values.

The launcher or ReadyOS manager resolves:

```text
app id -> snapshot bank -> write existing shim target bank -> call shim
```

The shim does not need to know about:

- app count;
- app manifests;
- resource names;
- bank ownership records;
- service invocation records;
- dynamic overlay lookup;
- unload logic.

### Resident Cache Design

Long term, the `$C600-$C7FF` resident area can become a cache/export area rather
than the full canonical database. Early on, it remains the runtime truth and is
mirrored into bank `0`.

It should keep only hot fields such as:

- magic/schema/cache version;
- dirty flags;
- current app id;
- current app snapshot physical bank;
- launcher snapshot physical bank;
- selected target physical bank;
- compact loaded-state cache for currently visible app range;
- bank skip;
- service invocation active flag;
- current request/result index;
- small subsystem root indexes.

This list is intentionally aspirational. Before adding any field to
`$C600-$C7FF`, prove that a current field can be reused or that the new field is
strictly necessary for a hot path. The resident area is harder to recover than
bank `0` and must not become a dumping ground.

The existing shim bitmap can either remain as a compatibility cache or become a
windowed loaded-state cache. It does not need to represent every future app if
the launcher/manager writes the exact target bank before calling the shim.

### Limited Copy From Bank 0

When the launcher needs a range of app registry state, it should DMA a limited
range from logical bank `0` into resident or app-local buffers.

Examples:

- copy visible menu page app entries;
- copy app id to snapshot bank table for current page;
- copy one app's resource descriptors before preloading;
- copy invocation block before dispatch;
- copy ownership records for one app during unload.

This accepts a small performance tax for keeping the shim fixed.

The copy code must be bounded and explicit. Avoid generic copy-by-record-name
interpreters on the C64. Prefer helper functions such as "copy one app record",
"copy bank table page", or "copy resource records for app id".

### Consistency And Recovery

Duplicated state creates a new failure class: `$C600`, shim fields, and bank `0`
can disagree. The design must make disagreement detectable and recoverable.

Minimum consistency fields:

- schema version;
- generation counter;
- last writer id, such as boot, launcher, easyflash loader, reuviewer, test;
- dirty/in-progress flag;
- small divergence counter or last divergence code.

Early implementation should avoid expensive checksums in hot C64 paths. A
simple magic/version/generation check is enough for runtime. Host tools and
debug builds can compute deeper checksums over the bank `0` records.

Update sequence for early mirror mode:

1. update existing resident state;
2. mark bank `0` mirror update in progress;
3. copy the changed fixed range to bank `0`;
4. increment generation;
5. clear in-progress flag.

If bank `0` is missing, stale, or marked in-progress after a reset, ReadyOS
should rebuild it from the resident/runtime facts where possible. This is why
bank `0` should not become canonical until the mirror path is proven.

When bank `0` eventually becomes canonical for a subset of state, define a
separate commit sequence for that subset before implementation. Do not infer the
commit rule from the mirror-mode path.

## ReadyShell Plan

ReadyShell currently uses fixed REU banks for overlay cache/debug/scratch/value
arena behavior. The target is to move those to resource records.

ReadyShell should not be the first subsystem converted. It is too central and
has tight resident/overlay margins. Use it first as a reporting target: bank `0`
should describe the existing ReadyShell fixed resources, and tests should prove
that the description matches reality. Only later should ReadyShell consume
dynamic bank values.

The EasyFlash ReadyShell path is the model to preserve and generalize. It
already preloads ReadyShell overlays, including command overlays, before
ReadyShell runs. The refactor should first express those existing preloaded
overlays as generated dependency/resource records, then make disk preload and
launcher load-all use the same dependency list.

Phases:

1. Add generated dependency/resource records that describe the existing
   EasyFlash-style ReadyShell preloaded overlays and fixed banks without
   changing behavior.
2. Verify cartridge preload, disk preload, and launcher load-all can report the
   same ReadyShell dependency set.
3. Teach ReadyShell to read bank values from a small runtime config block.
4. Populate that config block from logical bank `0` before ReadyShell runs.
5. Convert overlay fetch paths from fixed constants to config values.
6. Convert debug/probe/scratch/value-arena locations after overlay fetches are
   stable.
7. Update host-side ReadyShell REU tests to validate dynamic resource records.

Guardrails:

- do not reduce resident ReadyShell heap headroom materially;
- do not increase overlay payloads beyond current overlay headroom limits;
- keep overlay load address behavior unchanged unless separately proven;
- keep a fixed-bank transition mode until generated dependency lookup passes
  both host tests and VICE runtime tests. This is for staged validation of the
  new contract, not for old binary compatibility.

## ReadyBASIC And Micromodule Plan

ReadyBASIC is higher risk because it duplicates ReadyOS REU/shim knowledge in
assembler and uses command micromodules/submodules.

Current documents that must stay in sync include:

- `src/apps/readybasic/READYBASIC_MICROMODULE_SYNC.md`;
- `src/apps/readybasic/READYBASIC_CURRENT_DESIGN.md`;
- `src/apps/readybasic/READYBASIC_LIFECYCLE_AND_REU_ARCHITECTURE.md`;
- `src/apps/readybasic/REadyBASICCommandModuleAndSubmodulePlan.MD`;
- `docs/readybasic_memory_diagrams.html` generated by the memory report.

ReadyBASIC migration phases:

1. Add logical bank `0` records for existing fixed ReadyBASIC core/code banks
   `$44` and `$45`, plus generated dependency records for known module and
   micromodule payloads, but keep behavior fixed.
2. Verify ReadyBASIC dependency records match the currently generated module and
   micromodule artifacts.
3. Add a small ReadyBASIC runtime config block in visible RAM or an existing
   frame area below `$C600` containing resolved core/code/module bank values.
4. Fill that config block during ReadyBASIC cold entry or before app handoff.
5. Change assembler constants to read from config where feasible, one path at a
   time.
6. Keep command micromodule/submodule load addresses and under-ROM slots stable
   until a specific whole-system contract update changes them.
7. Update micromodule sync docs after each proven ABI shift.
8. Only after C apps, clipboard, and ReadyShell are stable should ReadyBASIC
   banks become dynamically assigned.

Principal correction: ReadyBASIC should not be used to prove the generic
allocator. Its assembler constants, runtime stack/ZP snapshots, typed heap, and
micromodule layout make it a late-stage compatibility consumer. The first
ReadyBASIC work should be read-only reporting and config-block proof, not
dynamic reassignment.

ReadyBASIC must continue to treat:

- `$C600-$C7FF` as ReadyOS metadata/cache only;
- `$C800-$C9FF` as ReadyOS shim ABI only;
- command micromodule memory below `$C600` and under-ROM slots as explicitly
  documented.

## Clipboard Plan

Clipboard is a good early dynamic subsystem.

Target behavior:

- clipboard banks are dynamically allocated;
- owner kind is `clipboard` or `system`;
- records identify payload chains and formats;
- clipboard root descriptor lives in logical bank `0` or resident cache;
- unload/cleanup can free clipboard payloads by owner/role.

Clipboard should move before ReadyShell and ReadyBASIC because it has less
assembler coupling and should prove the ownership model.

## App Count Expansion

The target app catalog capacity is `64`, but this should be reached in stages.

This is lower priority than correctness of dynamic ownership. Do not expand UI
capacity and allocator behavior in the same phase. First prove that current apps
can be represented by app id and resolved bank; then prove dynamic snapshot
allocation for the current catalog; only then raise catalog capacity.

Required changes:

- app ids become independent from REU banks;
- hotkeys point to app ids;
- app catalog parsing supports more entries;
- launcher menu/page logic supports more entries;
- loaded-state tracking no longer depends on a 24-bit fixed app bitmap;
- app preload and on-demand load paths allocate snapshot banks dynamically;
- reuviewer displays app ownership records instead of fixed app slot ranges;
- verifier no longer assumes app slots are only fixed banks `2-25`.

The shim can stay unchanged because the launcher writes direct physical bank
values before invoking shim operations.

## File Dialog / OS Service App Plan

The first modal UI service should probably be a shared file open/save service.

Reasons:

- many apps duplicate 2-5KB of infrequently used file UI/action code;
- file name, drive, file type, filters, overwrite confirmation, and DOS status
  handling are easy to represent as request/result records;
- it validates modal service invocation with high practical value.

Initial scope:

- file save service with caller-provided REU payload;
- suggested filename;
- drive and type fields;
- simple filter/type support;
- result includes final filename, drive, status, bytes written, and DOS status.

First screen contract:

- service draws its own UI;
- caller redraws after return;
- no hidden screen preservation until later.

Later scope:

- open/load service;
- service-allocated result buffers;
- REL-specific dialogs;
- overwrite policy options;
- path/drive picker reuse;
- optional OS screen/color save and restore.

## Baseline Measurement Plan

Before implementation, capture a full memory and size baseline for every app and
for the special overlay/micromodule systems. This baseline is mandatory.

Record:

- PRG file size;
- linker map runtime end;
- CODE, RODATA, DATA, BSS segment sizes;
- BSS start/end;
- raw headroom to `$C5FF`;
- aligned writable slack after BSS;
- any app-specific heap/headroom interpretation;
- ReadyShell resident heap;
- ReadyShell overlay sizes and overlay slack;
- ReadyBASIC resident size;
- ReadyBASIC BASIC workspace/free-memory facts;
- ReadyBASIC command micromodule/submodule seed and runtime usage;
- file dialog/simplefiles/simplecells special linker reserve behavior;
- shim byte size and fixed address layout;
- `$C600-$C9FF` resident usage.

Suggested tooling and artifacts:

- `python3 verify.py`;
- `python3 build_support/verify_memory_map.py`;
- `python3 build_support/verify_readyos_shim.py`;
- `make readybasic-memory-report`;
- `python3 build_support/readybasic_memory_report.py` if direct invocation is
  useful;
- `python3 build_support/readyshell_overlay_report.py`;
- `python3 build_support/file_dialog_memory_report.py` where applicable;
- generated app `.map` files from a normal full ReadyOS build;
- generated PRGs in `bin/`;
- relevant generated reports under `docs/`.

Create a baseline report file before code changes, for example:

```text
docs/reports/readyos_reu_refactor_baseline_before.md
```

The baseline should include a table for every app and separate sections for
ReadyShell, ReadyBASIC, shim, and resident metadata.

## After-Change Comparison Plan

After each phase, regenerate the same measurements and compare against the
baseline.

The comparison must flag:

- any app runtime end moving closer to `$C5FF`;
- any BSS growth;
- any CODE/RODATA/DATA growth;
- any reduced aligned writable slack;
- any ReadyShell resident heap reduction;
- any ReadyShell overlay slack reduction;
- any ReadyBASIC workspace reduction;
- any ReadyBASIC micromodule/submodule growth;
- any unexpected shim byte layout change;
- any `$C600-$C9FF` contract drift;
- any new app overlap with `$C600-$C7FF`, `$C800-$C9FF`, I/O, or ROM regions.

Acceptance rule:

- no app may lose materially significant headroom without an explicit note and
  approval;
- no app may cross existing verifier fail thresholds;
- shim size and address layout must remain fixed;
- ReadyBASIC and ReadyShell special headroom must remain within documented
  guardrails;
- any intentional tradeoff must be captured in the comparison report.

Create comparison reports such as:

```text
docs/reports/readyos_reu_refactor_phase_01_compare.md
docs/reports/readyos_reu_refactor_phase_02_compare.md
```

## Code Placement And Size Budgets

The most likely failure mode is not REU capacity; it is C64 resident code and
BSS growth. Treat the refactor as a code-placement problem first.

Rules:

- normal apps should not link the full bank `0` manager;
- launcher, boot/cartridge code, reuviewer, and host/test tools may contain
  richer management code;
- app-facing APIs must be tiny wrappers or fixed structs;
- no app should gain new BSS for global REU registry state;
- no generic parser/interpreter should be added to normal app code;
- no service invocation code should be linked into apps until that feature is
  explicitly promoted;
- ReadyShell and ReadyBASIC size changes require separate review even if global
  app thresholds pass.

Initial size budgets:

- normal app CODE/RODATA growth from shared helpers: target `0` bytes, hard
  review above `128` bytes per app;
- normal app BSS growth: target `0` bytes, hard review above `16` bytes per app;
- launcher growth: allowed only with measured headroom and map comparison;
- reuviewer growth: acceptable within app headroom, because it is a diagnostic
  app;
- ReadyShell resident heap loss: hard review for any loss above `64` bytes;
- ReadyShell overlay slack loss: hard review for any overlay losing more than
  `64` bytes, and automatic stop if a tight overlay falls below its current
  safety margin;
- ReadyBASIC BASIC workspace or micromodule/submodule loss: hard review for any
  measurable regression.

These numbers are deliberately conservative. They can be loosened only after the
baseline report shows actual margins and the change is clearly worth the cost.

## Implementation Phases

### Phase 0: Audit And Baseline

Goals:

- build the current full system;
- capture all memory, size, BSS, heap, overlay, micromodule, and shim facts;
- document stale fixed-bank wording;
- identify every fixed REU bank assumption.

Tasks:

- run normal build and verification;
- run memory/report tooling;
- produce the before-baseline report;
- `rg` for fixed bank constants and direct `$40-$48` assumptions;
- `rg` for `$C600`, `$C700`, `$C800`, `$C9FF`, shim bitmap, and bank skip use;
- audit ReadyBASIC assembler constants;
- audit ReadyShell overlay fetch code;
- audit launcher app bank parsing and preload behavior;
- audit reuviewer bank type display assumptions.

Exit criteria:

- baseline report exists;
- fixed-bank assumption list exists;
- no implementation changes have started.

### Phase 1: Define Bank 0 Schema Without Behavior Change

Goals:

- create minimal schema headers/docs for logical bank `0`;
- keep existing fixed bank behavior;
- keep helpers out of normal apps initially;
- prove zero runtime behavior change.

Tasks:

- define control bank header;
- define compact bank ownership/mirror record;
- define compact fixed-resource record for current fixed subsystem banks;
- reserve, but do not implement, future app/resource/invocation regions;
- add constants in C form first;
- add assembler constants only for fields assembler actually reads;
- add documentation for schema versioning and compatibility.

Exit criteria:

- schema is documented;
- no shim growth;
- no behavior change;
- verification still passes.

### Phase 2: Mirror Existing Layout Into Bank 0

Goals:

- logical bank `0` becomes a truthful mirror of current fixed layout;
- `$C600-$C7FF` remains the hot resident table/cache;
- existing launcher and shim behavior remain unchanged.

Tasks:

- initialize logical bank `0` during boot or early launcher startup;
- write ownership records for current fixed banks;
- write app records for current catalog entries;
- write resource records for ReadyShell and ReadyBASIC fixed banks;
- add helper to refresh `$C600-$C7FF` from bank `0`;
- add helper to write back changed resident metadata to bank `0`;
- make reuviewer optionally inspect bank `0` records.

Exit criteria:

- bank `0` mirror matches existing allocation table;
- old fixed behavior still works;
- ReadyOS boots normally;
- reuviewer/debug output can show ownership records.

### Phase 2.5: Resolver Indirection With Fixed Banks

Goals:

- introduce app id to physical bank resolution without changing allocation;
- prove the launcher can use a resolver while still returning the old fixed
  physical banks;
- keep shim inputs identical to the old path.

Tasks:

- assign compact app ids from the catalog;
- add a launcher-local resolver that maps app id to the current fixed physical
  snapshot bank;
- route launcher switch/preload decisions through the resolver;
- keep the fixed logical-to-physical formula as the resolver implementation;
- write resolver decisions into bank `0` audit records;
- add a comparison check that old formula and resolver output match.

Exit criteria:

- every app still lands in the same bank it used before;
- shim bytes receive the same target/current bank values as before;
- bank `0` records show the app id and resolved bank;
- no app code size changes except launcher/reuviewer/test utilities.

### Phase 3: Dynamic Snapshot Allocation With Shim Unchanged

Goals:

- app snapshot banks are allocated dynamically;
- shim still receives direct physical bank values;
- app id is separate from bank id.

Tasks:

- add allocator API returning physical bank plus ownership record;
- launcher catalog stores app id and token;
- launcher assigns snapshot bank on preload/load;
- launcher records `app_id -> snapshot bank`;
- launcher writes existing shim target/current bank fields before shim calls;
- current shim bitmap becomes compatibility/hot cache only;
- support load-all-to-REU through the same allocator path;
- support on-demand app loading through the same path.

Exit criteria:

- app switching works with dynamically assigned snapshot banks;
- old fixed slot assumption is no longer required for normal app launch;
- shim size/layout unchanged;
- before/after app headroom comparison is acceptable.

Do not start Phase 3 until Phase 2.5 has passed on disk and EasyFlash paths.
Dynamic allocation should be introduced behind the resolver by changing the
resolver backend, not by changing shim semantics or app-facing switch APIs.

### Phase 4: Catalog Capacity Expansion

Goals:

- lift app catalog capacity toward `64`;
- preserve UI usability and hotkeys;
- avoid making shim aware of the larger catalog.

Tasks:

- update catalog parser limits;
- update launcher menu/page handling;
- update hotkey binding to point to app id;
- update verification expectations;
- update reuviewer app ownership display;
- keep preload policy independent of catalog count.

Exit criteria:

- more than current app count can be represented;
- target capacity `64` is supported in metadata;
- runtime only allocates banks for loaded/preloaded apps;
- shim remains unchanged.

### Phase 5: Clipboard Dynamic Ownership

Goals:

- prove subsystem dynamic allocation with a lower-risk component.

Tasks:

- move clipboard payload bank tracking to ownership/resource records;
- store clipboard root descriptor in bank `0` or resident cache;
- implement cleanup/free by owner;
- update clipboard manager and related library calls;
- update reuviewer display.

Exit criteria:

- clipboard works across app switches;
- clipboard banks are unloadable/freeable by owner;
- memory comparison remains acceptable.

### Phase 6: Manifest Resource Loading

Goals:

- allow apps to declare compact generated dependency/resource records;
- use common resource allocation for disk, cartridge, load-all, and on-demand
  paths;
- generalize the existing cartridge ReadyShell overlay preload behavior.

Tasks:

- extend host-side config/build generation for per-app dependencies;
- define resource source descriptors;
- update build tooling to generate manifest payloads;
- update cartridge preload tables to register resources into bank `0`;
- update launcher load-all and on-demand paths to use resource descriptors;
- prove ReadyShell overlay dependencies and ReadyBASIC module dependencies are
  represented in the generated records before changing their bank consumption;
- add verifier checks for manifest/resource consistency.

Exit criteria:

- at least one app can declare a resource without hard-coded bank placement;
- cartridge and disk paths populate equivalent dependency/registry records;
- ReadyShell's existing cartridge-preloaded overlays can be described by the new
  records;
- no fixed-bank behavior regresses.

### Phase 7: Shared File Service

Goals:

- future-proof and eventually implement the first modal UI service using REU
  request/result passing;
- reduce future per-app duplicated file dialog code;
- keep this phase out of the required first milestone unless a later planning
  pass explicitly promotes it.

Tasks:

- define file save request/result schema;
- build service invocation dispatcher in launcher/ReadyOS manager code, not shim;
- implement file save service app;
- caller writes payload to REU and request block;
- service writes result block;
- caller redraws after return;
- add one pilot caller app.

Exit criteria:

- pilot app can save through service;
- cancel/error/success paths return structured results;
- caller redraw behavior is correct;
- service-owned temporary banks are freed.

### Phase 8: Headless Invocation

Goals:

- future-proof and eventually implement invisible service/app invocation;
- keep this phase out of the required first milestone unless a later planning
  pass explicitly promotes it.

Tasks:

- define headless capability flags;
- define headless entry convention;
- add request/result handling;
- add caller suspend/restore flow;
- require headless apps to avoid screen/keyboard unless declared otherwise;
- implement one small headless pilot service.

Exit criteria:

- caller app invokes headless service and resumes invisibly;
- result is available in REU;
- screen is not disturbed;
- failure status returns cleanly.

### Phase 9: ReadyShell Dynamic Resources

Goals:

- move ReadyShell overlay/cache/debug/scratch ownership from fixed constants to
  registry/config values.

Tasks:

- register existing fixed ReadyShell banks as resources;
- add ReadyShell runtime config block;
- resolve overlay locations from bank `0`;
- migrate overlay fetch paths;
- migrate scratch/debug/value arena paths;
- update host-side ReadyShell REU tests.

Exit criteria:

- ReadyShell works with dynamically assigned resource banks;
- overlay slack remains acceptable;
- resident heap remains acceptable;
- host and VICE tests pass.

### Phase 10: ReadyBASIC Dynamic Resources

Goals:

- move ReadyBASIC core/code banks toward dynamic assignment after lower-risk
  systems are stable.

Tasks:

- register existing `$44/$45` as ReadyBASIC resources;
- add config block for resolved core/code bank values;
- migrate assembler one path at a time;
- keep micromodule/submodule ABI stable;
- update sync docs after each proven shift;
- rerun ReadyBASIC command, program, lifecycle, module, and visual probes.

Exit criteria:

- ReadyBASIC works with resolved resource banks;
- micromodule docs match code;
- BASIC workspace/free memory remains acceptable;
- command module/submodule headroom remains acceptable.

### Phase 11: Unload And Eviction

Goals:

- use ownership records to free all banks belonging to an app/service/subsystem.

Tasks:

- implement unload by owner;
- implement service-temp cleanup;
- optionally implement resource-only unload;
- add dirty/pinned/evictable policy;
- update launcher UI if needed;
- update reuviewer to show reclaimable groups.

Exit criteria:

- unloading an app frees snapshot, overlays, modules, and app-owned banks;
- pinned system resources are not freed;
- service temp resources are reliably cleaned after return/error.

## Verification Matrix

Minimum verification after each major phase:

- normal full build;
- `python3 verify.py`;
- `python3 build_support/verify_memory_map.py`;
- `python3 build_support/verify_readyos_shim.py`;
- normal ReadyOS boot through `run.sh`;
- launcher load/switch/return flow;
- load-all-to-REU flow where applicable;
- EasyFlash/cartridge preload flow when touched;
- reuviewer inspection of ownership and fixed/cache state;
- ReadyShell host REU tests when ReadyShell code or resource records change;
- ReadyBASIC static/plugin/lifecycle/module tests when ReadyBASIC constants or
  config change.

Special ReadyBASIC verification should include the existing probe scripts and
make targets documented in the ReadyBASIC files, including lifecycle and module
overlay probes.

### Required Build And Test Commands

The baseline and every major phase comparison should record the exact command
set used. Use tiers so development remains practical while release checkpoints
stay strict.

Tier 1, required for small implementation steps:

```text
make verify
python3 build_support/verify_readyos_shim.py
python3 build_support/verify_memory_map.py
```

Tier 2, required for any phase that changes REU allocation, preload,
suspend/resume, launcher switch behavior, or bank ownership:

```text
make verify
make easyflash-verify
make readyshell-host-tests
make readybasic-plugin-static-check
make readybasic-memory-report
```

Tier 3, required for milestone completion and before considering the refactor
stable:

```text
make fullcheck
make release-all
make audit-release-assets
make easyflash-verify
make easyflash-smoke
make easyflash-preload-verify
make easyflash-probe-verify
make xefprobe-standalone-verify
make readybasic-vice-suites
```

Use `make fullcheck` where a clean rebuild plus normal verification is desired
outside the full Tier 3 matrix.

Also run the profile build diversity path:

```text
bash ./run.sh --build-all
```

For launch/smoke diversity, use normal ReadyOS boots, not single-app launches:

```text
bash ./run.sh
bash ./run.sh --profile precog-d81
bash ./run.sh --profile precog-dual-d64
bash ./run.sh --profile precog-solo-d64-a
bash ./run.sh --profile precog-solo-d64-b
bash ./run.sh --profile precog-solo-d64-c
bash ./run.sh --profile precog-solo-d64-d
bash ./run.sh --profile precog-solo-d64-e
bash ./run.sh --vice-fast
```

The exact profile list should be generated from:

```text
bash ./run.sh --list-profiles
python3 build_support/readyos_profiles.py list-ids
```

The cartridge path is mandatory for this refactor because EasyFlash preload is
one of the paths that must populate the same future bank `0` registry as disk
and launcher-driven preload.

### VICE Runtime Diversity

VICE coverage should include at least:

- default dual-D71 profile through normal `run.sh`;
- D81 profile;
- dual-D64 profile;
- all solo-D64 profiles, especially ReadyShell-focused and planning subsets;
- normal drive behavior;
- `--vice-fast` drive-trap/warp behavior;
- load-all-to-REU enabled and disabled profiles or overrides;
- run-first profile behavior where used;
- EasyFlash cartridge cold boot with companion `readyos_data.d64`;
- EasyFlash preload verification;
- EasyFlash probe verification;
- standalone EasyFlash probe screenshot verification.

Where feasible, capture VICE logs and monitor logs for comparison, especially
for phases that alter preload, app switch, REU allocation, or cartridge
handoff.

### Harness And App-Specific Tests

The following harnesses should be built and run when their touched areas are in
scope:

- `xrelchk` for CAL26 REL transport and REL behavior;
- `xfilechk` for file copy/rename/delete/file-dialog-adjacent storage behavior;
- `xseqchk` for SEQ persistence behavior;
- `xtextchk` for PETSCII/text edge cases;
- `test_reu.prg` or its current equivalent for low-level REU DMA sanity;
- editor/tasklist/simplefiles host smoke tests already included in
  `make verify`;
- ReadyShell host parser, VM, overlay-command, and REU heap/value tests;
- ReadyBASIC direct command, program, lifecycle, module overlay, cross-app
  resume, large-vars, rbtest1, second-entry editor, state, repeat-label, and
  full visual VICE suites.

If any of these harnesses do not currently have a single aggregate make target,
add one before starting the invasive phases. The refactor should not rely on
remembering a loose list of scripts.

### New Tests To Add For This Refactor

Add focused tests as the new architecture appears:

- bank `0` schema pack/unpack host test;
- bank `0` checksum/version/magic validation test;
- resident `$C600-$C7FF` cache import/export test;
- ownership table invariants test: no double owners, no free pinned banks, no
  dynamic allocation of reserved banks;
- app id to snapshot bank resolver test;
- dynamic snapshot allocation/free test;
- dynamic load-all-to-REU registry equivalence test;
- disk preload versus cartridge preload registry equivalence test;
- reuviewer ownership display smoke test;
- unload-by-owner test;
- clipboard dynamic allocation/free test;
- ReadyShell resource registry lookup test before removing fixed banks;
- ReadyBASIC config-block readback test before removing fixed `$44/$45`
  assumptions;
- service invocation schema host test, even before real services ship;
- modal/headless invocation VICE tests only when those future features are
  promoted from schema reservation to implementation.

### Acceptance Gates

Before merging a phase that changes REU allocation, preload, suspend/resume, or
resource ownership:

- `make verify` passes;
- `make release-all` passes;
- `make audit-release-assets` passes;
- `make easyflash-verify` passes;
- relevant VICE profile boots pass;
- relevant ReadyShell/ReadyBASIC suites pass;
- before/after memory comparison is documented;
- no unexpected shim layout or size change is present;
- no app has a materially significant headroom loss without explicit approval.

## Documentation Updates

The refactor must update docs as behavior changes.

Likely files:

- `README.md`;
- `docs/ReadyOS SHIM Architecture Report (0.2).html` or successor report;
- `docs/ReadyShellArchitecture.md`;
- `docs/readyshell_overlay_inventory.md`;
- `docs/readybasic_memory_diagrams.html` via regeneration;
- `src/apps/readybasic/READYBASIC_MICROMODULE_SYNC.md`;
- `src/apps/readybasic/READYBASIC_CURRENT_DESIGN.md`;
- `src/apps/readybasic/READYBASIC_LIFECYCLE_AND_REU_ARCHITECTURE.md`;
- `src/apps/readybasic/REadyBASICCommandModuleAndSubmodulePlan.MD`;
- any generated readme/help pages that describe REU layout.

Stale wording to remove or clarify:

- "launcher bank 0" where launcher now maps to `skip + 1`;
- fixed app slots `2-25` as the only app model;
- fixed ReadyShell banks as permanent architecture rather than initial
  allocation;
- fixed ReadyBASIC banks once config indirection exists;
- legacy clipboard bank wording.

## Main Risks

### Contract Sprawl

Many current code paths treat bank number as identity, allocation state, and
physical location. The refactor must separate these or it will become harder to
reason about than the current fixed layout.

Mitigation:

- introduce app id, resource id, owner kind, and physical bank as separate
  fields;
- keep the shim on physical banks only;
- make reuviewer display the separated concepts.

### Resident Memory Creep

Moving to dynamic registries can accidentally grow every app through shared
library additions.

Mitigation:

- keep most manager code in launcher/service code, not every app;
- expose tiny helper APIs for apps;
- measure every app before/after;
- reject broad app code-size increases unless justified.

### ReadyBASIC Assembler Coupling

ReadyBASIC duplicates REU constants and has micromodule/submodule placement
rules.

Mitigation:

- defer ReadyBASIC dynamic banks until late;
- use a runtime config block;
- migrate one path at a time;
- update micromodule sync docs immediately after each proven change.

### Shim Pressure

There will be temptation to add registry logic to the shim.

Mitigation:

- keep the shim direct-bank only;
- do app id/resource lookup in launcher/manager;
- use bank `0` plus `$C600-$C7FF` cache for richer state.

### Screen State For Modal Services

The app snapshot does not include normal screen RAM or color RAM.

Mitigation:

- first modal services require caller redraw;
- later add explicit OS screen/color save/restore as a separate capability.

## Recommended First Milestone

The first practical milestone should not attempt full dynamic everything.

Recommended milestone:

1. capture baseline reports;
2. define bank `0` schema;
3. mirror the current fixed layout into bank `0`;
4. keep all behavior fixed;
5. make reuviewer/debug tooling show the bank `0` ownership records;
6. compare memory/headroom and prove no material app impact.

Explicit non-goals for the first milestone:

- no dynamic app snapshot allocation;
- no catalog capacity increase;
- no new runtime manifest parser;
- no ReadyShell dynamic bank consumption;
- no ReadyBASIC dynamic bank consumption;
- no clipboard migration unless it is promoted as a separate follow-up;
- no unload/eviction;
- no headless invocation;
- no modal UI service app;
- no shim growth or shim semantic change.

The success condition is boring: the new bank `0` records exist, agree with the
old runtime facts, survive normal and cartridge boot flows, and cost essentially
nothing to normal apps.

This gives ReadyOS a canonical future control bank without risking launcher,
shim, ReadyShell, or ReadyBASIC behavior immediately.

## Historical Baseline Status: 2026-06-02

At baseline commit `e7b5487 Add REU control bank mirror baseline`, this branch
had implemented the conservative first milestone plus the first piece of Phase
2.5 resolver indirection. At that point it intentionally did not implement
dynamic app allocation, catalog expansion, manifest parsing, unload, headless
invocation, modal services, or dynamic ReadyShell/ReadyBASIC resource
assignment. The current milestone status at the top of this document supersedes
that baseline for launcher dynamic allocation, 64-entry catalogs, cartridge
preload tracking, and disk launcher unload.

Implemented:

- added `src/lib/reu_control_bank.h` and `src/lib/reu_control_bank.c`;
- defined logical bank `0` schema version `1` with magic `RCB0`;
- kept the shim at `512` bytes with no semantic change;
- kept `$C600-$C7FF` as fast resident truth;
- mirrored the resident `$C600` 256-byte bank-type table into logical bank `0`
  at offset `$0100`;
- wrote compact fixed-resource records at `$0200` for:
  - ReadyOS global/control bank;
  - launcher snapshot;
  - launcher overlay;
  - ReadyShell cache banks `$40`, `$41`, `$42`;
  - ReadyShell debug bank `$43`;
  - ReadyShell scratch bank `$48`;
  - ReadyBASIC core/code banks `$44`, `$45`;
- linked the control-bank writer only into launcher and reuviewer, not broad
  normal-app REU libraries;
- refreshed the bank `0` mirror from launcher after bitmap sync and app
  preload state changes;
- added a fixed-bank launcher snapshot resolver so shim-facing launcher paths
  stop directly depending on `app_banks[index]` at the final handoff point;
- added reuviewer control-bank header validation/status display;
- added `build_support/verify_reu_control_bank.py`;
- added `build_support/report_app_headroom.py`;
- captured the current app-window report at
  `agentworkijg/reu_refactor_headroom_current.json`;
- wired the new static verifier into `make verify`.

Verification passed after implementation:

- `make bin/launcher.prg bin/launcher_easyflash.prg bin/reuviewer.prg`;
- `python3 build_support/verify_reu_control_bank.py`;
- `python3 build_support/report_app_headroom.py --output agentworkijg/reu_refactor_headroom_current.json`;
- `python3 build_support/verify_memory_map.py`;
- `python3 build_support/verify_readyos_shim.py --check-easyflash-bin`;
- `make verify`;
- `make easyflash-verify`.

Observed memory-contract result:

- normal apps do not link the new control-bank writer;
- launcher and reuviewer grow because they deliberately own/debug the mirror;
- `verify_memory_map.py` still passes the app-window, `$C600-$C7FF`, shim, and
  I/O exclusion checks;
- `verify_readyos_shim.py --check-easyflash-bin` still reports a `512` byte
  shim and EasyFlash shim binary byte-identical to `readyos_shim.inc`;
- ReadyShell heap/overlay bounds still pass the existing memory-map checks.
- the current generated report shows ReadyBASIC as the tightest app-window case
  with `1031` bytes of headroom, so broad library growth remains unacceptable.

Open work for the next branch or milestone:

- capture a clean pre-change/mainline report and compare it against
  `agentworkijg/reu_refactor_headroom_current.json` before making authority or
  allocator changes;
- add a VICE probe that reads logical bank `0` and validates the `RCB0` header,
  generation, bank-type mirror, and fixed-resource records at runtime;
  an initial monitor-script attempt was deferred because monitor writes to the
  REU I/O registers did not reliably affect the live REU transfer registers,
  so the next probe should be implemented as a small C64-side test program or
  with a proven VICE I/O-address-space command sequence;
- expand launcher resolver coverage beyond final shim-facing handoff sites
  before any dynamic bank assignment is introduced;
- add generated dependency records for the existing EasyFlash ReadyShell
  preload model before changing ReadyShell itself;
- keep ReadyBASIC module/micromodule dynamic-bank work deferred until the C app
  and ReadyShell resource model has proven stable;
- design unload/eviction and app-owned resource lists only after dynamic
  allocation exists and passes disk plus EasyFlash smoke paths.
