;
; readybasic.s - ReadyOS BASIC V2 bridge proof of concept
;
; Load address: $1000
; BASIC workspace: $1201-$9FFF
; Hidden helper code: RAM under BASIC ROM at $A000-$BFFF
; Visible bridge/mailbox/state: $C000-$C5BF
;

        .setcpu "6502"

; ---------------------------------------------------------------------------
; ROM/KERNAL entry points
; ---------------------------------------------------------------------------

CHRGET          = $0073
CHRGOT          = $0079
BASIC_ERROR     = $A43A
BASIC_MAIN      = $A483
BASIC_READY     = $A474
BASIC_CRUNCH    = $A57C
BASIC_LISTCHAR  = $A71A
BASIC_NEXT_STMT = $A7AE
BASIC_GONE      = $A7E4
BASIC_GONE_CONT = $A7E7
BASIC_EVAL      = $AE86
BASIC_FRMNUM    = $AD8A
BASIC_CHKCOM    = $AEFD
BASIC_SYNERR    = $AF08
BASIC_GETADR    = $B7F7
BASIC_INIT_RAM  = $E3BF
BASIC_RESTORE_VECTORS = $E453

K_SETLFS        = $FFBA
K_SETNAM        = $FFBD
K_OPEN          = $FFC0
K_CLOSE         = $FFC3
K_CHKIN         = $FFC6
K_CHKOUT        = $FFC9
K_CLRCHN        = $FFCC
K_CHRIN         = $FFCF
K_CHROUT        = $FFD2
K_GETIN         = $FFE4
K_RESTOR        = $FF8A
K_READST        = $FFB7
K_PLOT          = $FFF0

; ---------------------------------------------------------------------------
; BASIC/KERNAL workspace
; ---------------------------------------------------------------------------

TXTTAB          = $2B
VARTAB          = $2D
ARYTAB          = $2F
STREND          = $31
FRETOP          = $33
MEMSIZ          = $37
CURLIN          = $39
OLDTXT          = $3D
TXTPTR          = $7A

LINNUM          = $14
DFLTN           = $99
SCREEN_INPUT    = $D0
SHFLAG          = $028D
KEYD_COUNT      = $00C6
KEYD_BUFFER     = $0277
KERNAL_CHRIN_VEC= $0324
KERNAL_GETIN_VEC= $032A
KERNAL_MEMTOP    = $0281
KERNAL_MEMBOT    = $0283

BASIC_START     = $1201
BASIC_SENTINEL  = BASIC_START - 1
BASIC_LIMIT     = $A000
STD_BASIC_START = $0801
RELOC_DELTA     = BASIC_START - STD_BASIC_START

SCREEN          = $0400
COLOR_RAM       = $D800
VIC_BORDER      = $D020
VIC_BG          = $D021
CPU_PORT        = $0001

SHIM_RETURN     = $C80C
SHIM_SWITCH     = $C80F
SHIM_TARGET     = $C820
SHIM_CURRENT    = $C834
SHIM_BITMAP_LO  = $C836
SHIM_BITMAP_HI  = $C837
SHIM_BITMAP_XHI = $C838
SHIM_DRIVE      = $C839

; BASIC-compatible scratch pointers. These are outside cc65's reserved ZP set
; and are saved/restored for ReadyBASIC warm return.
rb_ptr_lo       = $FB
rb_ptr_hi       = $FC
rb_color_lo     = $FD
rb_color_hi     = $FE

RB_TOKEN        = $FE
RB_MAGIC_READY  = $52
RB_MAGIC_RUN    = $B2
RB_MAGIC2       = $A6
RAM_UNDER_BASIC = $FD
KEY_CTRL_B      = 2
KEY_F2          = 137
KEY_F4          = 138
APP_BANK_MIN    = 1
APP_BANK_MAX    = 23

; ---------------------------------------------------------------------------
; $1000 app entry
; ---------------------------------------------------------------------------

        .segment "LOADADDR"
        .word $1000

        .segment "ENTRY"

        .import __HIDDEN_LOAD__, __HIDDEN_RUN__, __HIDDEN_SIZE__
        .import __BRIDGE_LOAD__, __BRIDGE_RUN__, __BRIDGE_SIZE__

rb_entry_src    = $FB
rb_entry_dst    = $FD

