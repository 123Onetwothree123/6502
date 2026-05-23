# ReadyBASIC Making Command Guide

This guide explains how current ReadyBASIC commands are made in
`src/apps/readybasic/readybasic.s`. It uses the current names and layout:
128 descriptor slots in REU bank `$44`, packed command code in bank `$45`,
`SCRCAP` in slot 14, `SCRPUT` in slot 128, and zero-filled filler slots 15-127.

Native `PROC`/`FUNC` routines are intentionally not plugin commands. They are
ordinary BASIC program text called with bare `EXEC`, and they do not need
descriptors, command ids, signature ids, `LOWPACK`, `HIDDENPACK`, or bank `$45`
code bytes. Use this command guide only when adding new `!COMMAND` overlays.

## Naming Rules

ReadyBASIC command names are visible BASIC text after `!`; they are not private
tokens. Avoid substrings that C64 BASIC can tokenize inside the command name.
That is why the demo/proof commands use the `Z...` namespace and why the array
examples use `NUM` instead of `INT`.

Historical names such as `PING`, `ADD16`, `STRUP`, `HCRC`, `SUMAI`,
`RANGEAI`, `TEMPSCRATCH`, and `FAIL` are not aliases. The current public names
are `ZECHO1`, `ZADD16`, `UPPER`, `LOWER`, `ZHIDDENRAM`, `ZSUMNUMARRAY`,
`ZRANGENUMARRAY`, `ZTEMPSCRATCH`, and `ZFAIL`.

## How To Read The Examples

Each command has three cooperating pieces:

1. A parser signature such as `parse_sig_zadd16`. This runs in resident
   ReadyBASIC code while BASIC ROM services are visible. It validates syntax,
   evaluates BASIC expressions, clears output variables, and fills the call
   frame (`CF_*` fields).
2. A worker label such as `cmd_zadd16_low`. This is the overlay entry point
   copied from REU into C64 RAM. It reads `CF_*` fields and writes the result
   frame (`RF_*` fields).
3. A descriptor macro such as `CMD_LOW ... "ZADD16"`. This emits the 32-byte
   registry record that tells ReadyBASIC the public command name, parser
   signature id, packed-code offset, copy size, and runtime entry address.

The labels are not magic incantations: they are addresses used by the assembler
to fill descriptor fields, and they become the runtime handoff points between
resident lookup, REU-backed packed code, and command execution.

## When To Use PROC/FUNC Instead

Use a native routine when the reusable logic is naturally BASIC code and should
ship with, or be typed into, the user's BASIC program:

```basic
1000 PROC DRAW P%,N$
1010 PRINT P%;N$
1020 ENDP

1100 FUNC ADDI X%,Y%,R%
1110 R%=X%+Y%
1120 ENDP

10 EXEC DRAW,3,"PLAYER"
20 EXEC ADDI,4,5,A%
```

`PROC` has input formals only. `FUNC` uses its final formal as the one output
formal. Version 1 supports only `%` integer and `$` string formals, no arrays,
locals, plain floating variables, or multiple outputs. Definitions should live
after `END`; fall-through into a definition is invalid. Because formals are just
ordinary C64 BASIC globals, choose formal names that will not collide with caller
variables you care about.

Use a `!COMMAND` overlay instead when the routine needs hidden RAM, REU handles,
fast machine-code loops, direct screen/color memory, or shared command behavior.

## Descriptor Shape

Each command has a 32-byte descriptor in the cold `REGSEED` image. On cold boot,
ReadyBASIC copies those descriptors to REU bank `$44:$1000-$1FFF`. At runtime
lookup fetches one 256-byte descriptor page into `RB_PAGEBUF`, scans eight
descriptors locally, and copies the match into `RB_DESC_BUF`.

