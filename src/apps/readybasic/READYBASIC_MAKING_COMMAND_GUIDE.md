# ReadyBASIC Making Command Guide

This guide explains how to add or change descriptor-backed assembler commands
in the current ReadyBASIC module/submodule architecture. It is not the guide for
native BASIC `PROC`/`FUNC`; those are resident language features written by
users in BASIC program text.

## Current Shape

Commands are visible BASIC names such as `ZADD16(1,2)` or `SCRCAP(H%)`. Each
assembler command has:

1. A resident parser signature that validates syntax and fills the call frame at
   `$C200`.
2. A 32-byte descriptor in REU bank `$44:$1000-$1FFF`.
3. An assembler payload in REU bank `$45`.
4. A runtime target under BASIC ROM: slot 0 at `$A800`, slot 1 at `$B000`, slot
   2 at `$B800`, or a span of those slots.
5. A result frame at `$C300` that resident code commits back to BASIC.

The old `LOW` versus `HIDDEN` command distinction is obsolete. All command
payloads are under-ROM payloads selected by module id, submodule id, optional
overlay id, slot mask, REU offset, runtime destination, and entry offset.

## Naming Rules

ReadyBASIC names are stored as readable BASIC text, so the C64 tokenizer can
still see keyword substrings. Screen new names in BASIC before making them
public. `ZMODLD` is used instead of `ZMODLOAD` because `LOAD` tokenizes inside
the longer name.

Recommended prefixes:

| Prefix | Use |
| --- | --- |
| `Z*` | Demo, proof, or temporary development command. |
| `X*` | Experimental public command whose shape is not settled. |
| `U*` | Ultimate-family specific command. |
| `XU*` | Experimental Ultimate-family command. |

Avoid names longer than 16 bytes; descriptors store a fixed 16-byte uppercase
name field.

## Descriptor ABI

Each command descriptor is exactly 32 bytes:

| Byte(s) | Field | Authoring note |
| ---: | --- | --- |
| `0` | Command id | Stable internal id. |
| `1` | Module id | Built-in module 1 is system/default; built-in module 2 is proof/loader. |
| `2-3` | Payload REU offset | Offset in bank `$45`, little endian. |
| `4-5` | Payload size | Number of bytes to fetch when not resident. |
| `6` | Submodule id | Stable within the module. |
| `7` | Overlay id | `0` for a normal submodule, nonzero for overlays. |
| `8` | Slot mask | Bit 0 = `$A800`, bit 1 = `$B000`, bit 2 = `$B800`. |
| `9` | Generation/check byte | Used by residency checks. |
| `10-11` | Runtime destination offset | Destination offset from `$A000`. |
| `12-13` | Entry offset | Entry offset after payload copy. |
| `14` | Signature id | Selects resident parser behavior. |
| `15` | Name length | Uppercase command text length. |
| `16-31` | Name bytes | Uppercase, zero padded. |

Source macro names remain historical conveniences. They all emit the descriptor
shape above:

```asm
CMD_LOW      ; module 1, slot 0, copy a bracketed slice
CMD_LOW_ALL  ; module 1, slot 0, copy the whole slot-0 payload
CMD_HIDDEN   ; module 1/common-compatible payload, generic descriptor path
CMD_SLOT1    ; module 2, slot 1
CMD_SLOT2    ; module 2, slot 2
CMD_SPAN     ; module 2, slots 1+2
CMD_OVL1     ; module 2 overlay proof in slot 2
CMD_OVL2     ; module 2 overlay proof in slot 2
```

Do not add a new dispatch category for a command unless the descriptor cannot
model it. Prefer another macro over another resident path.

## Choosing A Slot Layout

| Need | Recommended layout |
| --- | --- |
| Small command that uses common system helpers often | Module 1 / slot 0. |
| Independent command family | A module submodule in slot 1 or slot 2. |
| Stable logic plus many alternatives | Stable manager in slot 1, overlays rotating through slot 2. |
| Larger operation needing 4KB | One submodule spanning slots 1+2. |
| Operation needing the whole 6KB | One submodule spanning slots 0+1+2, but do not assume slot-0 helpers remain callable. |

Remember that payload code is fixed-address assembler. It is linked for the
runtime slot address; it is not relocated when copied.

## Adding A Built-In Command

1. Pick or add a command id near the existing `CMD_*` constants.
2. Reuse an existing signature if possible. Add a new `SIG_*` only when the
   parameter/result shape is genuinely new.
3. Add or reuse a resident `parse_sig_*` routine. It should validate syntax,
   evaluate BASIC expressions through ROM helpers, clear output variables when
   needed, and fill only documented `CF_*` fields.
4. Place worker code in the appropriate segment:
   - slot 0: current `LOWPACK` region at `$A800`;
   - slot 1: `SLOTPACK1` at `$B000`;
   - slot 2: `SLOTPACK2` or overlay payload at `$B800`;
   - span: a segment linked for the full target span.
5. Emit one descriptor with the right module id, submodule id, overlay id, slot
   mask, REU offset, size, runtime destination, entry offset, signature id, and
   name.