entry:
        lda rb_entry_magic2
        cmp #RB_MAGIC2
        bne @cold
        lda rb_entry_magic
        cmp #RB_MAGIC_READY
        beq @warm
        cmp #RB_MAGIC_RUN
        beq @warm
@cold:
        sei
        lda CPU_PORT
        sta rb_entry_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        lda #<__HIDDEN_LOAD__
        sta rb_entry_src
        lda #>__HIDDEN_LOAD__
        sta rb_entry_src+1
        lda #<__HIDDEN_RUN__
        sta rb_entry_dst
        lda #>__HIDDEN_RUN__
        sta rb_entry_dst+1
        lda #<__HIDDEN_SIZE__
        sta rb_entry_len
        lda #>__HIDDEN_SIZE__
        sta rb_entry_len+1
        jsr entry_copy_block
        lda rb_entry_cpu
        sta CPU_PORT

        lda #<__BRIDGE_LOAD__
        sta rb_entry_src
        lda #>__BRIDGE_LOAD__
        sta rb_entry_src+1
        lda #<__BRIDGE_RUN__
        sta rb_entry_dst
        lda #>__BRIDGE_RUN__
        sta rb_entry_dst+1
        lda #<__BRIDGE_SIZE__
        sta rb_entry_len
        lda #>__BRIDGE_SIZE__
        sta rb_entry_len+1
        jsr entry_copy_block
        lda #RB_MAGIC_READY
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
@warm:
        jmp rb_boot

entry_copy_block:
        ldy #0
@loop:
        lda rb_entry_len
        ora rb_entry_len+1
        beq @done
        lda (rb_entry_src),y
        sta (rb_entry_dst),y
        inc rb_entry_src
        bne :+
        inc rb_entry_src+1
:       inc rb_entry_dst
        bne :+
        inc rb_entry_dst+1
:       sec
        lda rb_entry_len
        sbc #1
        sta rb_entry_len
        lda rb_entry_len+1
        sbc #0
        sta rb_entry_len+1
        jmp @loop
@done:
        rts

        .byte "READYBASIC POC",0

rb_entry_len:   .word 0
rb_entry_magic: .byte 0
rb_entry_magic2:.byte 0
rb_entry_cpu:   .byte 0

default_title:
        .byte "READYBASIC",0
help_text:
        .byte "RB SAVE/LOAD  CTRL+B HOME",0

; ---------------------------------------------------------------------------
; Hidden helper code, called through the visible trampoline.
; ---------------------------------------------------------------------------

        .segment "HIDDEN"

hidden_zp_save:
        .res 256, 0
hidden_stack_save:
        .res 256, 0

hidden_draw_text:
        lda rb_arg_y
        jsr mul40_to_ptr
        clc
        lda rb_ptr_lo
        adc rb_arg_x
        sta rb_ptr_lo
        bcc :+
        inc rb_ptr_hi
:       lda rb_ptr_hi
        clc
        adc #>SCREEN
        sta rb_ptr_hi

        lda rb_arg_y
        jsr mul40_to_ptr
        clc
        lda rb_ptr_lo
        adc rb_arg_x
        sta rb_color_lo
        lda rb_ptr_hi
        adc #>COLOR_RAM
        sta rb_color_hi

        ldy #$00
@copy:
        lda rb_strbuf,y
        beq @done
        jsr ascii_to_screen
        sta (rb_ptr_lo),y
        lda rb_arg_color
        sta (rb_color_lo),y
        iny
        cpy #32
        bcc @copy
@done:
        rts

; ---------------------------------------------------------------------------
; Visible bridge, wedge, mailbox, and state.
; ---------------------------------------------------------------------------

        .segment "BRIDGE"

rb_mailbox:
rb_status:      .byte 0
rb_error:       .byte 0
rb_cmd_seen:    .byte 0
rb_flags:       .byte 0
rb_result_lo:   .byte 0
rb_result_hi:   .byte 0
rb_last_st:     .byte 0
rb_drive:       .byte 0