```asm
.macro CMD_LOW id, sig, label, endlabel, name
        .byte id, RB_CMD_F_LOW       ; public id and low-overlay flag
        .word label - __LOWPACK_RUN__ ; packed-code offset in REU bank $45
        .word endlabel - label        ; copy length for this command
        .word 0, 0                    ; no hidden overlay slice
        .word label - RB_LOW_BASE     ; runtime entry offset from $A900
        .word 0                       ; no hidden runtime entry
        .byte sig, .strlen(name)      ; parser signature and name length
        .byte name
        .res 16 - .strlen(name), 0
.endmacro
```

Descriptor commentary:

| Line or field | Meaning |
| --- | --- |
| `.macro CMD_LOW id, sig, label, endlabel, name` | Defines a descriptor template for a command whose worker lives in the low overlay at `$A900`. |
| `id` | The stable internal command id. Runtime behavior should not rely on the command's slot number. |
| `sig` | The parser signature id. Resident dispatch uses it to select the `parse_sig_*` routine before the overlay runs. |
| `label` / `endlabel` | Assembler labels bracketing the worker code. Their difference is the exact copy size. |
| `name` | The visible text after `!`, padded to the descriptor's 16-byte name field. |
| `RB_CMD_F_LOW` | Descriptor flag telling lookup to copy low overlay code and call the `$A900` entry. |
| `label - __LOWPACK_RUN__` | Offset of this worker inside the packed LOWPACK image stored in REU bank `$45`. |
| `endlabel - label` | Number of bytes to copy for this command. Small wrappers copy only themselves. |
| `label - RB_LOW_BASE` | Runtime entry offset after the worker has been copied into the low overlay window. |

`CMD_LOW_ALL` is used for commands whose tiny wrapper calls shared allocator or
screen helpers elsewhere in `LOWPACK`. Those commands copy the full current
`$061A` low pack to keep resident RAM small.

```asm
.macro CMD_LOW_ALL id, sig, label, name
        .byte id, RB_CMD_F_LOW
        .word 0                    ; packed-code offset is whole LOWPACK
        .word __LOWPACK_SIZE__      ; copy the whole shared low pack
        .word 0, 0
        .word label - RB_LOW_BASE   ; runtime entry offset from $A900
        .word 0
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro
```

`CMD_LOW_ALL` keeps the descriptor format the same but deliberately copies the
whole low pack. That is appropriate when the command entry is tiny but calls
other low-overlay helpers, such as handle allocation or screen-copy routines.

Hidden commands use the same descriptor shape, but point at a hidden packed
slice and a hidden runtime entry under BASIC ROM RAM:

```asm
.macro CMD_HIDDEN id, sig, label, endlabel, name
        .byte id, RB_CMD_F_HIDDEN
        .word 0, 0
        .word label - __HIDDENPACK_RUN__ ; hidden packed-code offset
        .word endlabel - label           ; hidden copy length
        .word 0
        .word label - RB_HIDDEN_BASE     ; runtime entry offset from $A800
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro
```

`CMD_HIDDEN` uses the hidden fields in the descriptor instead of the low fields.
ReadyBASIC copies that slice to `$A800`, maps RAM under BASIC ROM, calls the
entry, then restores normal banking.

## ZECHO1: Smallest Output Command

`ZECHO1` proves the simplest path: parse one output integer variable, run a tiny
low overlay, and commit an integer result.

```asm
parse_sig_zecho1:
        jsr rb_parse_out_int       ; capture OUT% pointer and clear it first
        rts

cmd_zecho1_low:
        lda #0
        sta RF_STATUS              ; status 0 means commit result
        lda #RB_VAL_INT
        sta RF_TAG                 ; result frame contains an integer
        lda #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI              ; return 1 as little-endian value
        rts
cmd_zecho1_low_end:
```

Descriptor:

```asm
CMD_LOW CMD_ZECHO1, SIG_ZECHO1, cmd_zecho1_low, cmd_zecho1_low_end, "ZECHO1"
```

Line-by-line commentary:

| Line or group | What it does |
| --- | --- |
| `parse_sig_zecho1:` | Resident parser entry selected by `SIG_ZECHO1`. |
| `jsr rb_parse_out_int` | Reads the output integer variable, records its address, and clears it before command execution. |
| `rts` after the parser | Returns to resident dispatch. If parsing failed, the helper has already set the error path. |
| `cmd_zecho1_low:` | Low-overlay worker entry used by the descriptor's runtime offset. |
| `lda #0` / `sta RF_STATUS` | Marks the command as successful. Nonzero status prevents result commit. |
| `lda #RB_VAL_INT` / `sta RF_TAG` | Says the result frame contains a 16-bit BASIC integer. |
| `lda #1` / `sta RF_VAL_LO` and `lda #0` / `sta RF_VAL_HI` | Stages integer value `1` in little-endian order. |
| `cmd_zecho1_low_end:` | End marker used only by the assembler to compute copy length. It is not called. |
| `CMD_LOW ... "ZECHO1"` | Publishes the public command name and connects `SIG_ZECHO1` to the worker slice. |

Why it matters: this is the minimum useful skeleton for an output command.
Everything else adds more parsing, different result tags, or REU/hidden-memory
work.

## ZADD16: Numeric Inputs Plus Output

`ZADD16` proves two numeric expressions followed by an integer output variable.
Resident parser code evaluates the inputs through BASIC ROM and places them in
the call frame.

```asm
parse_sig_zadd16:
        jsr rb_parse_num0          ; first numeric expression -> CF_NUM0
        jsr rb_parse_num1          ; second numeric expression -> CF_NUM1
        jsr rb_parse_out_int       ; OUT%, cleared before execution
        rts

cmd_zadd16_low:
        clc
        lda CF_NUM0_LO
        adc CF_NUM1_LO
        sta RF_VAL_LO
        lda CF_NUM0_HI
        adc CF_NUM1_HI
        sta RF_VAL_HI
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        rts
cmd_zadd16_low_end:
```

Descriptor:

```asm
CMD_LOW CMD_ZADD16, SIG_ZADD16, cmd_zadd16_low, cmd_zadd16_low_end, "ZADD16"
```

Line-by-line commentary:

| Line or group | What it does |
| --- | --- |
| `jsr rb_parse_num0` | Evaluates the first BASIC numeric expression and stores its integer form in `CF_NUM0_LO/HI`. |
| `jsr rb_parse_num1` | Evaluates the second numeric expression into `CF_NUM1_LO/HI`. |
| `jsr rb_parse_out_int` | Captures and clears the output integer variable. |
| `clc` before `adc` | Clears carry so the two-byte addition starts cleanly. |
| `lda CF_NUM0_LO` / `adc CF_NUM1_LO` / `sta RF_VAL_LO` | Adds the low bytes and stages the low result byte. |
| `lda CF_NUM0_HI` / `adc CF_NUM1_HI` / `sta RF_VAL_HI` | Adds the high bytes plus carry from the low-byte addition. |
| `RF_STATUS = 0`, `RF_TAG = RB_VAL_INT` | Marks success and says resident commit should write a 16-bit integer. |
| `CMD_LOW ... "ZADD16"` | Tells the registry this command uses the scalar-add parser and this exact worker slice. |

Why it matters: this is the scalar arithmetic pattern. A command can trust the
call frame after its parser signature has run; the overlay does not need to call
BASIC expression parsers itself.

## UPPER And LOWER: String Input, String Output

`UPPER` and `LOWER` share the same signature: one string value, one output
string variable. The overlay stages the transformed bytes into `RF_STR_BUF`.
Resident visible code later allocates BASIC string heap space and writes the
string descriptor, because string heap mutation belongs on the visible side of
the contract.

```asm
parse_sig_string_out:
        jsr rb_parse_string_value  ; variable or quoted literal -> CF_STR_BUF
        jsr rb_parse_out_string    ; OUT$, cleared before execution
        rts
```

The current `LOWER` worker:

```asm
cmd_lower_low:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_STRING
        sta RF_TAG
        lda CF_STR_LEN
        sta RF_STR_LEN
        ldy #0
@loop:
        cpy CF_STR_LEN
        beq @done
        lda CF_STR_BUF,y
        cmp #$C1
        bcc @ascii_case
        cmp #$DB
        bcs @ascii_case
        sec
        sbc #$60                 ; shifted C64 letters -> lowercase byte range
        jmp @store
@ascii_case:
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        clc
        adc #$20                 ; ASCII A-Z -> a-z
@store:
:       sta RF_STR_BUF,y
        iny
        jmp @loop
@done:
        rts
cmd_lower_low_end:
```

Descriptors:

```asm
CMD_LOW CMD_UPPER, SIG_UPPER, cmd_upper_low, cmd_upper_low_end, "UPPER"
CMD_LOW CMD_LOWER, SIG_LOWER, cmd_lower_low, cmd_lower_low_end, "LOWER"
```

Line-by-line commentary:

| Line or group | What it does |
| --- | --- |
| `parse_sig_string_out:` | Shared parser signature used by both `UPPER` and `LOWER`. |
| `jsr rb_parse_string_value` | Accepts either a string variable/expression or a quoted literal and stages bytes in `CF_STR_BUF`. |
| `jsr rb_parse_out_string` | Captures the output string variable descriptor and clears it before execution. |
| `RF_STATUS = 0`, `RF_TAG = RB_VAL_STRING` | Prepares a successful string result. |
| `lda CF_STR_LEN` / `sta RF_STR_LEN` | Copies the input length to the result length. |
| `ldy #0` and `@loop` | Uses Y as the byte index through the staged string. |
| `cpy CF_STR_LEN` / `beq @done` | Stops when all staged bytes have been processed. |
| `cmp #$C1` ... `sbc #$60` | Handles shifted C64 letter bytes, where visual case depends on charset mode. |
| `cmp #'A'` ... `adc #$20` | Handles ordinary ASCII uppercase bytes. |
| `sta RF_STR_BUF,y` | Writes the transformed byte into the result buffer, not directly into BASIC string memory. |
| `CMD_LOW ... "UPPER"` and `CMD_LOW ... "LOWER"` | Publish two commands with the same parser shape but different byte-transform workers. |

Why it matters: string commands separate byte transformation from BASIC heap
ownership. Visual lowercase on a C64 depends on charset/display mode, so tests
assert `ASC()` byte values for `LOWER`.

## ZHIDDENRAM: Hidden Worker Command

`ZHIDDENRAM` proves that a command can run under BASIC ROM RAM in the hidden
overlay slot at `$A800`. Its descriptor uses `CMD_HIDDEN`, so ReadyBASIC fetches
the hidden slice into `$A800`, maps RAM under BASIC ROM, calls it, and restores
banking immediately afterward.

```asm
CMD_HIDDEN CMD_ZHIDDENRAM, SIG_ZHIDDENRAM,
           cmd_zhiddenram_hidden, cmd_zhiddenram_hidden_end, "ZHIDDENRAM"
```

Descriptor commentary:

| Field | Meaning |
| --- | --- |
| `CMD_ZHIDDENRAM` | Internal command id for the hidden-memory proof command. |
| `SIG_ZHIDDENRAM` | Parser signature that stages a string input and integer output. |
| `cmd_zhiddenram_hidden` | Hidden overlay entry copied to `$A800`. |
| `cmd_zhiddenram_hidden_end` | End label used to compute the hidden copy size. |
| `"ZHIDDENRAM"` | Public command text; this is a proof/demo command under the `Z...` namespace. |

The worker itself reads `CF_STR_BUF`, sums staged bytes, and returns an integer
result frame. This is intentionally a proof command, not a final checksum API.

## ZSUMNUMARRAY And ZRANGENUMARRAY: Array References

ReadyBASIC array parameters are explicit: pass the base element and a count.
For example:

```basic
DIM A%(3)
A%(0)=1:A%(1)=2:A%(2)=3
!ZSUMNUMARRAY A%(0),3,S%
```

