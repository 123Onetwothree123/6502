# ReadyBASIC Making Command Guide

This guide explains how current ReadyBASIC commands are made in
`src/apps/readybasic/readybasic.s`. It uses the current names and layout:
128 descriptor slots in REU bank `$44`, packed command code in bank `$45`,
`SCRCAP` in slot 14, `SCRPUT` in slot 128, and zero-filled filler slots 15-127.

## Naming Rules

ReadyBASIC command names are visible BASIC text after `!`; they are not private
tokens. Avoid substrings that C64 BASIC can tokenize inside the command name.
That is why the demo/proof commands use the `Z...` namespace and why the array
examples use `NUM` instead of `INT`.

Historical names such as `PING`, `ADD16`, `STRUP`, `HCRC`, `SUMAI`,
`RANGEAI`, `TEMPSCRATCH`, and `FAIL` are not aliases. The current public names
are `ZECHO1`, `ZADD16`, `UPPER`, `LOWER`, `ZHIDDENRAM`, `ZSUMNUMARRAY`,
`ZRANGENUMARRAY`, `ZTEMPSCRATCH`, and `ZFAIL`.

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