rb_magic:       .byte 0
rb_magic2:      .byte 0
rb_saved_sp:    .byte 0
rb_saved_zp0:   .byte 0
rb_saved_zp1:   .byte 0
rb_arg_x:       .byte 0
rb_arg_y:       .byte 0
rb_arg_color:   .byte 1
rb_arg_a_lo:    .byte 0
rb_arg_a_hi:    .byte 0
rb_arg_b_lo:    .byte 0
rb_arg_b_hi:    .byte 0
rb_tmp_lo:      .byte 0
rb_tmp_hi:      .byte 0
rb_len:         .byte 0
rb_load_lo:     .byte 0
rb_load_hi:     .byte 0
rb_delta_lo:    .byte 0
rb_delta_hi:    .byte 0
rb_name_len:    .byte 0
rb_tmp_char:    .byte 0
rb_saved_cpu:   .byte 0
rb_ptr2_lo_tmp: .byte 0
rb_ptr2_hi_tmp: .byte 0
rb_vectors_saved:.byte 0
rb_orig_error_lo:.byte 0
rb_orig_error_hi:.byte 0
rb_orig_main_lo:.byte 0
rb_orig_main_hi:.byte 0
rb_orig_crunch_lo:.byte 0
rb_orig_crunch_hi:.byte 0
rb_orig_list_lo:.byte 0
rb_orig_list_hi:.byte 0
rb_orig_execute_lo:.byte 0
rb_orig_execute_hi:.byte 0
rb_orig_eval_lo:.byte 0
rb_orig_eval_hi:.byte 0
rb_orig_chrin_lo:.byte 0
rb_orig_chrin_hi:.byte 0
rb_orig_getin_lo:.byte 0
rb_orig_getin_hi:.byte 0
rb_nav_action:  .byte 0
rb_saved_txtptr_lo:.byte 0
rb_saved_txtptr_hi:.byte 0
rb_peek_lo:     .byte 0
rb_peek_hi:     .byte 0

rb_strbuf:      .res 33, 0
rb_namebuf:     .res 48, 0
rb_decbuf:      .res 6, 0

rb_boot:
        sei
        lda #$37
        sta CPU_PORT
        lda rb_magic2
        cmp #RB_MAGIC2
        bne rb_cold_start
        lda rb_magic
        cmp #RB_MAGIC_RUN
        beq rb_resume_running
        cmp #RB_MAGIC_READY
        beq rb_resume_ready

rb_cold_start:
        jsr K_RESTOR
        jsr BASIC_RESTORE_VECTORS
        jsr install_vectors
        jsr init_basic_workspace
        jsr prepare_basic_console
        jsr call_hidden_draw_default_header
        jsr position_basic_prompt
        lda #RB_MAGIC2
        sta rb_magic2
        lda #RB_MAGIC_READY
        sta rb_magic
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
        cli
        jmp BASIC_READY

rb_resume_ready:
        jsr install_vectors
        jsr prepare_basic_console
        jsr call_hidden_draw_default_header
        jsr position_basic_prompt
        lda #RB_MAGIC_READY
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
        cli
        jmp BASIC_READY

rb_resume_running:
        jsr install_vectors
        jsr restore_runtime_state
        lda #RB_MAGIC2
        sta rb_magic2
        lda #RB_MAGIC_READY
        sta rb_magic
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
        cli
        jmp BASIC_GONE

install_vectors:
        lda rb_vectors_saved
        bne @install
        lda $0300
        sta rb_orig_error_lo
        lda $0301
        sta rb_orig_error_hi
        lda $0302
        sta rb_orig_main_lo
        lda $0303
        sta rb_orig_main_hi
        lda $0304
        sta rb_orig_crunch_lo
        lda $0305
        sta rb_orig_crunch_hi
        lda $0306
        sta rb_orig_list_lo
        lda $0307
        sta rb_orig_list_hi
        lda $0308
        sta rb_orig_execute_lo
        lda $0309
        sta rb_orig_execute_hi
        lda $030A
        sta rb_orig_eval_lo
        lda $030B
        sta rb_orig_eval_hi
        lda KERNAL_CHRIN_VEC
        sta rb_orig_chrin_lo
        lda KERNAL_CHRIN_VEC+1
        sta rb_orig_chrin_hi
        lda KERNAL_GETIN_VEC
        sta rb_orig_getin_lo
        lda KERNAL_GETIN_VEC+1
        sta rb_orig_getin_hi
        lda #1
        sta rb_vectors_saved
@install:
        lda rb_orig_error_lo
        sta $0300
        lda rb_orig_error_hi
        sta $0301
        lda rb_orig_main_lo
        sta $0302
        lda rb_orig_main_hi
        sta $0303
        lda #<rb_crunch
        sta $0304
        lda #>rb_crunch
        sta $0305
        lda #<rb_list
        sta $0306
        lda #>rb_list
        sta $0307
        lda #<rb_execute
        sta $0308
        lda #>rb_execute
        sta $0309
        lda rb_orig_eval_lo
        sta $030A
        lda rb_orig_eval_hi
        sta $030B
        rts