The resident parser resolves the array reference and stores a direct pointer in
the call frame before the overlay runs:

```asm
parse_sig_zsumnumarray:
        jsr rb_parse_int_array_input
        jsr rb_parse_out_int
        jsr rb_resolve_int_array_input_ptr
        rts
```

The overlay can then walk memory without calling BASIC ROM:

```asm
cmd_zsumnumarray_low:
        lda CF_PTR0_LO
        sta rb_ptr_lo
        lda CF_PTR0_HI
        sta rb_ptr_hi
        lda #0
        sta RF_VAL_LO
        sta RF_VAL_HI
        ldx CF_COUNT0_LO
        beq @done
@loop:
        ldy #1                    ; C64 integer low byte is second
        clc
        lda RF_VAL_LO
        adc (rb_ptr_lo),y
        sta RF_VAL_LO
        dey
        lda RF_VAL_HI
        adc (rb_ptr_lo),y
        sta RF_VAL_HI
        clc
        lda rb_ptr_lo
        adc #2                    ; next integer array element
        sta rb_ptr_lo
        bcc :+
        inc rb_ptr_hi
:       dex
        bne @loop
@done:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        rts
cmd_zsumnumarray_low_end:
```

`ZRANGENUMARRAY` is the output-array sibling. It stages integer bytes in the
result frame, then resident commit code writes those bytes into the BASIC array.
That keeps overlays from mutating output arrays directly after a failed command.

Descriptors:

```asm
CMD_LOW CMD_ZSUMNUMARRAY, SIG_ZSUMNUMARRAY,
        cmd_zsumnumarray_low, cmd_zsumnumarray_low_end, "ZSUMNUMARRAY"
CMD_LOW CMD_ZRANGENUMARRAY, SIG_ZRANGENUMARRAY,
        cmd_zrangenumarray_low, cmd_zrangenumarray_low_end, "ZRANGENUMARRAY"
```

Line-by-line commentary:

| Line or group | What it does |
| --- | --- |
| `jsr rb_parse_int_array_input` | Parses a base integer-array element like `A%(0)` and a count. |
| `jsr rb_resolve_int_array_input_ptr` | Converts that BASIC array reference into a direct C64 pointer in `CF_PTR0_LO/HI`. |
| `lda CF_PTR0_LO/HI` -> `rb_ptr_lo/hi` | Copies the resolved array pointer into the worker's indirect pointer. |
| `RF_VAL_LO/HI = 0` | Initializes the running sum. |
| `ldx CF_COUNT0_LO` | Uses X as the element counter. The current demo count is byte-sized. |
| `ldy #1` then `dey` | Reads C64 integer low byte then high byte from each two-byte element. |
| `adc (rb_ptr_lo),y` | Adds the current array element through the indirect pointer. |
| `adc #2` / `inc rb_ptr_hi` | Advances to the next integer element. |
| `RF_STATUS = 0`, `RF_TAG = RB_VAL_INT` | Marks the sum as a successful integer output. |
| `ZRANGENUMARRAY` descriptor | Publishes the sibling command that stages multiple integer outputs through the result frame. |

## BUFNEW, BUFFILL, BUFFREE, SCRCAP, SCRPUT: REU Handle Commands

The handle commands are the main future-facing pattern. BASIC sees a small
integer handle; canonical metadata lives in REU bank `$44`.

```asm
cmd_bufnew_low:
        jsr rb_handle_alloc
        rts

cmd_buffill_low:
        jsr rb_handle_fill
        rts

cmd_buffree_low:
        jsr rb_handle_free
        rts
```

The helper path converts byte length to 256-byte pages, finds a free handle,
finds contiguous heap pages, stores the descriptor in `$44:$0800-$09FF`, marks
the bitmap at `$44:$0C00`, and returns the one-based handle number.

Screen commands are typed handle commands:

```asm
cmd_scrcap_low:
        jsr rb_screen_handle_alloc
        lda RF_STATUS
        beq :+
        rts
:       jsr rb_screen_save_text
        jsr rb_screen_save_color
        ; return the new handle number in RF_VAL

cmd_scrput_low:
        jsr rb_screen_handle_validate
        lda RF_STATUS
        beq :+
        rts
:       jsr rb_screen_load_text
        jsr rb_screen_load_color
        ; no output variable is committed
```

Descriptors:

```asm
CMD_LOW_ALL CMD_BUFNEW, SIG_BUFNEW, cmd_bufnew_low, "BUFNEW"
CMD_LOW_ALL CMD_BUFFILL, SIG_BUFFILL, cmd_buffill_low, "BUFFILL"
CMD_LOW_ALL CMD_BUFFREE, SIG_BUFFREE, cmd_buffree_low, "BUFFREE"
CMD_LOW_ALL CMD_SCRCAP, SIG_SCRCAP, cmd_scrcap_low, "SCRCAP"
CMD_LOW_ALL CMD_SCRPUT, SIG_SCRPUT, cmd_scrput_low, "SCRPUT"
```

Line-by-line commentary:

| Line or group | What it does |
| --- | --- |
| `cmd_bufnew_low` / `jsr rb_handle_alloc` | Delegates allocation to shared low-overlay handle code. The descriptor uses `CMD_LOW_ALL` so the helper is present. |
| `cmd_buffill_low` / `jsr rb_handle_fill` | Validates a type-1 buffer handle and fills its heap pages through a small C64 transfer buffer. |
| `cmd_buffree_low` / `jsr rb_handle_free` | Frees any valid typed handle and clears REU metadata. |
| `cmd_scrcap_low` / `jsr rb_screen_handle_alloc` | Allocates a type-2 screen text+color handle. |
| `lda RF_STATUS` / `beq :+` / `rts` | If allocation failed, return immediately with the error status intact. |
| `jsr rb_screen_save_text` / `jsr rb_screen_save_color` | Copies `$0400-$07E7` text RAM and `$D800-$DBE7` color RAM into the REU handle. |
| `cmd_scrput_low` / `jsr rb_screen_handle_validate` | Checks that the input handle exists and is type-2 before restoring. |
| `jsr rb_screen_load_text` / `jsr rb_screen_load_color` | Copies the saved text and color pages back to the C64 screen. |
| `RF_TAG = RB_VAL_NONE` | Tells resident commit there is no BASIC output variable for `SCRPUT`. |
| `CMD_LOW_ALL ...` descriptors | Publish commands that depend on shared low-overlay helpers rather than copying tiny isolated slices. |

Why it matters: this is how future large objects should work. Keep BASIC-visible
values small, keep canonical resource metadata in REU, and validate handle type
at command boundaries. `BUFFILL` accepts only type-1 buffer handles; `SCRPUT`
accepts only type-2 screen text+color handles; `BUFFREE` frees any valid type.

## Checklist For Adding A Command

1. Choose a tokenizer-safe name, preferably avoiding embedded BASIC keywords.
2. Add a signature id and command id.
3. Add or reuse a parser signature that fills the call frame and clears outputs.
4. Add a low or hidden worker that only writes the result frame on success.
5. Add a descriptor entry; use `CMD_LOW_ALL` only when shared helpers require the
   full low pack.
6. Keep resident changes minimal. Prefer REU metadata and existing scratch pages.
7. Add direct and stored-program VICE coverage, including error behavior and any
   old-name rejection if this is a rename.
8. Update Markdown and HTML docs after static and VICE verification, using
   measured map values rather than predicted sizes.

## Appendix A: Descriptor And Registry Terms