6. Add VICE-suite coverage for statement form, expression form if supported,
   error paths, warm resume if stateful, and no-recopy behavior if residency is
   relevant.
7. Run `make readybasic-plugin-static-check` and the full ReadyBASIC VICE visual
   suite through the normal ReadyOS boot path.

## Parser Signature Guidance

Keep parser signatures resident only when they need BASIC ROM services or
interpreter state. Avoid growing resident code for command-private policy.

Good signature work:

- Evaluate integer or float expressions through BASIC ROM.
- Capture output variables and clear them before command execution.
- Stage short string inputs into the call frame.
- Validate comma and parenthesis syntax.
- Report consistent ReadyBASIC errors.

Poor signature work:

- Large command-specific lookup tables.
- Disk module policy that can live inside `ZMODLD`.
- Long-lived command state that can be a REU handle.
- Graphics/audio/file code that belongs in a module submodule.

## Worker Guidance

Workers run with RAM under BASIC ROM mapped in, so be careful about assumptions:

- Read input from `$C200` and write output to `$C300`.
- Return status through the result frame, not by mutating BASIC variables
  directly.
- Keep zero-page use conservative; cc65 and BASIC/KERNAL expect their runtime
  zero-page locations to survive.
- Do not use `$C600-$C9FF`.
- Do not call BASIC ROM helpers while BASIC ROM is banked out. Return to
  resident code for ROM work.
- If a worker calls helper code in another slot, make sure its descriptor and
  slot mask guarantee that helper is resident, or use resident ABI services.

## Example: Small Slot-0 Command

Slot-0 commands use module 1 and live in the default/system payload. A small
command can copy only its slice:

```asm
CMD_LOW CMD_ZADD16, SIG_ZADD16, cmd_zadd16_low, cmd_zadd16_low_end, "ZADD16"

cmd_zadd16_low:
        ; read CF_* integer inputs, write RF_* integer result
        rts
cmd_zadd16_low_end:
```

Commands that call shared slot-0 helpers use `CMD_LOW_ALL` so the whole
slot-0 payload is resident:

```asm
CMD_LOW_ALL CMD_BUFNEW, SIG_BUFNEW, cmd_bufnew_low, "BUFNEW"
```

## Example: Slot, Span, And Overlay Proofs

The current proof commands demonstrate the shapes new modules can use:

| Macro | Command | Shape |
| --- | --- | --- |
| `CMD_SLOT1` | `ZSLOT1` | Single submodule in `$B000-$B7FF`. |
| `CMD_SLOT2` | `ZSLOT2` | Single submodule in `$B800-$BFFF`. |
| `CMD_SPAN` | `ZSPAN` | One payload spanning slots 1+2. |
| `CMD_OVL1` | `ZOVL1` | Overlay payload through slot 2. |
| `CMD_OVL2` | `ZOVL2` | Another overlay payload through the same target. |

`ZCPYRST` and `ZCOPY` let tests prove that repeated calls to an already
resident command do not trigger another REU copy.

## Adding A Disk Module

Disk modules are generated today by
`build_support/build_readybasic_disk_modules.py`. The sample loader command
`ZMODLD(name$)` lives in the second included module, not in resident core.

For a new sample module:

1. Add payload bytes linked for the desired slot address.
2. Add a descriptor with a unique command id/name, module id, submodule id,
   overlay id, slot mask, payload offset, runtime destination, and signature id.
3. Assign an offset in REU bank `$45`. Current samples use `$3000`, `$3200`,
   `$3300`, and `$3400`.
4. Generate a PRG with load address `$C500`, magic `RBM!`, a small header,
   descriptors, payload directory, and payload bytes.
5. Add the generated PRG to ReadyBASIC-capable disk profiles.
6. Extend the VICE suite to call `ZMODLD("NAME")` and then the new commands.

The loaded PRG at `$C500` is temporary. Once `ZMODLD` has copied descriptors to
REU `$44` and payloads to REU `$45`, command execution must not depend on the
file buffer.

## When To Use Native `PROC` / `FUNC`

Use `PROC` or `FUNC` when the reusable logic should be ordinary user BASIC:

```basic
1000 PROC DRAW(P%,N$)
1010 PRINT P%;N$
1020 ENDP

1100 FUNC ADDI(X%,Y%)
1110 R%=X%+Y%
1120 RET R%
1130 ENDP
```

Use a descriptor-backed command when the feature needs machine-code speed,
hidden RAM, REU handles, direct screen/color memory, disk module loading,
graphics modes, or shared non-BASIC behavior.

## Memory Checklist

Before committing a command change:

- `RESIDENT` still ends below `BASIC_START`.
- `BRIDGE` still ends below `$C200`.
- Frame/buffer use stays inside `$C200-$C5FF`.
- `$C600-$C7FF` and `$C800-$C9FF` are untouched except for intentional REU bank
  ownership marks at `$C600+$44/$45`.
- Under-ROM payloads fit their claimed slot masks.
- Built-in payload offsets in bank `$45` match descriptor offsets.
- Disk module descriptors do not collide with built-in descriptors.
- Command names are safe from BASIC tokenizer collisions.
- VICE coverage proves the new path through the normal ReadyOS boot flow.