restore_vectors:
        lda rb_vectors_saved
        beq @done
        lda rb_orig_error_lo
        sta $0300
        lda rb_orig_error_hi
        sta $0301
        lda rb_orig_main_lo
        sta $0302
        lda rb_orig_main_hi
        sta $0303
        lda rb_orig_crunch_lo
        sta $0304
        lda rb_orig_crunch_hi
        sta $0305
        lda rb_orig_list_lo
        sta $0306
        lda rb_orig_list_hi
        sta $0307
        lda rb_orig_execute_lo
        sta $0308
        lda rb_orig_execute_hi
        sta $0309
        lda rb_orig_eval_lo
        sta $030A
        lda rb_orig_eval_hi
        sta $030B
        lda rb_orig_chrin_lo
        sta KERNAL_CHRIN_VEC
        lda rb_orig_chrin_hi
        sta KERNAL_CHRIN_VEC+1
        lda rb_orig_getin_lo
        sta KERNAL_GETIN_VEC
        lda rb_orig_getin_hi
        sta KERNAL_GETIN_VEC+1
@done:
        rts

rb_call_orig_execute:
        jmp (rb_orig_execute_lo)

rb_call_orig_getin:
        jmp (rb_orig_getin_lo)

prepare_basic_console:
        lda #0
        sta KEYD_COUNT
        jsr K_CLRCHN
        lda #$93
        jsr K_CHROUT
        rts

position_basic_prompt:
        clc
        ldx #0
        ldy #3
        jsr K_PLOT
        lda #0
        sta KEYD_COUNT
        rts

init_basic_workspace:
        jsr clear_basic_workspace
        jsr set_basic_memory_bounds
        jsr BASIC_INIT_RAM
        jsr force_basic_workspace_pointers
        rts

force_basic_workspace_pointers:
        jsr set_basic_memory_bounds
        lda #$00
        sta BASIC_SENTINEL
        lda #<BASIC_START
        sta TXTTAB
        lda #>BASIC_START
        sta TXTTAB+1
        lda #$00
        sta BASIC_START
        sta BASIC_START+1
        lda #<(BASIC_START+2)
        sta VARTAB
        sta ARYTAB
        sta STREND
        lda #>(BASIC_START+2)
        sta VARTAB+1
        sta ARYTAB+1
        sta STREND+1
        lda #<BASIC_LIMIT
        sta FRETOP
        sta MEMSIZ
        lda #>BASIC_LIMIT
        sta FRETOP+1
        sta MEMSIZ+1
        lda #$FF
        sta CURLIN
        sta CURLIN+1
        sta OLDTXT
        sta OLDTXT+1
        lda #<BASIC_START
        sta TXTPTR
        lda #>BASIC_START
        sta TXTPTR+1
        rts

ensure_basic_workspace_pointers:
        jsr set_basic_memory_bounds
        lda #<BASIC_START
        sta TXTTAB
        lda #>BASIC_START
        sta TXTTAB+1
        lda #<BASIC_LIMIT
        sta FRETOP
        sta MEMSIZ
        lda #>BASIC_LIMIT
        sta FRETOP+1
        sta MEMSIZ+1
        lda VARTAB+1
        cmp #>BASIC_START
        bcc @reset_vars
        cmp #>BASIC_LIMIT
        bcs @reset_vars
        rts
@reset_vars:
        lda #0
        sta BASIC_START
        sta BASIC_START+1
        lda #<(BASIC_START+2)
        sta VARTAB
        sta ARYTAB
        sta STREND
        lda #>(BASIC_START+2)
        sta VARTAB+1
        sta ARYTAB+1
        sta STREND+1
        rts

set_basic_memory_bounds:
        lda #<BASIC_SENTINEL
        sta KERNAL_MEMBOT
        lda #>BASIC_SENTINEL
        sta KERNAL_MEMBOT+1
        lda #<BASIC_LIMIT
        sta KERNAL_MEMTOP
        lda #>BASIC_LIMIT
        sta KERNAL_MEMTOP+1
        rts