| Term | Meaning |
| --- | --- |
| `REGSEED` | Cold-load descriptor image in C64 RAM during startup. It is copied to REU and then reclaimed, so it does not reduce empty BASIC free bytes. |
| `RB_CMD_DESC_COUNT` | Registry capacity, currently 128 descriptors. |
| `$44:$1000-$1FFF` | REU location of the 128 descriptor table. Runtime lookup pages through this table. |
| `RB_PAGEBUF` | C64 RAM page buffer used to fetch one 256-byte descriptor page, eight descriptors at a time. |
| `RB_DESC_BUF` | Resident buffer containing the single descriptor selected by lookup. |
| `RB_CMD_F_LOW` | Descriptor flag for a command whose executable code runs from the low overlay window. |
| `RB_CMD_F_HIDDEN` | Descriptor flag for a command whose executable code runs under BASIC ROM RAM. |
| `__LOWPACK_RUN__` | Linker symbol for the packed low-overlay image before it is copied to REU bank `$45`. |
| `__LOWPACK_SIZE__` | Measured size of the whole low pack, currently `$061A` bytes. |
| `RB_LOW_BASE` | Runtime low-overlay base, currently `$A900`. |
| `__HIDDENPACK_RUN__` | Linker symbol for the packed hidden-overlay image. |
| `RB_HIDDEN_BASE` | Runtime hidden-overlay base, currently `$A800`. |

## Appendix B: Call Frame And Result Frame Fields

| Field | Meaning |
| --- | --- |
| `CF_NUM0_LO/HI`, `CF_NUM1_LO/HI` | Numeric inputs evaluated by resident parser helpers. |
| `CF_STR_BUF`, `CF_STR_LEN` | Staged string input bytes and length. |
| `CF_PTR0_LO/HI` | Resolved pointer to a BASIC array or other structured input. |
| `CF_COUNT0_LO` | Count associated with an array-style input. |
| `RF_STATUS` | Command status. Zero means resident code may commit the result. Nonzero means error/no commit. |
| `RF_TAG` | Result type marker, such as `RB_VAL_INT`, `RB_VAL_STRING`, or `RB_VAL_NONE`. |
| `RF_VAL_LO/HI` | Staged 16-bit integer result or handle number. |
| `RF_STR_BUF`, `RF_STR_LEN` | Staged string result bytes and length. Resident code owns BASIC heap allocation. |
| `RF_ARR_BUF` | Staging area for array output bytes before resident commit writes them to BASIC variables. |

## Appendix C: Parser Helpers

| Helper | Meaning |
| --- | --- |
| `rb_parse_num0`, `rb_parse_num1` | Evaluate BASIC numeric expressions into call-frame numeric slots. |
| `rb_parse_string_value` | Evaluate or read a string value into `CF_STR_BUF`. |
| `rb_parse_out_int` | Capture an output integer variable and clear it before command execution. |
| `rb_parse_out_string` | Capture an output string variable descriptor and clear it before command execution. |
| `rb_parse_int_array_input` | Parse an integer array base element and count for read-only array input. |
| `rb_parse_int_array_output` | Parse an integer array target for staged array output commit. |
| `rb_resolve_int_array_input_ptr` | Resolve parsed array input into a direct memory pointer. |

## Appendix D: Overlay And Handle Helpers

| Helper or label | Meaning |
| --- | --- |
| `cmd_*_low` | Entry point for code copied to the low overlay window. |
| `cmd_*_low_end` | End marker used for descriptor copy-size math. |
| `cmd_*_hidden` | Entry point for code copied to the hidden overlay window under BASIC ROM RAM. |
| `rb_handle_alloc` | Allocates a typed handle descriptor and heap pages in REU bank `$44`. |
| `rb_handle_fill` | Fills a generic buffer handle, rejecting non-buffer handle types. |
| `rb_handle_free` | Frees any valid typed handle. |
| `rb_screen_handle_alloc` | Allocates a type-2 screen text+color handle. |
| `rb_screen_handle_validate` | Validates that a handle exists and is type-2 before `SCRPUT`. |
| `rb_screen_save_text`, `rb_screen_save_color` | Save text RAM and color RAM into a screen handle. |
| `rb_screen_load_text`, `rb_screen_load_color` | Restore text RAM and color RAM from a screen handle. |