clear_basic_workspace:
        lda #<BASIC_START
        sta rb_ptr_lo
        lda #>BASIC_START
        sta rb_ptr_hi
        lda #0
        tay
@loop:
        sta (rb_ptr_lo),y
        inc rb_ptr_lo
        bne :+
        inc rb_ptr_hi
:       lda rb_ptr_hi
        cmp #>BASIC_LIMIT
        bne @zero_next
        lda rb_ptr_lo
        cmp #<BASIC_LIMIT
        beq @done
@zero_next:
        lda #0
        jmp @loop
@done:
        rts

; ICRNCH replacement: keep BASIC's line editor stable for the POC. RB is
; recognized as raw text by IGONE, so ordinary program entry is untouched.
rb_crunch:
        jsr ensure_basic_workspace_pointers
        jmp BASIC_CRUNCH

; IQPLOP replacement: print our private token as RB, otherwise defer.
rb_list:
        cmp #RB_TOKEN
        beq @mine
        jmp BASIC_LISTCHAR
@mine:
        lda #'R'
        jsr K_CHROUT
        lda #'B'
        jsr K_CHROUT
        rts

; IGONE replacement: handle RB statements and check CTRL+B at statement edge.
rb_execute:
        jsr ensure_basic_workspace_pointers
        jsr rb_check_ctrl_b
        jsr rb_peek_next_nonspace
        cmp #RB_TOKEN
        beq rb_statement_token
        cmp #'R'
        beq @maybe_raw
        cmp #'r'
        beq @maybe_raw
        jmp rb_execute_fallback
@maybe_raw:
        lda rb_peek_lo
        sta rb_ptr_lo
        lda rb_peek_hi
        sta rb_ptr_hi
        ldy #1
        lda (rb_ptr_lo),y
        cmp #'B'
        beq @raw_match
        cmp #'b'
        beq @raw_match
        jmp rb_execute_fallback
@raw_match:
        lda rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        sta TXTPTR+1
        jsr CHRGET
        jsr CHRGET
        jmp rb_statement
rb_statement_token:
        lda rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        sta TXTPTR+1
        jsr CHRGET

rb_statement:
        jsr parse_const_u8
        sta rb_cmd_seen
        cmp #1
        bne :+
        jmp cmd_header
:       cmp #2
        bne :+
        jmp cmd_text
:       cmp #3
        bne :+
        jmp cmd_add
:       cmp #10
        bne :+
        jmp cmd_save
:       cmp #11
        bne :+
        jmp cmd_load
:       cmp #12
        bne :+
        jmp cmd_clear
:       jmp BASIC_SYNERR

rb_execute_fallback:
        jmp rb_call_orig_execute

rb_peek_next_nonspace:
        lda TXTPTR
        sta rb_ptr_lo
        lda TXTPTR+1
        sta rb_ptr_hi
@next:
        inc rb_ptr_lo
        bne :+
        inc rb_ptr_hi
:       ldy #0
        lda (rb_ptr_lo),y
        cmp #' '
        beq @next
        ldx rb_ptr_lo
        stx rb_peek_lo
        ldx rb_ptr_hi
        stx rb_peek_hi
        rts

cmd_header:
        jsr parse_comma_string
        jsr parse_comma_byte
        sta rb_arg_color
        jsr parse_comma_byte
        sta VIC_BG
        sta VIC_BORDER
        jsr call_hidden_draw_header
        jmp rb_ok

cmd_text:
        jsr parse_comma_expr_byte
        sta rb_arg_x
        jsr parse_comma_expr_byte
        sta rb_arg_y
        jsr parse_comma_string
        jsr parse_comma_expr_byte
        sta rb_arg_color
        jsr call_hidden_draw_text
        jmp rb_ok

cmd_add:
        jsr parse_comma_expr_u16
        lda LINNUM
        sta rb_arg_a_lo
        lda LINNUM+1
        sta rb_arg_a_hi
        jsr parse_comma_expr_u16
        clc
        lda rb_arg_a_lo
        adc LINNUM
        sta rb_result_lo
        lda rb_arg_a_hi
        adc LINNUM+1
        sta rb_result_hi
        jmp rb_ok

cmd_save:
        jsr parse_comma_string
        jsr call_hidden_save_program
        jmp rb_ok

cmd_load:
        jsr parse_comma_string
        jsr call_hidden_load_program
        jmp rb_ok

cmd_clear:
        jsr init_basic_workspace
        jsr call_hidden_draw_default_header
        jmp rb_ok

rb_ok:
        lda #0
        sta rb_status
        sta rb_error
        lda CURLIN+1
        cmp #$FF
        beq @direct
        jmp BASIC_NEXT_STMT
@direct:
        jmp BASIC_READY

rb_err:
        sta rb_error
        lda #$FF
        sta rb_status
        rts

; ---------------------------------------------------------------------------
; CTRL+B statement-boundary save/return and warm restore.
; ---------------------------------------------------------------------------

rb_check_ctrl_b:
        lda KEYD_COUNT
        beq @done
        lda KEYD_BUFFER
        cmp #KEY_CTRL_B
        beq rb_suspend_running_launcher
@done:
        rts

rb_suspend_running_launcher:
        jsr rb_call_orig_getin
        lda #0
        sta rb_nav_action
        jmp rb_save_running_state

rb_save_running_state:
        sei
        tsx
        stx rb_saved_sp
        ldx #0
@copy_zp:
        lda $0000,x
        sta hidden_zp_save,x
        lda $0100,x
        sta hidden_stack_save,x
        inx
        bne @copy_zp
        lda #RB_MAGIC_RUN
        sta rb_magic
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_magic2
        sta rb_entry_magic2
        lda #0
        sta KEYD_COUNT
        jsr restore_vectors
        jmp SHIM_RETURN

restore_runtime_state:
        sei
        lda CPU_PORT
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        lda hidden_zp_save
        sta rb_saved_zp0
        lda hidden_zp_save+1
        sta rb_saved_zp1
        ldx #0
@copy_stack:
        lda hidden_stack_save,x
        sta $0100,x
        inx
        bne @copy_stack
        ldx #2
@copy_zp:
        lda hidden_zp_save,x
        sta $0000,x
        inx
        bne @copy_zp
        lda rb_saved_zp0
        sta $0000
        lda rb_saved_zp1
        sta $0001
        ldx rb_saved_sp
        txs
        rts

; ---------------------------------------------------------------------------
; Parsing helpers.
; ---------------------------------------------------------------------------

parse_const_u8:
        lda #0
        sta rb_tmp_lo
@skip_spaces:
        jsr CHRGOT
        cmp #' '
        bne @loop
        jsr CHRGET
        jmp @skip_spaces
@loop:
        jsr CHRGOT
        cmp #'0'
        bcc @done
        cmp #'9'+1
        bcs @done
        sec
        sbc #'0'
        pha
        lda rb_tmp_lo
        asl
        sta rb_tmp_hi
        asl
        asl
        clc
        adc rb_tmp_hi
        sta rb_tmp_lo
        pla
        clc
        adc rb_tmp_lo
        sta rb_tmp_lo
        jsr CHRGET
        jmp @loop
@done:
        lda rb_tmp_lo
        rts

parse_comma_byte:
        jsr BASIC_CHKCOM
        jsr parse_const_u8
        rts

parse_comma_expr_byte:
        jsr parse_comma_expr_u16
        lda LINNUM
        rts

parse_comma_expr_u16:
        jsr BASIC_CHKCOM
        jsr BASIC_FRMNUM
        jsr BASIC_GETADR
        rts

parse_comma_string:
        jsr BASIC_CHKCOM
        jsr CHRGOT
        cmp #'"'
        beq @quoted
        jmp BASIC_SYNERR
@quoted:
        jsr CHRGET
        ldy #0
@copy:
        jsr CHRGOT
        cmp #'"'
        beq @end
        cmp #0
        beq @bad
        cpy #32
        bcs @skip
        sta rb_strbuf,y
        iny
@skip:
        jsr CHRGET
        jmp @copy
@end:
        lda #0
        sta rb_strbuf,y
        jsr CHRGET
        rts
@bad:
        jmp BASIC_SYNERR

; ---------------------------------------------------------------------------
; TUI helpers.
; ---------------------------------------------------------------------------

        .segment "HIDDEN"

draw_default_header:
        lda #6
        sta VIC_BG
        sta VIC_BORDER
        lda #1
        sta rb_arg_color
        ldx #0
@title:
        lda default_title,x
        sta rb_strbuf,x
        beq @draw
        inx
        bne @title
@draw:
        jsr draw_header_from_buffer
        rts

draw_header_from_buffer:
        lda rb_arg_color
        pha
        lda #0
        jsr clear_screen_row
        lda #1
        jsr clear_screen_row
        pla
        sta rb_arg_color
        lda #1
        sta rb_arg_x
        lda #0
        sta rb_arg_y
        jsr hidden_draw_text
        ldx #0
@help:
        lda help_text,x
        sta rb_strbuf,x
        beq @draw_help
        inx
        cpx #33
        bcc @help
        lda #0
        sta rb_strbuf+32
@draw_help:
        lda #0
        sta rb_arg_x
        lda #1
        sta rb_arg_y
        lda #15
        sta rb_arg_color
        jsr hidden_draw_text
        rts

clear_screen_row:
        jsr mul40_to_ptr
        lda rb_ptr_hi
        clc
        adc #>SCREEN
        sta rb_ptr_hi
        lda rb_ptr_lo
        sta rb_color_lo
        lda rb_ptr_hi
        sec
        sbc #>SCREEN
        clc
        adc #>COLOR_RAM
        sta rb_color_hi
        lda #1
        sta rb_arg_color
        ldy #39
@loop:
        lda #32
        sta (rb_ptr_lo),y
        lda rb_arg_color
        sta (rb_color_lo),y
        dey
        bpl @loop
        rts

mul40_to_ptr:
        sta rb_ptr_lo
        lda #0
        sta rb_ptr_hi
        asl rb_ptr_lo
        rol rb_ptr_hi
        asl rb_ptr_lo
        rol rb_ptr_hi
        asl rb_ptr_lo
        rol rb_ptr_hi
        lda rb_ptr_lo
        sta rb_tmp_lo
        lda rb_ptr_hi
        sta rb_tmp_hi
        asl rb_ptr_lo
        rol rb_ptr_hi
        asl rb_ptr_lo
        rol rb_ptr_hi
        clc
        lda rb_ptr_lo
        adc rb_tmp_lo
        sta rb_ptr_lo
        lda rb_ptr_hi
        adc rb_tmp_hi
        sta rb_ptr_hi
        rts

ascii_to_screen:
        cmp #'A'
        bcc @digit
        cmp #'Z'+1
        bcs @lower
        sec
        sbc #'A'-1
        rts
@lower:
        cmp #'a'
        bcc @digit
        cmp #'z'+1
        bcs @digit
        sec
        sbc #'a'-1
        rts
@digit:
        cmp #'0'
        bcc @punct
        cmp #'9'+1
        bcs @punct
        rts
@punct:
        cmp #'@'
        bne :+
        lda #0
        rts
:       cmp #' '
        bne :+
        lda #32
        rts
:       cmp #'.'
        bne :+
        lda #46
        rts
:       cmp #':'
        bne :+
        lda #58
        rts
:       cmp #'+'
        bne :+
        lda #43
        rts
:       cmp #'-'
        bne :+
        lda #45
        rts
:       cmp #'='
        bne :+
        lda #61
        rts
:       cmp #'"'
        bne :+
        lda #34
        rts
:       lda #32
        rts

        .segment "BRIDGE"

call_hidden_draw_default_header:
        php
        sei
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        jsr draw_default_header
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

call_hidden_draw_header:
        php
        sei
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        jsr draw_header_from_buffer
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

call_hidden_draw_text:
        php
        sei
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        jsr hidden_draw_text
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

call_hidden_save_program:
        php
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        jsr save_program
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

call_hidden_load_program:
        php
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        jsr load_program
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

; ---------------------------------------------------------------------------
; File load/save helpers.
; ---------------------------------------------------------------------------

        .segment "HIDDEN"

append_file_mode:
        ldx #0
@find_end:
        lda rb_strbuf,x
        beq @suffix
        sta rb_namebuf,x
        inx
        cpx #36
        bcc @find_end
@suffix:
        lda #','
        sta rb_namebuf,x
        inx
        lda #'p'
        sta rb_namebuf,x
        inx
        lda #','
        sta rb_namebuf,x
        inx
        lda rb_tmp_char
        sta rb_namebuf,x
        inx
        stx rb_name_len
        lda #0
        sta rb_namebuf,x
        rts

open_file:
        lda rb_name_len
        ldx #<rb_namebuf
        ldy #>rb_namebuf
        jsr K_SETNAM
        lda rb_drive
        bne :+
        lda SHIM_DRIVE
        bne :+
        lda #8
:       tax
        lda #2
        ldy #2
        jsr K_SETLFS
        jsr K_OPEN
        bcs @err
        lda #0
        rts
@err:
        lda #1
        rts

close_file:
        jsr K_CLRCHN
        lda #2
        jsr K_CLOSE
        rts

save_program:
        lda #'w'
        sta rb_tmp_char
        jsr append_file_mode
        jsr open_file
        beq :+
        lda #10
        jsr rb_err
        rts
:       ldx #2
        jsr K_CHKOUT
        lda #<STD_BASIC_START
        jsr K_CHROUT
        lda #>STD_BASIC_START
        jsr K_CHROUT

        lda #<BASIC_START
        sta rb_ptr_lo
        lda #>BASIC_START
        sta rb_ptr_hi
@line:
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_tmp_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_tmp_hi
        ora rb_tmp_lo
        beq @end_marker
        sec
        lda rb_tmp_lo
        sbc #<RELOC_DELTA
        sta rb_ptr2_lo_tmp
        lda rb_tmp_hi
        sbc #>RELOC_DELTA
        sta rb_ptr2_hi_tmp
        lda rb_ptr2_lo_tmp
        jsr K_CHROUT
        lda rb_ptr2_hi_tmp
        jsr K_CHROUT
        ldy #2
@bytes:
        lda (rb_ptr_lo),y
        jsr K_CHROUT
        lda (rb_ptr_lo),y
        beq @advance
        iny
        bne @bytes
        lda #11
        jsr rb_err
        jsr close_file
        rts
@advance:
        lda rb_tmp_lo
        sta rb_ptr_lo
        lda rb_tmp_hi
        sta rb_ptr_hi
        jmp @line
@end_marker:
        lda #0
        jsr K_CHROUT
        lda #0
        jsr K_CHROUT
        jsr close_file
        jsr rb_ok
        rts

load_program:
        lda #'r'
        sta rb_tmp_char
        jsr append_file_mode
        jsr open_file
        beq :+
        lda #20
        jsr rb_err
        rts
:       ldx #2
        jsr K_CHKIN
        jsr K_CHRIN
        sta rb_load_lo
        jsr K_CHRIN
        sta rb_load_hi
        sec
        lda #<BASIC_START
        sbc rb_load_lo
        sta rb_delta_lo
        lda #>BASIC_START
        sbc rb_load_hi
        sta rb_delta_hi

        lda #<BASIC_START
        sta rb_ptr_lo
        lda #>BASIC_START
        sta rb_ptr_hi
@read:
        jsr K_CHRIN
        pha
        jsr K_READST
        sta rb_last_st
        pla
        ldy #0
        sta (rb_ptr_lo),y
        inc rb_ptr_lo
        bne :+
        inc rb_ptr_hi
:       lda rb_ptr_hi
        cmp #>BASIC_LIMIT
        bcc :+
        lda #21
        jsr rb_err
        jsr close_file
        rts
:       lda rb_last_st
        beq @read
        jsr close_file
        jsr relocate_loaded_program
        jsr draw_default_header
        jsr rb_ok
        rts

relocate_loaded_program:
        lda #<BASIC_START
        sta rb_ptr_lo
        lda #>BASIC_START
        sta rb_ptr_hi
@line:
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_tmp_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_tmp_hi
        ora rb_tmp_lo
        beq @done
        clc
        lda rb_tmp_lo
        adc rb_delta_lo
        sta rb_tmp_lo
        dey
        sta (rb_ptr_lo),y
        iny
        lda rb_tmp_hi
        adc rb_delta_hi
        sta rb_tmp_hi
        sta (rb_ptr_lo),y
        lda rb_tmp_hi
        cmp #>BASIC_LIMIT
        bcc @advance
        jmp init_basic_workspace
@advance:
        lda rb_tmp_lo
        sta rb_ptr_lo
        lda rb_tmp_hi
        sta rb_ptr_hi
        jmp @line
@done:
        clc
        lda rb_ptr_lo
        adc #2
        sta VARTAB
        sta ARYTAB
        sta STREND
        lda rb_ptr_hi
        adc #0
        sta VARTAB+1
        sta ARYTAB+1
        sta STREND+1
        lda #<BASIC_LIMIT
        sta FRETOP
        sta MEMSIZ
        lda #>BASIC_LIMIT
        sta FRETOP+1
        sta MEMSIZ+1
        rts
