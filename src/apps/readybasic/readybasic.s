;
; readybasic.s - lean ReadyBASIC REU plugin command spine
;
; Load address: $1000
; Visible resident core: $1200-$2ABF
; Low command overlay: $A900-$BFFF, under BASIC ROM
; Shared call/result buffers: $C200-$C5FF
; BASIC workspace: $2AC1-$9FFF
; Runtime zero page/stack snapshot: REU bank $44 offsets $0A00/$0B00
; Hidden helper shadow: $C280+, restored to $A000+ on warm entry
; Bridge state/trampolines: $C000-$C1FF
;

        .setcpu "6502"

; ---------------------------------------------------------------------------
; ROM/KERNAL entry points
; ---------------------------------------------------------------------------

CHRGET          = $0073
CHRGOT          = $0079
BASIC_READY     = $A474
BASIC_NEXT_STMT = $A7AE
BASIC_GONE      = $A7E4
BASIC_EVAL      = $AE86
BASIC_FRMEVL    = $AD9E
BASIC_FRMNUM    = $AD8A
BASIC_CHKCOM    = $AEFD
BASIC_SYNERR    = $AF08
BASIC_PTRGET    = $B08B
BASIC_FADD      = $B867
BASIC_GIVAYF    = $B391
BASIC_PUTNEW    = $B4CA
BASIC_FRESTR    = $B6A3
BASIC_MOVFM     = $BBA2
BASIC_MOVMF     = $BBD4
BASIC_GETADR    = $B7F7
BASIC_LINPRT    = $BDCD
BASIC_RESTORE_VECTORS = $E453

K_CHROUT        = $FFD2
K_CLRCHN        = $FFCC
K_PLOT          = $FFF0
K_RESTOR        = $FF8A

; ---------------------------------------------------------------------------
; BASIC/KERNAL workspace
; ---------------------------------------------------------------------------

VALTYP          = $0D
INTFLG          = $0E
LINNUM          = $14
TXTTAB          = $2B
VARTAB          = $2D
ARYTAB          = $2F
STREND          = $31
FRETOP          = $33
MEMSIZ          = $37
CURLIN          = $39
TXTPTR          = $7A
DFLTN           = $99
VARPNT          = $47
SUBFLG          = $10
DSCPTR          = $64
DSCPTR_HI       = $65
FAC_EXP         = $61
FAC_MANT1       = $62
FAC_MANT2       = $63
KEYD_COUNT      = $00C6
COLOR_CODE      = $0286
KERNAL_MEMTOP   = $0281
KERNAL_MEMBOT   = $0283

BASIC_START     = $2AC1
BASIC_SENTINEL  = BASIC_START - 1
BASIC_LIMIT     = $A000
BASIC_BYTES_FREE = BASIC_LIMIT - (BASIC_START + 2)
BASIC_INPUT_BUF = $0200
BASIC_INPUT_MAX = $58
RUNTIME_ZP_BUF  = $C400
RUNTIME_STACK_BUF = $C500
HIDDEN_SHADOW   = $C280

CPU_DDR         = $0000
CPU_PORT        = $0001
SCREEN          = $0400
COLOR_RAM       = $D800
VIC_MEM         = $D018
VIC_BORDER      = $D020
VIC_BG          = $D021

SHIM_RETURN     = $C80C

; Scratch pointers outside cc65's reserved zero-page runtime.
rb_ptr_lo       = $FB
rb_ptr_hi       = $FC
rb_ptr2_lo      = $FD
rb_ptr2_hi      = $FE

RB_MAGIC_READY  = $52
RB_MAGIC_RUN    = $B2
RB_MAGIC2       = $A6
RB_STATE_MAGIC1 = $72
RB_STATE_MAGIC2 = $62
RB_RESUME_READY = 0
RB_RESUME_RUN   = 1
TOKEN_THEN      = $A7
TOKEN_END       = $80
TOKEN_REM       = $8F
TOKEN_PLUS      = $AA
TOKEN_EQUAL     = $B2

RAM_UNDER_BASIC = $FD
RAM_UNDER_BASIC_KEEP_KERNAL = $FE
VIC_MEM_LOWERCASE = $16

; ---------------------------------------------------------------------------
; ReadyBASIC plugin ABI constants
; ---------------------------------------------------------------------------

RB_SLOT0_BASE   = $A800
RB_SLOT1_BASE   = $B000
RB_SLOT2_BASE   = $B800
RB_LOW_BASE     = RB_SLOT0_BASE
RB_HIDDEN_BASE  = $A000
RB_SHARED       = $C200
RB_CF           = $C200
RB_RF           = $C300
RB_DESC_BUF     = $C480
RB_CMDBUF       = $C4A0
RB_PAGEBUF      = $C500

CF_CMD_ID       = RB_CF + $00
CF_PARAM_COUNT  = RB_CF + $01
CF_NUM0_LO      = RB_CF + $10
CF_NUM0_HI      = RB_CF + $11
CF_NUM1_LO      = RB_CF + $12
CF_NUM1_HI      = RB_CF + $13
CF_NUM2_LO      = RB_CF + $14
CF_NUM2_HI      = RB_CF + $15
CF_FLOAT0       = RB_CF + $20
CF_FLOAT1       = RB_CF + $25
CF_FLOAT2       = RB_CF + $2A
CF_PTR0_LO      = RB_CF + $40
CF_PTR0_HI      = RB_CF + $41
CF_COUNT0_LO    = RB_CF + $42
CF_COUNT0_HI    = RB_CF + $43
CF_STR_LEN      = RB_CF + $50
CF_STR_BUF      = RB_CF + $60

RF_STATUS       = RB_RF + $00
RF_ERROR        = RB_RF + $01
RF_TAG          = RB_RF + $02
RF_VAL_LO       = RB_RF + $03
RF_VAL_HI       = RB_RF + $04
RF_COUNT_LO     = RB_RF + $05
RF_COUNT_HI     = RB_RF + $06
RF_FLOAT        = RB_RF + $08
RF_STR_LEN      = RB_RF + $10
RF_STR_BUF      = RB_RF + $20
RF_ARRAY_BUF    = RB_RF + $80

RB_VAL_NONE     = 0
RB_VAL_INT      = 1
RB_VAL_STRING   = 2
RB_VAL_ARRAYI   = 3
RB_VAL_FLOAT    = 4

RB_OUT_NONE     = 0
RB_OUT_INT      = 1
RB_OUT_STRING   = 2
RB_OUT_ARRAYI   = 3
RB_OUT_FLOAT    = 4

RB_MODULE_SYSTEM = 1
RB_SUBMOD_COMMON = 0
RB_SUBMOD_LEGACY_LOW = 1
RB_SUBMOD_PROOF_SLOT1 = 2
RB_SUBMOD_PROOF_SLOT2 = 3
RB_SLOT_LEGACY_LOW = $01
RB_SLOT_PROOF_1 = $02
RB_SLOT_PROOF_2 = $04
RB_SLOT_COMMON = $80
RB_SLOT_INVALID = $FF

RB_REU_CORE_BANK= $44
RB_REU_CODE_BANK= $45
RB_REU_TYPE_CORE= 14
RB_REU_TYPE_CODE= 15
RB_REU_ALLOC_TABLE = $C600
RB_REU_HEADER_OFF  = $0000
RB_REU_DESC_OFF    = $1000
RB_REU_SLOT_STATE_OFF = $2000
RB_REU_CALL_OFF    = $0400
RB_REU_RESULT_OFF  = $0400
RB_REU_DEBUG_OFF   = $0600
RB_REU_HANDLE_OFF  = $0800
RB_REU_HEAP_OFF    = $0C00
RB_REU_RUNTIME_ZP_OFF = $0A00
RB_REU_RUNTIME_STACK_OFF = $0B00
RB_REU_COMMON_LIMIT= $4000
RB_REU_DATA_OFF    = $4000

RB_CMD_DESC_SIZE   = 32
RB_CMD_DESC_COUNT  = 128
RB_CMD_DESC_PER_PAGE = 8
RB_MAX_NAME        = 15
RB_MAX_STR         = 64
RB_HANDLE_COUNT    = 128
RB_HANDLE_DESC_SIZE= 4
RB_HANDLE_PAGE_SLOTS = 64
RB_HEAP_PAGES      = 192
RB_HEAP_PAGE_BASE  = >RB_REU_DATA_OFF
RB_HANDLE_TYPE_BUFFER = 1
RB_HANDLE_TYPE_SCREEN_TC = 2
RB_SCREEN_BYTES    = $03E8
RB_SCREEN_HANDLE_PAGES = 8

SIG_ZECHO1      = 1
SIG_ZADD16      = 2
SIG_UPPER       = 3
SIG_LOWER       = 4
SIG_ZHIDDENRAM  = 5
SIG_ZSUMNUMARRAY = 6
SIG_ZRANGENUMARRAY = 7
SIG_BUFNEW      = 8
SIG_BUFFILL     = 9
SIG_BUFFREE     = 10
SIG_ZTEMPSCRATCH = 11
SIG_ZFAIL       = 12
SIG_FREEMEM     = 13
SIG_SCRCAP      = 14
SIG_SCRPUT      = 15
SIG_FADD        = 16
SIG_ZPAUSE      = SIG_BUFFREE
SIG_ERRCODE     = 17
SIG_ERRLINE     = 18

CMD_ZECHO1      = 1
CMD_ZADD16      = 2
CMD_UPPER       = 3
CMD_LOWER       = 4
CMD_ZHIDDENRAM  = 5
CMD_ZSUMNUMARRAY = 6
CMD_ZRANGENUMARRAY = 7
CMD_BUFNEW      = 8
CMD_BUFFILL     = 9
CMD_BUFFREE     = 10
CMD_ZTEMPSCRATCH = 11
CMD_ZFAIL       = 12
CMD_FREEMEM     = 13
CMD_SCRCAP      = 14
CMD_SCRPUT      = 15
CMD_FADD        = 16
CMD_ZPAUSE      = 17
CMD_ERRCODE     = 18
CMD_ERRLINE     = 19
CMD_ZSLOT0      = 20
CMD_ZSLOT1      = 21
CMD_ZSLOT2      = 22

; REU registers.
REU_CMD         = $DF01
REU_C64_LO      = $DF02
REU_C64_HI      = $DF03
REU_ADDR_LO     = $DF04
REU_ADDR_HI     = $DF05
REU_BANK        = $DF06
REU_LEN_LO      = $DF07
REU_LEN_HI      = $DF08

; ---------------------------------------------------------------------------
; $1000 app entry
; ---------------------------------------------------------------------------

        .segment "LOADADDR"
        .word $1000

        .segment "ENTRY"

        .import __HIDDEN_LOAD__, __HIDDEN_RUN__, __HIDDEN_SIZE__
        .import __BRIDGE_LOAD__, __BRIDGE_RUN__, __BRIDGE_SIZE__
        .import __LOWPACK_LOAD__, __LOWPACK_RUN__, __LOWPACK_SIZE__
        .import __SLOTPACK1_LOAD__, __SLOTPACK1_RUN__, __SLOTPACK1_SIZE__
        .import __SLOTPACK2_LOAD__, __SLOTPACK2_RUN__, __SLOTPACK2_SIZE__

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
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
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

        lda #<__HIDDEN_LOAD__
        sta rb_entry_src
        lda #>__HIDDEN_LOAD__
        sta rb_entry_src+1
        lda #<HIDDEN_SHADOW
        sta rb_entry_dst
        lda #>HIDDEN_SHADOW
        sta rb_entry_dst+1
        lda #<__HIDDEN_SIZE__
        sta rb_entry_len
        lda #>__HIDDEN_SIZE__
        sta rb_entry_len+1
        jsr entry_copy_block

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
        jmp rb_boot
@warm:
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_entry_cpu
        and #RAM_UNDER_BASIC
        sta CPU_PORT
        lda #<HIDDEN_SHADOW
        sta rb_entry_src
        lda #>HIDDEN_SHADOW
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

        .byte "READYBASIC REU",0

rb_entry_len:   .word 0
rb_entry_magic: .byte 0
rb_entry_magic2:.byte 0
rb_entry_cpu:   .byte 0

        .segment "PADLOW"
        .res $0000, 0

; ---------------------------------------------------------------------------
; Visible resident core.
; ---------------------------------------------------------------------------

        .segment "RESIDENT"

rb_boot:
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
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
        lda #1
        sta rb_seed_cold
        jsr call_hidden_seed_plugin_reu
        jsr prepare_basic_console
        jsr rb_draw_header
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
        lda #0
        sta rb_seed_cold
        jsr call_hidden_seed_plugin_reu
        lda #RB_MAGIC_READY
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
        cli
        jmp restore_basic_runtime_state

rb_resume_running:
        jsr install_vectors
        lda #0
        sta rb_seed_cold
        jsr call_hidden_seed_plugin_reu
        lda #RB_MAGIC_RUN
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_entry_magic2
        cli
        jmp restore_basic_runtime_state

install_vectors:
        lda rb_vectors_saved
        bne @install
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
        lda #1
        sta rb_vectors_saved
@install:
        lda #<rb_crunch
        sta $0304
        lda #>rb_crunch
        sta $0305
        lda #<rb_execute
        sta $0308
        lda #>rb_execute
        sta $0309
        lda #<rb_eval
        sta $030A
        lda #>rb_eval
        sta $030B
        rts

restore_vectors:
        lda rb_vectors_saved
        beq @done
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
        lda #<BASIC_EVAL
        sta $030A
        lda #>BASIC_EVAL
        sta $030B
@done:
        rts

rb_execute:
        jsr rb_peek_next_nonspace
        jsr rb_fold_a
        cmp #'J'
        beq @maybe_jump
        cmp #'L'
        beq @maybe_label
        cmp #'P'
        beq @maybe_proc
        cmp #'F'
        beq @maybe_func
        cmp #'E'
        beq @maybe_e
        cmp #'R'
        beq @maybe_repeat
        cmp #'U'
        beq @maybe_until
        cmp #TOKEN_END
        beq @maybe_endp
        jmp rb_maybe_bare_command
@maybe_jump:
        jsr rb_match_jump
        bcc rb_maybe_bare_command
        jmp rb_go_statement
@maybe_label:
        jsr rb_match_label
        bcc rb_maybe_bare_command
        jmp rb_label_statement
@maybe_proc:
        jsr rb_match_proc
        bcc rb_call_orig_execute
        jmp BASIC_SYNERR
@maybe_func:
        jsr rb_match_func
        bcc rb_maybe_bare_command
        jmp BASIC_SYNERR
@maybe_e:
        jsr rb_match_exec
        bcc :+
        jmp rb_exec_statement
:       jsr rb_match_endp
        bcc :+
        jmp rb_endp_statement
:
        jsr rb_match_exit
        bcc rb_maybe_bare_command
        jmp cmd_exit
@maybe_repeat:
        jsr rb_match_repeat
        bcc rb_maybe_bare_command
        jmp rb_repeat_statement
@maybe_until:
        jsr rb_match_until
        bcc rb_maybe_bare_command
        jmp rb_until_statement
@maybe_endp:
        jsr rb_match_endp
        bcc rb_call_orig_execute
        jmp rb_endp_statement

rb_call_orig_execute:
        jmp (rb_orig_execute_lo)

rb_maybe_bare_command:
        lda rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        sta TXTPTR+1
        jsr rb_parse_command_name
        bcc @fallback
        jsr CHRGOT
        cmp #'('
        bne @fallback
        jsr rb_lookup_command
        bcc @fallback
        jsr CHRGET
        jsr rb_plugin_statement_found
        jsr rb_expr_expect_close
        jmp BASIC_NEXT_STMT
@fallback:
        lda rb_peek_lo
        bne :+
        dec rb_peek_hi
:
        dec rb_peek_lo
        lda rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        sta TXTPTR+1
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

rb_match_exit:
        lda rb_peek_lo
        sta rb_ptr_lo
        lda rb_peek_hi
        sta rb_ptr_hi
        ldy #1
        lda (rb_ptr_lo),y
        cmp #'X'
        beq :+
        cmp #'x'
        bne @no
:       iny
        lda (rb_ptr_lo),y
        cmp #'I'
        beq :+
        cmp #'i'
        bne @no
:       iny
        lda (rb_ptr_lo),y
        cmp #'T'
        beq :+
        cmp #'t'
        bne @no
:       tya
        clc
        adc rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        adc #0
        sta TXTPTR+1
        sec
        rts
@no:
        clc
        rts

rb_match_proc:
        ldx #<rb_kw_proc
        ldy #>rb_kw_proc
        jmp rb_match_keyword_xy

rb_match_func:
        ldx #<rb_kw_func
        ldy #>rb_kw_func
        jmp rb_match_keyword_xy

rb_match_exec:
        ldx #<rb_kw_exec
        ldy #>rb_kw_exec
        jmp rb_match_keyword_xy

rb_match_ret:
        ldx #<rb_kw_ret
        ldy #>rb_kw_ret
        jmp rb_match_keyword_xy

rb_match_repeat:
        ldx #<rb_kw_repeat
        ldy #>rb_kw_repeat
        jmp rb_match_keyword_xy

rb_match_until:
        ldx #<rb_kw_until
        ldy #>rb_kw_until
        jmp rb_match_keyword_xy

rb_match_label:
        ldx #<rb_kw_label
        ldy #>rb_kw_label
        jmp rb_match_keyword_xy

rb_match_jump:
        ldx #<rb_kw_jump
        ldy #>rb_kw_jump
        jmp rb_match_keyword_xy

rb_match_endp:
        lda rb_peek_lo
        sta rb_ptr_lo
        lda rb_peek_hi
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        cmp #TOKEN_END
        bne @ascii
        iny
        lda (rb_ptr_lo),y
        jsr rb_fold_a
        cmp #'P'
        bne @no
        iny
        lda (rb_ptr_lo),y
        jsr rb_is_name_char
        bcs @no
        clc
        lda rb_peek_lo
        adc #1
        sta TXTPTR
        lda rb_peek_hi
        adc #0
        sta TXTPTR+1
        sec
        rts
@ascii:
        ldx #<rb_kw_endp
        ldy #>rb_kw_endp
        jmp rb_match_keyword_xy
@no:
        clc
        rts

rb_match_keyword_xy:
        stx rb_ptr2_lo
        sty rb_ptr2_hi
rb_match_keyword:
        lda rb_peek_lo
        sta rb_ptr_lo
        lda rb_peek_hi
        sta rb_ptr_hi
        ldy #0
@loop:
        lda (rb_ptr2_lo),y
        beq @boundary
        sta rb_kw_char
        lda (rb_ptr_lo),y
        jsr rb_fold_a
        cmp rb_kw_char
        bne @no
        iny
        bne @loop
@boundary:
        lda (rb_ptr_lo),y
        jsr rb_is_name_char
        bcs @no
        tya
        sec
        sbc #1
        clc
        adc rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        adc #0
        sta TXTPTR+1
        sec
        rts
@no:
        clc
        rts

rb_fold_a:
        cmp #'a'
        bcc @done
        cmp #'z' + 1
        bcs @done
        sec
        sbc #$20
@done:
        rts

rb_is_name_char:
        cmp #'A'
        bcc @digit
        cmp #'Z' + 1
        bcc @yes
@digit:
        cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcs @no
@yes:
        sec
        rts
@no:
        clc
        rts

cmd_exit:
        lda TXTPTR+1
        cmp #>BASIC_START
        bcs @running
        lda #RB_RESUME_READY
        sta RUNTIME_MODE
        lda #RB_MAGIC_READY
        bne @store
@running:
        lda #RB_RESUME_RUN
        sta RUNTIME_MODE
        lda #RB_MAGIC_RUN
@store:
        sta rb_magic
        sta rb_entry_magic
        lda #RB_MAGIC2
        sta rb_magic2
        sta rb_entry_magic2
        jsr call_hidden_save_state
        jsr restore_vectors
        jmp SHIM_RETURN

call_hidden_save_state:
        php
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jsr save_basic_runtime_state
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

call_hidden_seed_plugin_reu:
        php
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jsr rb_seed_plugin_reu_hidden
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

restore_basic_runtime_state:
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jmp hidden_restore_basic_runtime_state

restore_basic_runtime_state_fallback:
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda #$37
        sta CPU_PORT
        jsr force_basic_workspace_pointers
        cli
        jmp BASIC_READY

restore_basic_finish_ready:
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda #$37
        sta CPU_PORT
        ldx RUNTIME_SP
        txs
        cli
        jmp BASIC_READY

restore_basic_finish_run:
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda #$37
        sta CPU_PORT
        ldx RUNTIME_SP
        txs
        cli
        jmp BASIC_NEXT_STMT

init_basic_workspace:
        jsr force_basic_workspace_pointers
        lda #0
        sta BASIC_SENTINEL
        sta BASIC_START
        sta BASIC_START+1
        rts

force_basic_workspace_pointers:
        jsr set_basic_memory_bounds
        lda #<BASIC_START
        sta TXTTAB
        lda #>BASIC_START
        sta TXTTAB+1
        lda #<(BASIC_START + 2)
        sta VARTAB
        sta ARYTAB
        sta STREND
        lda #>(BASIC_START + 2)
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

set_basic_memory_bounds:
        lda #<BASIC_LIMIT
        sta KERNAL_MEMTOP
        lda #>BASIC_LIMIT
        sta KERNAL_MEMTOP+1
        lda #<BASIC_SENTINEL
        sta KERNAL_MEMBOT
        lda #>BASIC_SENTINEL
        sta KERNAL_MEMBOT+1
        rts

prepare_basic_console:
        lda #0
        sta KEYD_COUNT
        lda #VIC_MEM_LOWERCASE
        sta VIC_MEM
        jsr K_CLRCHN
        lda #147
        jsr K_CHROUT
        lda #1
        sta COLOR_CODE
        rts

position_basic_prompt:
        clc
        ldx #3
        ldy #0
        jsr K_PLOT
        lda #0
        sta KEYD_COUNT
        rts

rb_print_z:
        ldy #0
@loop:
        lda (rb_ptr_lo),y
        beq @done
        jsr K_CHROUT
        iny
        bne @loop
@done:
        rts

; ---------------------------------------------------------------------------
; Native PROC/FUNC dispatch.
; ---------------------------------------------------------------------------

RB_ROUT_PROC    = 1
RB_ROUT_FUNC    = 2
RB_PROC_DEPTH   = 4
RB_LOOP_DEPTH   = 4

rb_repeat_statement:
        jsr CHRGET
        lda rb_loop_depth
        cmp #RB_LOOP_DEPTH
        bcc :+
        lda #$23
        jmp rb_runtime_error
:       tax
        lda TXTPTR
        sta rb_loop_txt_lo,x
        lda TXTPTR+1
        sta rb_loop_txt_hi,x
        lda CURLIN
        sta rb_loop_cur_lo,x
        lda CURLIN+1
        sta rb_loop_cur_hi,x
        inc rb_loop_depth
        jmp BASIC_NEXT_STMT

rb_until_statement:
        jsr CHRGET
        lda rb_loop_depth
        bne :+
        lda #$24
        jmp rb_runtime_error
:       jsr rb_skip_spaces
        jsr BASIC_FRMNUM
        lda FAC_EXP
        beq @again
        dec rb_loop_depth
        jmp BASIC_NEXT_STMT
@again:
        ldx rb_loop_depth
        dex
        lda rb_loop_txt_lo,x
        sta TXTPTR
        lda rb_loop_txt_hi,x
        sta TXTPTR+1
        lda rb_loop_cur_lo,x
        sta CURLIN
        lda rb_loop_cur_hi,x
        sta CURLIN+1
        jmp BASIC_NEXT_STMT

rb_label_statement:
        jsr CHRGET
        jsr rb_parse_command_name
        bcs :+
        jmp BASIC_SYNERR
:       jmp BASIC_NEXT_STMT

rb_go_statement:
        jsr CHRGET
        jsr rb_parse_command_name
        bcs :+
        jmp BASIC_SYNERR
:       jsr rb_find_label
        bcs :+
        lda #$27
        jmp rb_runtime_error
:       jmp BASIC_NEXT_STMT

rb_exec_statement:
        jsr CHRGET
        jsr rb_parse_exec_name
        bcs :+
        jmp BASIC_SYNERR
:       lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        jsr rb_find_routine
        bcs :+
        lda #$20
        jmp rb_runtime_error
:       lda #0
        sta CF_PARAM_COUNT
        sta rb_bind_expr_mode
        lda rb_found_kind
        cmp #RB_ROUT_PROC
        beq :+
        jmp BASIC_SYNERR
:
        jsr rb_bind_exec_args
        bcs :+
        jmp BASIC_SYNERR
:       lda rb_proc_depth
        cmp #RB_PROC_DEPTH
        bcc :+
        lda #$21
        jmp rb_runtime_error
:       tax
        lda TXTPTR
        sta rb_proc_ret_lo,x
        lda TXTPTR+1
        sta rb_proc_ret_hi,x
        lda CURLIN
        sta rb_proc_cur_lo,x
        lda CURLIN+1
        sta rb_proc_cur_hi,x
        inc rb_proc_depth
        lda rb_found_line_lo
        sta CURLIN
        lda rb_found_line_hi
        sta CURLIN+1
        lda rb_form_lo
        sta TXTPTR
        lda rb_form_hi
        sta TXTPTR+1
        jmp BASIC_NEXT_STMT

rb_endp_statement:
        lda rb_proc_depth
        bne :+
        lda #$22
        jmp rb_runtime_error
:       dec rb_proc_depth
        ldx rb_proc_depth
        jmp rb_proc_restore

rb_proc_restore:
        lda rb_proc_ret_lo,x
        sta TXTPTR
        lda rb_proc_ret_hi,x
        sta TXTPTR+1
        lda rb_proc_cur_lo,x
        sta CURLIN
        lda rb_proc_cur_hi,x
        sta CURLIN+1
        jmp BASIC_NEXT_STMT

rb_inc_stmt:
        inc rb_stmt_lo
        bne :+
        inc rb_stmt_hi
:       rts

rb_stmt_chr:
        lda rb_stmt_lo
        sta rb_ptr_lo
        lda rb_stmt_hi
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        rts

rb_parse_exec_name:
        jsr rb_skip_spaces
        ldx #0
@loop:
        jsr rb_raw_chrgot
        jsr rb_fold_a
        jsr rb_is_name_char
        bcc @done
        cpx #RB_MAX_NAME
        bcs @bad
        sta RB_CMDBUF,x
        inx
        jsr rb_raw_chrget
        jmp @loop
@done:
        stx rb_cmd_len
        beq @bad
        sec
        rts
@bad:
        clc
        rts

rb_find_routine:
        lda #<BASIC_START
        sta rb_scan_line_lo
        lda #>BASIC_START
        sta rb_scan_line_hi
@line:
        lda rb_scan_line_lo
        sta rb_ptr_lo
        lda rb_scan_line_hi
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_next_line_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_next_line_hi
        ora rb_next_line_lo
        bne :+
        jmp @miss
:
        ldy #2
        lda (rb_ptr_lo),y
        sta rb_found_line_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_found_line_hi
        clc
        lda rb_scan_line_lo
        adc #4
        sta rb_stmt_lo
        lda rb_scan_line_hi
        adc #0
        sta rb_stmt_hi
@stmt:
        jsr rb_skip_stmt_spaces
        jsr rb_stmt_chr
        beq @next
        cmp #':'
        bne :+
        jsr rb_inc_stmt
        jmp @stmt
:       cmp #TOKEN_REM
        beq @next
        lda rb_stmt_lo
        sta rb_peek_lo
        lda rb_stmt_hi
        sta rb_peek_hi
        jsr rb_match_proc
        bcc @try_func
        lda #RB_ROUT_PROC
        bne @kw
@try_func:
        lda rb_stmt_lo
        sta rb_peek_lo
        lda rb_stmt_hi
        sta rb_peek_hi
        jsr rb_match_func
        bcc @skip_stmt
        lda #RB_ROUT_FUNC
@kw:
        sta rb_found_kind
        jsr CHRGET
        jsr rb_skip_spaces
        jsr rb_compare_found_name
        bcs @found
@skip_stmt:
        jsr rb_skip_to_stmt_end
        jmp @stmt
@next:
        lda rb_next_line_lo
        sta rb_scan_line_lo
        lda rb_next_line_hi
        sta rb_scan_line_hi
        jmp @line
@found:
        lda TXTPTR
        sta rb_def_lo
        lda TXTPTR+1
        sta rb_def_hi
        sec
        rts
@miss:
        clc
        rts

rb_find_label:
        lda #<BASIC_START
        sta rb_scan_line_lo
        lda #>BASIC_START
        sta rb_scan_line_hi
@line:
        lda rb_scan_line_lo
        sta rb_ptr_lo
        lda rb_scan_line_hi
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_next_line_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_next_line_hi
        ora rb_next_line_lo
        beq @miss
        clc
        lda rb_scan_line_lo
        adc #4
        sta rb_stmt_lo
        lda rb_scan_line_hi
        adc #0
        sta rb_stmt_hi
        jsr rb_skip_stmt_spaces
        lda rb_stmt_lo
        sta rb_peek_lo
        lda rb_stmt_hi
        sta rb_peek_hi
        jsr rb_match_label
        bcc @next
        jsr CHRGET
        jsr rb_skip_spaces
        jsr rb_compare_found_name
        bcs @found
@next:
        lda rb_next_line_lo
        sta rb_scan_line_lo
        lda rb_next_line_hi
        sta rb_scan_line_hi
        jmp @line
@found:
        ldy #2
        lda (rb_ptr_lo),y
        sta CURLIN
        iny
        lda (rb_ptr_lo),y
        sta CURLIN+1
        sec
        rts
@miss:
        clc
        rts

rb_skip_stmt_spaces:
        ldy #0
@loop:
        jsr rb_stmt_chr
        cmp #' '
        bne @done
        jsr rb_inc_stmt
        jmp @loop
@done:
        rts

rb_skip_to_stmt_end:
        ldy #0
@loop:
        jsr rb_stmt_chr
        beq @done
        cmp #':'
        beq @done
        cmp #TOKEN_REM
        beq @line_done
        jsr rb_inc_stmt
        jmp @loop
@line_done:
        lda #0
@done:
        rts

rb_compare_found_name:
        ldy #0
@loop:
        cpy rb_cmd_len
        beq @boundary
        lda (TXTPTR),y
        jsr rb_fold_a
        cmp RB_CMDBUF,y
        bne @no
        iny
        jmp @loop
@boundary:
        lda (TXTPTR),y
        jsr rb_fold_a
        jsr rb_is_name_char
        bcs @no
        tya
        clc
        adc TXTPTR
        sta TXTPTR
        bcc :+
        inc TXTPTR+1
:       sec
        rts
@no:
        clc
        rts

rb_bind_exec_args:
        lda rb_def_lo
        sta rb_form_lo
        lda rb_def_hi
        sta rb_form_hi
@loop:
        jsr rb_next_formal
        bcs @formal
        jsr rb_actual_at_end
        rts
@formal:
        lda TXTPTR
        sta rb_form_lo
        lda TXTPTR+1
        sta rb_form_hi
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VARPNT
        sta rb_formal_lo
        lda VARPNT+1
        sta rb_formal_hi
        lda TXTPTR
        sta rb_form_next_lo
        lda TXTPTR+1
        sta rb_form_next_hi
        lda VALTYP
        cmp #$FF
        bne :+
        jmp @string
:
        lda INTFLG
        cmp #$80
        beq @int
        jmp @float
@int:
@int_input:
        lda #RB_OUT_INT
        jsr rb_save_formal_value
        jsr rb_exec_next_actual
        bcs :+
        rts
:       jsr rb_start_numeric_actual
        lda rb_bind_expr_mode
        pha
        lda rb_formal_lo
        pha
        lda rb_formal_hi
        pha
        lda rb_form_next_lo
        pha
        lda rb_form_next_hi
        pha
        lda CF_PARAM_COUNT
        pha
        jsr BASIC_FRMNUM
        jsr BASIC_GETADR
        pla
        sta CF_PARAM_COUNT
        pla
        sta rb_form_next_hi
        pla
        sta rb_form_next_lo
        pla
        sta rb_formal_hi
        pla
        sta rb_formal_lo
        pla
        sta rb_bind_expr_mode
        jsr rb_finish_numeric_actual
@got_int:
        lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        ldy #0
        lda rb_formal_lo
        sta rb_ptr_lo
        lda rb_formal_hi
        sta rb_ptr_hi
        lda LINNUM+1
        sta (rb_ptr_lo),y
        iny
        lda LINNUM
        sta (rb_ptr_lo),y
        inc CF_PARAM_COUNT
        jmp @advance_form
@float:
        lda #RB_OUT_FLOAT
        jsr rb_save_formal_value
        jsr rb_exec_next_actual
        bcs :+
        rts
:       jsr rb_start_numeric_actual
        lda rb_bind_expr_mode
        pha
        lda rb_formal_lo
        pha
        lda rb_formal_hi
        pha
        lda rb_form_next_lo
        pha
        lda rb_form_next_hi
        pha
        lda CF_PARAM_COUNT
        pha
        jsr BASIC_FRMNUM
        pla
        sta CF_PARAM_COUNT
        pla
        sta rb_form_next_hi
        pla
        sta rb_form_next_lo
        pla
        sta rb_formal_hi
        pla
        sta rb_formal_lo
        pla
        sta rb_bind_expr_mode
        jsr rb_finish_numeric_actual
        ldx rb_formal_lo
        ldy rb_formal_hi
        jsr BASIC_MOVMF
        lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        inc CF_PARAM_COUNT
        jmp @advance_form
@string:
@string_input:
        lda #RB_OUT_STRING
        jsr rb_save_formal_value
        jsr rb_exec_next_actual
        bcs :+
        rts
:       lda rb_bind_expr_mode
        pha
        lda rb_formal_lo
        pha
        lda rb_formal_hi
        pha
        lda rb_form_next_lo
        pha
        lda rb_form_next_hi
        pha
        lda CF_PARAM_COUNT
        pha
        jsr rb_parse_string_value_current
        pla
        sta CF_PARAM_COUNT
        pla
        sta rb_form_next_hi
        pla
        sta rb_form_next_lo
        pla
        sta rb_formal_hi
        pla
        sta rb_formal_lo
        pla
        sta rb_bind_expr_mode
        lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        jsr rb_stage_cf_string_result
        lda rb_formal_lo
        sta rb_out_ptr_lo
        lda rb_formal_hi
        sta rb_out_ptr_hi
        lda #RB_OUT_STRING
        sta rb_out_type
        lda #1
        sta rb_out_count
        jsr rb_commit_result
        inc CF_PARAM_COUNT
@advance_form:
        lda rb_form_next_lo
        sta rb_form_lo
        lda rb_form_next_hi
        sta rb_form_hi
        jmp @loop

rb_stage_cf_string_result:
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
        sta RF_STR_BUF,y
        iny
        jmp @loop
@done:
        rts

rb_next_formal:
        lda rb_form_lo
        sta TXTPTR
        lda rb_form_hi
        sta TXTPTR+1
        jsr rb_skip_spaces
        cmp #'('
        bne :+
        jsr CHRGET
        jsr rb_skip_spaces
:       cmp #')'
        bne :+
        jsr CHRGET
        lda TXTPTR
        sta rb_form_lo
        lda TXTPTR+1
        sta rb_form_hi
        jmp @no
:
        cmp #','
        bne :+
        jsr CHRGET
        jsr rb_skip_spaces
:       cmp #0
        beq @no
        cmp #':'
        beq @no
        sec
        rts
@no:
        clc
        rts

rb_exec_next_actual:
        lda rb_actual_lo
        sta TXTPTR
        lda rb_actual_hi
        sta TXTPTR+1
        jsr rb_skip_spaces
        ldx CF_PARAM_COUNT
        bne @comma
        cmp #'('
        beq @take
@comma:
        cmp #','
        beq :+
        clc
        rts
:
@take:  jsr CHRGET
        jsr rb_skip_spaces
        jsr rb_mark_wrapped_actual
        lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        sec
        rts

rb_actual_at_end:
        lda rb_actual_lo
        sta TXTPTR
        lda rb_actual_hi
        sta TXTPTR+1
        jsr rb_skip_spaces
        cmp #')'
        bne :+
        jsr CHRGET
        jsr rb_skip_spaces
        lda rb_bind_expr_mode
        bne @ok
:
        lda rb_bind_expr_mode
        bne @bad
        cmp #0
        beq @ok
        cmp #':'
        beq @ok
@bad:
        clc
        rts
@ok:
        sec
        rts

; ---------------------------------------------------------------------------
; Command parsing and dispatch.
; ---------------------------------------------------------------------------

rb_plugin_statement_found:
        lda RB_DESC_BUF
        sta CF_CMD_ID
        lda #0
        sta CF_PARAM_COUNT
        sta rb_command_precomputed
        jsr rb_clear_result_frame
        jsr rb_parse_by_signature
        lda rb_command_precomputed
        bne @commit
        jsr rb_stash_call_frame
        jsr rb_load_and_call_command
        jsr rb_stash_result_frame
@commit:
        jsr rb_commit_result
        rts

rb_parse_command_name:
        jsr rb_skip_spaces
        ldx #0
@loop:
        jsr rb_raw_chrgot
        cmp #$A5
        bne @not_fn_token
        cpx #RB_MAX_NAME - 1
        bcc :+
        jmp @too_long
:       lda #'F'
        sta RB_CMDBUF,x
        inx
        lda #'N'
        sta RB_CMDBUF,x
        inx
        jsr rb_raw_chrget
        jmp @loop
@not_fn_token:
        cmp #$B8
        bne @not_fre_token
        cpx #RB_MAX_NAME - 2
        bcc :+
        jmp @too_long
:
        lda #'F'
        sta RB_CMDBUF,x
        inx
        lda #'R'
        sta RB_CMDBUF,x
        inx
        lda #'E'
        sta RB_CMDBUF,x
        inx
        jsr rb_raw_chrget
        jmp @loop
@not_fre_token:
        cmp #$FF
        bne @not_pi_token
        cpx #RB_MAX_NAME - 1
        bcc :+
        jmp @too_long
:
        lda #'P'
        sta RB_CMDBUF,x
        inx
        lda #'I'
        sta RB_CMDBUF,x
        inx
        jsr rb_raw_chrget
        jmp @loop
@not_pi_token:
        cmp #$C1
        bcc @not_shifted_upper
        cmp #$DB
        bcs @not_shifted_upper
        sec
        sbc #$80
        jmp @folded_case
@not_shifted_upper:
        cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        sec
        sbc #$20
@folded_case:
:       cmp #'A'
        bcc @maybe_digit
        cmp #'Z' + 1
        bcc @store
@maybe_digit:
        cmp #'0'
        bcc @done
        cmp #'9' + 1
        bcs @done
@store:
        cpx #RB_MAX_NAME
        bcs @too_long
        sta RB_CMDBUF,x
        inx
        jsr rb_raw_chrget
        jmp @loop
@done:
        stx rb_cmd_len
        beq @bad
        jsr rb_raw_chrgot
        cmp #','
        beq @bad
        jsr rb_skip_spaces
        sec
        rts
@too_long:
@bad:
        clc
        rts

rb_raw_chrgot:
        ldy #0
        lda (TXTPTR),y
        rts

rb_raw_chrget:
        inc TXTPTR
        bne @done
        inc TXTPTR+1
@done:
        rts

rb_skip_spaces:
@loop:
        ldy #0
        jsr CHRGOT
        cmp #' '
        bne @done
        jsr CHRGET
        jmp @loop
@done:
        ldy #0
        rts

rb_parse_arg_sep:
        lda CF_PARAM_COUNT
        beq @first
        jsr BASIC_CHKCOM
        jmp rb_mark_wrapped_actual
@first:
        jsr rb_skip_spaces
        jmp rb_mark_wrapped_actual

rb_mark_wrapped_actual:
        lda #0
        sta rb_actual_wrapped
        jsr rb_skip_spaces
        cmp #'('
        bne :+
        inc rb_actual_wrapped
:       rts

rb_finish_numeric_actual:
        lda rb_actual_wrapped
        beq @done
        jsr rb_skip_spaces
        cmp #')'
        beq :+
        jmp BASIC_SYNERR
:       jsr CHRGET
@done:
        rts

rb_start_numeric_actual:
        lda rb_actual_wrapped
        beq @done
        jsr CHRGET
        jsr rb_skip_spaces
@done:
        rts

rb_lookup_command:
        lda #<RB_REU_DESC_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_DESC_OFF
        sta rb_reu_off_hi
        lda #0
        sta rb_lookup_index
@page:
        lda rb_lookup_index
        cmp #RB_CMD_DESC_COUNT
        bcc :+
        jmp @miss
:       lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        lda #<RB_PAGEBUF
        sta rb_ptr_lo
        lda #>RB_PAGEBUF
        sta rb_ptr_hi
        lda #RB_CMD_DESC_PER_PAGE
        sta rb_lookup_slots
@slot:
        lda rb_lookup_index
        cmp #RB_CMD_DESC_COUNT
        bcc :+
        jmp @miss
:       ldy #15
        lda (rb_ptr_lo),y
        cmp rb_cmd_len
        bne @next
        ldy #0
@cmp:
        cpy rb_cmd_len
        beq @match
        tya
        pha
        clc
        adc #16
        tay
        lda (rb_ptr_lo),y
        sta rb_lookup_char
        pla
        tay
        lda rb_lookup_char
        cmp RB_CMDBUF,y
        bne @next
        iny
        jmp @cmp
@match:
        ldy #0
@copy:
        lda (rb_ptr_lo),y
        sta RB_DESC_BUF,y
        iny
        cpy #RB_CMD_DESC_SIZE
        bcc @copy
        sec
        rts
@next:
        clc
        lda rb_ptr_lo
        adc #RB_CMD_DESC_SIZE
        sta rb_ptr_lo
        bcc :+
        inc rb_ptr_hi
:       inc rb_lookup_index
        dec rb_lookup_slots
        bne @slot
        inc rb_reu_off_hi
        jmp @page
@miss:
        clc
        rts

rb_parse_by_signature:
        lda RB_DESC_BUF+14
        cmp #SIG_ZECHO1
        beq parse_sig_zecho1
        cmp #SIG_ZADD16
        beq parse_sig_zadd16
        cmp #SIG_UPPER
        beq parse_sig_string_out
        cmp #SIG_LOWER
        beq parse_sig_string_out
        cmp #SIG_ZHIDDENRAM
        beq parse_sig_zhiddenram
        cmp #SIG_ZSUMNUMARRAY
        beq parse_sig_zsumnumarray
        cmp #SIG_ZRANGENUMARRAY
        beq parse_sig_zrangenumarray
        cmp #SIG_BUFNEW
        beq parse_sig_bufnew
        cmp #SIG_BUFFILL
        beq parse_sig_buffill
        cmp #SIG_BUFFREE
        beq parse_sig_buffree
        cmp #SIG_ZTEMPSCRATCH
        beq parse_sig_ztempscratch
        cmp #SIG_ZFAIL
        beq parse_sig_zfail
        cmp #SIG_FREEMEM
        beq parse_sig_freemem
        cmp #SIG_SCRCAP
        beq parse_sig_scrcap
        cmp #SIG_SCRPUT
        beq parse_sig_scrput
        cmp #SIG_FADD
        beq parse_sig_fadd
        cmp #SIG_ERRCODE
        beq parse_sig_errcode
        cmp #SIG_ERRLINE
        beq parse_sig_errline
        jmp BASIC_SYNERR

parse_sig_zecho1:
        jsr rb_parse_out_int_current
        jmp rb_precompute_zecho1

parse_sig_zadd16:
        jsr rb_parse_num0
        jsr rb_parse_num1
        jsr rb_parse_out_int
        rts

parse_sig_string_out:
        jsr rb_parse_string_value
        jsr rb_parse_out_string
        rts

parse_sig_zhiddenram:
        jsr rb_parse_string_value
        jsr rb_parse_out_int
        rts

parse_sig_zsumnumarray:
        jsr rb_parse_int_array_input
        jsr rb_parse_out_int
        jsr rb_resolve_int_array_input_ptr
        rts

parse_sig_zrangenumarray:
        jsr rb_parse_num0
        jsr rb_parse_num1
        lda CF_NUM1_LO
        sta rb_saved_count_lo
        lda CF_NUM1_HI
        sta rb_saved_count_hi
        jsr rb_parse_out_int_array
        rts

parse_sig_bufnew:
        jsr rb_parse_num0
        jsr rb_parse_out_int
        rts

parse_sig_buffill:
        jsr rb_parse_num0
        jsr rb_parse_num1
        rts

parse_sig_buffree:
        jsr rb_parse_num0
        rts

parse_sig_ztempscratch:
        jsr rb_parse_num0
        jsr rb_parse_out_int
        rts

parse_sig_zfail:
        jsr rb_parse_num0
        jsr rb_parse_out_int
        rts

parse_sig_freemem:
        jsr rb_parse_no_args
        rts

parse_sig_scrcap:
        jsr rb_parse_out_int_current
        rts

parse_sig_scrput:
        jsr rb_parse_num0
        rts

parse_sig_fadd:
        jsr rb_parse_float0
        jsr rb_parse_float1
        jsr rb_parse_out_float
        jmp rb_compute_fadd_result

parse_sig_errcode:
        jsr rb_parse_out_int_current
        jmp rb_precompute_errcode

parse_sig_errline:
        jsr rb_parse_out_int_current
        jmp rb_precompute_errline

rb_parse_no_args:
        jsr rb_skip_spaces
        cmp #0
        beq @ok
        cmp #':'
        beq @ok
        cmp #')'
        beq @ok
        jmp BASIC_SYNERR
@ok:
        rts

rb_precompute_zecho1:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        lda #1
        sta rb_command_precomputed
        rts

rb_precompute_errcode:
        lda #0
        sta RF_STATUS
        sta RF_VAL_HI
        lda #RB_VAL_INT
        sta RF_TAG
        lda rb_last_error
        sta RF_VAL_LO
        lda #1
        sta rb_command_precomputed
        rts

rb_precompute_errline:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda rb_last_line_lo
        sta RF_VAL_LO
        lda rb_last_line_hi
        sta RF_VAL_HI
        lda #1
        sta rb_command_precomputed
        rts

rb_parse_num0:
        lda #CF_NUM0_LO-RB_CF
        bne rb_parse_num_to_slot
rb_parse_num1:
        lda #CF_NUM1_LO-RB_CF
        bne rb_parse_num_to_slot
rb_parse_num2:
        lda #CF_NUM2_LO-RB_CF
rb_parse_num_to_slot:
        sta rb_target_off
        jsr rb_parse_arg_sep
        lda rb_target_off
        cmp #CF_NUM0_LO-RB_CF
        beq :+
        jsr rb_save_num0
:
        jsr rb_start_numeric_actual
        lda rb_target_off
        pha
        lda CF_PARAM_COUNT
        pha
        jsr BASIC_FRMNUM
        jsr BASIC_GETADR
        pla
        sta CF_PARAM_COUNT
        pla
        sta rb_target_off
        jsr rb_finish_numeric_actual
        lda rb_target_off
        cmp #CF_NUM0_LO-RB_CF
        beq :+
        jsr rb_restore_num0
:
        ldy rb_target_off
        lda LINNUM
        sta RB_CF,y
        iny
        lda LINNUM+1
        sta RB_CF,y
        inc CF_PARAM_COUNT
        rts

rb_parse_float0:
        lda #CF_FLOAT0-RB_CF
        bne rb_parse_float_to_slot
rb_parse_float1:
        lda #CF_FLOAT1-RB_CF
        bne rb_parse_float_to_slot
rb_parse_float2:
        lda #CF_FLOAT2-RB_CF
rb_parse_float_to_slot:
        sta rb_target_off
        jsr rb_parse_arg_sep
        lda rb_target_off
        cmp #CF_FLOAT0-RB_CF
        beq :+
        jsr rb_save_float0
:       jsr rb_start_numeric_actual
        lda rb_target_off
        pha
        lda CF_PARAM_COUNT
        pha
        jsr BASIC_FRMNUM
        pla
        sta CF_PARAM_COUNT
        pla
        sta rb_target_off
        jsr rb_finish_numeric_actual
        lda rb_target_off
        cmp #CF_FLOAT0-RB_CF
        beq :+
        jsr rb_restore_float0
:       clc
        lda rb_target_off
        adc #<RB_CF
        tax
        lda #>RB_CF
        adc #0
        tay
        jsr BASIC_MOVMF
        inc CF_PARAM_COUNT
        rts

rb_parse_out_int:
        jsr rb_parse_arg_sep
rb_parse_out_int_current:
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        beq :+
        jmp rb_parse_type_error
:       lda INTFLG
        cmp #$80
        beq :+
        jmp rb_parse_type_error
:       lda #RB_OUT_INT
        sta rb_out_type
        lda VARPNT
        sta rb_out_ptr_lo
        lda VARPNT+1
        sta rb_out_ptr_hi
        ldy #0
        lda #0
        sta (VARPNT),y
        iny
        sta (VARPNT),y
        lda #1
        sta rb_out_count
        inc CF_PARAM_COUNT
        rts

rb_parse_out_string:
        jsr rb_parse_arg_sep
rb_parse_out_string_current:
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        cmp #$FF
        beq :+
        jmp rb_parse_type_error
:       lda #RB_OUT_STRING
        sta rb_out_type
        lda VARPNT
        sta rb_out_ptr_lo
        lda VARPNT+1
        sta rb_out_ptr_hi
        ldy #0
        lda #0
        sta (VARPNT),y
        iny
        sta (VARPNT),y
        iny
        sta (VARPNT),y
        lda #1
        sta rb_out_count
        inc CF_PARAM_COUNT
        rts

rb_parse_out_float:
        jsr rb_parse_arg_sep
rb_parse_out_float_current:
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        beq :+
        jmp rb_parse_type_error
:       lda INTFLG
        cmp #$80
        bne :+
        jmp rb_parse_type_error
:       lda #RB_OUT_FLOAT
        sta rb_out_type
        lda VARPNT
        sta rb_out_ptr_lo
        lda VARPNT+1
        sta rb_out_ptr_hi
        lda #1
        sta rb_out_count
        inc CF_PARAM_COUNT
        ldy #0
        lda #0
@clear:
        sta (VARPNT),y
        iny
        cpy #5
        bcc @clear
        rts

rb_parse_out_int_array:
        jsr rb_parse_arg_sep
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        beq :+
        jmp rb_parse_type_error
:       lda INTFLG
        cmp #$80
        beq :+
        jmp rb_parse_type_error
:       lda #RB_OUT_ARRAYI
        sta rb_out_type
        jsr rb_normalize_int_array_ptr_from_varpnt
        lda rb_ptr2_lo
        sta rb_out_ptr_lo
        sta rb_ptr2_lo
        lda rb_ptr2_hi
        sta rb_out_ptr_hi
        sta rb_ptr2_hi
        lda rb_saved_count_lo
        sta rb_out_count_lo
        lda rb_saved_count_hi
        sta rb_out_count_hi
        jsr rb_clear_int_array_output
        lda #1
        sta rb_out_count
        inc CF_PARAM_COUNT
        rts

rb_parse_int_array_input:
        jsr rb_parse_arg_sep
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        beq :+
        jmp rb_parse_type_error
:       lda INTFLG
        cmp #$80
        beq :+
        jmp rb_parse_type_error
:       jsr rb_normalize_int_array_ptr_from_varpnt
        sec
        lda rb_ptr2_lo
        sbc ARYTAB
        sta CF_PTR0_LO
        lda rb_ptr2_hi
        sbc ARYTAB+1
        sta CF_PTR0_HI
        inc CF_PARAM_COUNT
        jsr rb_parse_num2
        lda CF_NUM2_LO
        sta CF_COUNT0_LO
        sta rb_saved_count_lo
        lda CF_NUM2_HI
        sta CF_COUNT0_HI
        sta rb_saved_count_hi
        rts

rb_parse_string_value:
        jsr rb_parse_arg_sep
rb_parse_string_value_current:
        lda CF_PARAM_COUNT
        pha
        jsr BASIC_FRMEVL
        jsr rb_stage_fac_string_to_cf
        jsr BASIC_FRESTR
        pla
        sta CF_PARAM_COUNT
        inc CF_PARAM_COUNT
        rts

rb_parse_quoted_string:
        jsr CHRGET
        ldy #0
@loop:
        jsr CHRGOT
        beq @done
        cmp #$22
        beq @close
        cpy #RB_MAX_STR
        bcs @skip
        sta CF_STR_BUF,y
        iny
@skip:
        jsr CHRGET
        jmp @loop
@close:
        jsr CHRGET
@done:
        sty CF_STR_LEN
        inc CF_PARAM_COUNT
        rts

rb_parse_type_error:
        jmp BASIC_SYNERR

; ---------------------------------------------------------------------------
; Expression-style command calls.
; ---------------------------------------------------------------------------

RB_EXPR_INT     = 1
RB_EXPR_STRING  = 2
RB_EXPR_FLOAT   = 3

rb_eval:
        lda TXTPTR
        sta rb_eval_save_lo
        lda TXTPTR+1
        sta rb_eval_save_hi
        jsr CHRGET
        jsr rb_parse_command_name
        bcs :+
        jmp rb_eval_fallback
:       jsr CHRGOT
        cmp #'('
        beq :+
        jmp rb_eval_fallback
:       jsr rb_lookup_command
        bcs :+
        jsr rb_eval_func
        bcc @not_func
        jmp rb_expr_return_result
@not_func:
        jmp rb_eval_fallback
:       jsr CHRGET
        lda RB_DESC_BUF
        sta CF_CMD_ID
        lda #0
        sta CF_PARAM_COUNT
        sta rb_out_count
        sta rb_command_precomputed
        sta INTFLG
        lda #RB_EXPR_INT
        sta rb_expr_type
        jsr rb_clear_result_frame
        jsr rb_parse_expr_signature
        jsr rb_expr_expect_close
        lda rb_command_precomputed
        bne rb_expr_return_result
        jsr rb_stash_call_frame
        jsr rb_load_and_call_command
        jsr rb_stash_result_frame
        lda RF_STATUS
        bne @error
        jmp rb_expr_return_result
@error:
        lda RF_ERROR
        bne @runtime
        lda RF_STATUS
@runtime:
        jmp rb_runtime_error
rb_expr_return_result:
        lda rb_expr_type
        cmp #RB_EXPR_STRING
        beq rb_expr_return_string
        lda RF_TAG
        cmp #RB_VAL_INT
        beq @int
        cmp #RB_VAL_FLOAT
        beq rb_expr_return_float
        bne rb_expr_bad_type
@int:
        lda RF_VAL_HI
        ldy RF_VAL_LO
        jsr BASIC_GIVAYF
        clc
        rts

rb_expr_return_float:
        lda #0
        sta VALTYP
        sta INTFLG
        lda #<RF_FLOAT
        ldy #>RF_FLOAT
        jsr BASIC_MOVFM
        clc
        rts

rb_expr_return_string:
        lda RF_TAG
        cmp #RB_VAL_STRING
        bne rb_expr_bad_type
        lda RF_STR_LEN
        beq @empty
        jsr rb_alloc_string_heap
        bcs @string_error
        jmp @descriptor
@empty:
        lda #0
        sta rb_ptr_lo
        sta rb_ptr_hi
@descriptor:
        lda #$FF
        sta VALTYP
        lda RF_STR_LEN
        sta FAC_EXP
        lda rb_ptr_lo
        sta FAC_MANT1
        lda rb_ptr_hi
        sta FAC_MANT2
        lda #<FAC_EXP
        sta DSCPTR
        lda #0
        sta DSCPTR_HI
        jsr BASIC_PUTNEW
        clc
        rts
@string_error:
        lda #$02
        jmp rb_runtime_error
rb_expr_bad_type:
        jmp BASIC_SYNERR

rb_eval_func_done:
        clc
        rts

rb_eval_fallback:
        lda rb_eval_save_lo
        sta TXTPTR
        lda rb_eval_save_hi
        sta TXTPTR+1
        jmp BASIC_EVAL

rb_eval_func:
        lda TXTPTR
        sta rb_actual_lo
        lda TXTPTR+1
        sta rb_actual_hi
        jsr rb_find_routine
        bcs :+
        clc
        rts
:       lda rb_found_kind
        cmp #RB_ROUT_FUNC
        beq :+
        clc
        rts
:       lda #0
        sta CF_PARAM_COUNT
        sta rb_exec_out_type
        lda rb_func_depth
        cmp #RB_PROC_DEPTH
        bcc :+
        lda #33
        jmp rb_runtime_error
:       tax
        lda #0
        sta rb_form_save_count,x
        inc rb_func_depth
        lda #1
        sta rb_bind_expr_mode
        lda #1
        sta rb_expr_type
        lda rb_scan_line_lo
        pha
        lda rb_scan_line_hi
        pha
        jsr rb_bind_exec_args
        pla
        sta rb_scan_line_hi
        pla
        sta rb_scan_line_lo
        bcs :+
        jsr rb_restore_func_formals
        jmp BASIC_SYNERR
:       lda TXTPTR
        sta rb_eval_after_lo
        lda TXTPTR+1
        sta rb_eval_after_hi
        jsr rb_expr_run_to_return
        bcs :+
        jsr rb_restore_func_formals
        jmp BASIC_SYNERR
:       lda rb_exec_out_type
        cmp #RB_OUT_STRING
        beq @string
        cmp #RB_OUT_INT
        beq @int
        lda rb_eval_after_lo
        pha
        lda rb_eval_after_hi
        pha
        jsr BASIC_FRMNUM
        pla
        sta rb_eval_after_hi
        pla
        sta rb_eval_after_lo
        ldx #<RF_FLOAT
        ldy #>RF_FLOAT
        jsr BASIC_MOVMF
        lda #0
        sta RF_STATUS
        lda #RB_VAL_FLOAT
        sta RF_TAG
        lda #RB_EXPR_FLOAT
        sta rb_expr_type
        jsr rb_restore_func_formals
        jmp @restore
@int:
        lda rb_eval_after_lo
        pha
        lda rb_eval_after_hi
        pha
        jsr BASIC_FRMNUM
        pla
        sta rb_eval_after_hi
        pla
        sta rb_eval_after_lo
        jsr BASIC_GETADR
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda LINNUM
        sta RF_VAL_LO
        lda LINNUM+1
        sta RF_VAL_HI
        lda #RB_EXPR_INT
        sta rb_expr_type
        jsr rb_restore_func_formals
        jsr @restore
        sec
        rts
@string:
        lda rb_eval_after_lo
        pha
        lda rb_eval_after_hi
        pha
        jsr BASIC_FRMEVL
        jsr rb_stage_fac_string_result
        jsr BASIC_FRESTR
        pla
        sta rb_eval_after_hi
        pla
        sta rb_eval_after_lo
        lda #RB_EXPR_STRING
        sta rb_expr_type
        jsr rb_restore_func_formals
@restore:
        lda rb_eval_after_lo
        sta TXTPTR
        lda rb_eval_after_hi
        sta TXTPTR+1
        sec
        rts

rb_expr_run_to_return:
        jsr rb_expr_next_body_line
        bcs @line
        rts
@next_line:
        jsr rb_expr_next_body_line
        bcs @line
        rts
@line:
        clc
        lda rb_scan_line_lo
        adc #4
        sta rb_stmt_lo
        lda rb_scan_line_hi
        adc #0
        sta rb_stmt_hi
@stmt:
        jsr rb_skip_stmt_spaces
        jsr rb_stmt_chr
        beq @next_line
        cmp #':'
        bne :+
        jsr rb_inc_stmt
        jmp @stmt
:       cmp #TOKEN_REM
        beq @next_line
        lda rb_stmt_lo
        sta rb_peek_lo
        lda rb_stmt_hi
        sta rb_peek_hi
        jsr rb_match_ret
        bcs @ret
        lda rb_stmt_lo
        sta rb_peek_lo
        lda rb_stmt_hi
        sta rb_peek_hi
        jsr rb_match_endp
        bcs @no
        jsr rb_expr_exec_assignment
        bcs @stmt
        clc
        rts
@ret:
        jsr CHRGET
        jsr rb_skip_spaces
        jsr rb_expr_detect_ret_type
        sec
        rts
@no:
        clc
        rts

rb_expr_exec_assignment:
        jsr rb_expr_assignment_shape
        bcs :+
        rts
:       lda rb_stmt_lo
        sta TXTPTR
        lda rb_stmt_hi
        sta TXTPTR+1
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VARPNT
        sta rb_exec_out_lo
        lda VARPNT+1
        sta rb_exec_out_hi
        lda VALTYP
        pha
        lda INTFLG
        pha
        jsr rb_skip_spaces
        cmp #TOKEN_EQUAL
        beq :+
        cmp #'='
        beq :+
        pla
        pla
        clc
        rts
:       jsr CHRGET
        pla
        sta rb_tmp_lo
        pla
        cmp #$FF
        beq @string
        jsr rb_expr_push_state
        jsr BASIC_FRMNUM
        jsr rb_expr_pop_state
        lda rb_tmp_lo
        cmp #$80
        bne @float
        jsr BASIC_GETADR
        lda rb_exec_out_lo
        sta rb_ptr_lo
        lda rb_exec_out_hi
        sta rb_ptr_hi
        ldy #0
        lda LINNUM+1
        sta (rb_ptr_lo),y
        iny
        lda LINNUM
        sta (rb_ptr_lo),y
        jmp @done
@float:
        ldx rb_exec_out_lo
        ldy rb_exec_out_hi
        jsr BASIC_MOVMF
        jmp @done
@string:
        jsr rb_expr_push_state
        jsr BASIC_FRMEVL
        jsr rb_expr_pop_state
        jsr rb_stage_fac_string_result
        jsr BASIC_FRESTR
        lda #RB_OUT_STRING
        sta rb_out_type
        lda rb_exec_out_lo
        sta rb_out_ptr_lo
        lda rb_exec_out_hi
        sta rb_out_ptr_hi
        lda #1
        sta rb_out_count
        jsr rb_commit_result
@done:
        lda TXTPTR
        sta rb_stmt_lo
        lda TXTPTR+1
        sta rb_stmt_hi
        sec
        rts

rb_expr_push_state:
        pla
        sta rb_ptr_lo
        pla
        sta rb_ptr_hi
        lda rb_scan_line_lo
        pha
        lda rb_scan_line_hi
        pha
        lda rb_eval_after_lo
        pha
        lda rb_eval_after_hi
        pha
        lda rb_ptr_hi
        pha
        lda rb_ptr_lo
        pha
        rts

rb_expr_pop_state:
        pla
        sta rb_ptr_lo
        pla
        sta rb_ptr_hi
        pla
        sta rb_eval_after_hi
        pla
        sta rb_eval_after_lo
        pla
        sta rb_scan_line_hi
        pla
        sta rb_scan_line_lo
        lda rb_ptr_hi
        pha
        lda rb_ptr_lo
        pha
        rts

rb_expr_assignment_shape:
        lda rb_stmt_lo
        sta rb_ptr_lo
        lda rb_stmt_hi
        sta rb_ptr_hi
        ldy #0
@spaces:
        lda (rb_ptr_lo),y
        cmp #' '
        bne @first
        iny
        bne @spaces
@first:
        jsr rb_fold_a
        cmp #'A'
        bcc @no
        cmp #'Z' + 1
        bcs @no
        iny
@name:
        lda (rb_ptr_lo),y
        cmp #'%'
        beq @type
        cmp #'$'
        beq @type
        jsr rb_fold_a
        jsr rb_is_name_char
        bcc @after_name
        iny
        bne @name
@type:
        iny
@after_name:
        lda (rb_ptr_lo),y
        cmp #' '
        bne @equal
        iny
        bne @after_name
@equal:
        cmp #TOKEN_EQUAL
        beq @ok
        cmp #'='
        beq @ok
@no:
        clc
        rts
@ok:
        sec
        rts

rb_expr_next_body_line:
        lda rb_scan_line_lo
        sta rb_ptr_lo
        lda rb_scan_line_hi
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_scan_line_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_scan_line_hi
        lda rb_scan_line_lo
        ora rb_scan_line_hi
        bne :+
        clc
        rts
:       sec
        rts

rb_expr_detect_ret_type:
        cmp #'$'
        beq @typed_string
        cmp #'%'
        beq @typed_int
        cmp #$22
        beq @string
        ldy #0
@scan:
        lda (TXTPTR),y
        cmp #'$'
        beq @string
        cmp #'%'
        beq @int
        jsr rb_fold_a
        jsr rb_is_name_char
        bcc @float
        iny
        bne @scan
@typed_string:
        jsr CHRGET
        jsr rb_skip_spaces
@string:
        lda #RB_OUT_STRING
        sta rb_exec_out_type
        rts
@typed_int:
        jsr CHRGET
        jsr rb_skip_spaces
@int:
        lda #RB_OUT_INT
        sta rb_exec_out_type
        rts
@float:
        lda #RB_OUT_FLOAT
        sta rb_exec_out_type
        rts

rb_stage_fac_string_result:
        lda VALTYP
        cmp #$FF
        beq :+
        jmp rb_parse_type_error
:
        lda DSCPTR
        sta rb_ptr2_lo
        lda DSCPTR_HI
        sta rb_ptr2_hi
        ldy #0
        lda (rb_ptr2_lo),y
        cmp #RB_MAX_STR + 1
        bcc :+
        lda #RB_MAX_STR
:       sta RF_STR_LEN
        ldy #1
        lda (rb_ptr2_lo),y
        sta rb_ptr_lo
        iny
        lda (rb_ptr2_lo),y
        sta rb_ptr_hi
        ldy #0
@copy:
        cpy RF_STR_LEN
        beq @ready
        lda (rb_ptr_lo),y
        sta RF_STR_BUF,y
        iny
        jmp @copy
@ready:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_STRING
        sta RF_TAG
        rts

rb_stage_fac_string_to_cf:
        lda VALTYP
        cmp #$FF
        beq :+
        jmp rb_parse_type_error
:       lda DSCPTR
        sta rb_ptr2_lo
        lda DSCPTR_HI
        sta rb_ptr2_hi
        ldy #0
        lda (rb_ptr2_lo),y
        cmp #RB_MAX_STR + 1
        bcc :+
        lda #RB_MAX_STR
:       sta CF_STR_LEN
        ldy #1
        lda (rb_ptr2_lo),y
        sta rb_ptr_lo
        iny
        lda (rb_ptr2_lo),y
        sta rb_ptr_hi
        ldy #0
@copy:
        cpy CF_STR_LEN
        beq @done
        lda (rb_ptr_lo),y
        sta CF_STR_BUF,y
        iny
        jmp @copy
@done:
        rts

rb_save_num0:
        ldx rb_num_save_depth
        cpx #4
        bcc :+
        rts
:       lda CF_NUM0_LO
        sta rb_save_num0_lo,x
        lda CF_NUM0_HI
        sta rb_save_num0_hi,x
        inc rb_num_save_depth
        rts

rb_restore_num0:
        ldx rb_num_save_depth
        bne :+
        rts
:       dex
        stx rb_num_save_depth
        lda rb_save_num0_lo,x
        sta CF_NUM0_LO
        lda rb_save_num0_hi,x
        sta CF_NUM0_HI
        rts

rb_save_float0:
        lda rb_float_save_depth
        cmp #4
        bcc :+
        rts
:       asl
        asl
        clc
        adc rb_float_save_depth
        tay
        ldx #0
@loop:
        lda CF_FLOAT0,x
        sta rb_save_float0_buf,y
        iny
        inx
        cpx #5
        bcc @loop
        inc rb_float_save_depth
        rts

rb_restore_float0:
        lda rb_float_save_depth
        bne :+
        rts
:       sec
        sbc #1
        sta rb_float_save_depth
        asl
        asl
        clc
        adc rb_float_save_depth
        tay
        ldx #0
@loop:
        lda rb_save_float0_buf,y
        sta CF_FLOAT0,x
        iny
        inx
        cpx #5
        bcc @loop
        rts

rb_compute_fadd_result:
        lda #<CF_FLOAT0
        ldy #>CF_FLOAT0
        jsr BASIC_MOVFM
        lda #<CF_FLOAT1
        ldy #>CF_FLOAT1
        jsr BASIC_FADD
        ldx #<RF_FLOAT
        ldy #>RF_FLOAT
        jsr BASIC_MOVMF
        lda #0
        sta RF_STATUS
        lda #RB_VAL_FLOAT
        sta RF_TAG
        lda #1
        sta rb_command_precomputed
        rts

rb_save_formal_value:
        sta rb_save_type_tmp
        lda rb_func_depth
        bne :+
        rts
:       sec
        sbc #1
        sta rb_save_depth_tmp
        asl
        asl
        clc
        adc CF_PARAM_COUNT
        tax
        cpx #16
        bcc :+
        rts
:       lda rb_save_type_tmp
        sta rb_form_save_type,x
        lda rb_formal_lo
        sta rb_form_save_lo,x
        sta rb_ptr_lo
        lda rb_formal_hi
        sta rb_form_save_hi,x
        sta rb_ptr_hi
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_form_save_val0,x
        iny
        lda (rb_ptr_lo),y
        sta rb_form_save_val1,x
        iny
        lda (rb_ptr_lo),y
        sta rb_form_save_val2,x
        iny
        lda (rb_ptr_lo),y
        sta rb_form_save_val3,x
        iny
        lda (rb_ptr_lo),y
        sta rb_form_save_val4,x
        ldy rb_save_depth_tmp
        lda CF_PARAM_COUNT
        clc
        adc #1
        sta rb_form_save_count,y
        rts

rb_restore_func_formals:
        lda rb_func_depth
        bne :+
        rts
:       dec rb_func_depth
        ldy rb_func_depth
        lda rb_form_save_count,y
        beq @done
        sta rb_save_count_tmp
        tya
        asl
        asl
        sta rb_save_idx
@loop:
        ldx rb_save_idx
        lda rb_form_save_lo,x
        sta rb_ptr_lo
        lda rb_form_save_hi,x
        sta rb_ptr_hi
        ldy #0
        lda rb_form_save_val0,x
        sta (rb_ptr_lo),y
        iny
        lda rb_form_save_val1,x
        sta (rb_ptr_lo),y
        lda rb_form_save_type,x
        cmp #RB_OUT_INT
        beq @next
        iny
        lda rb_form_save_val2,x
        sta (rb_ptr_lo),y
        lda rb_form_save_type,x
        cmp #RB_OUT_STRING
        beq @next
        iny
        lda rb_form_save_val3,x
        sta (rb_ptr_lo),y
        iny
        lda rb_form_save_val4,x
        sta (rb_ptr_lo),y
@next:
        inc rb_save_idx
        dec rb_save_count_tmp
        bne @loop
@done:
        rts

rb_parse_expr_signature:
        lda RB_DESC_BUF+14
        cmp #SIG_ZECHO1
        beq parse_expr_zecho1
        cmp #SIG_ZADD16
        beq parse_expr_zadd16
        cmp #SIG_UPPER
        beq parse_expr_string_out
        cmp #SIG_LOWER
        beq parse_expr_string_out
        cmp #SIG_ZHIDDENRAM
        beq parse_expr_int_string
        cmp #SIG_BUFNEW
        beq parse_expr_num0
        cmp #SIG_ZTEMPSCRATCH
        beq parse_expr_num0
        cmp #SIG_SCRCAP
        beq parse_expr_no_args
        cmp #SIG_ZSUMNUMARRAY
        beq parse_expr_zsumnumarray
        cmp #SIG_FADD
        beq parse_expr_fadd
        cmp #SIG_ERRCODE
        beq parse_expr_errcode
        cmp #SIG_ERRLINE
        beq parse_expr_errline
        jmp BASIC_SYNERR

parse_expr_no_args:
        rts

parse_expr_zecho1:
        jmp rb_precompute_zecho1

parse_expr_zadd16:
        jsr rb_parse_num0
        jsr rb_parse_num1
        rts

parse_expr_fadd:
        jsr rb_parse_float0
        jsr rb_parse_float1
        lda #RB_EXPR_FLOAT
        sta rb_expr_type
        jmp rb_compute_fadd_result

parse_expr_errcode:
        jmp rb_precompute_errcode

parse_expr_errline:
        jmp rb_precompute_errline

parse_expr_num0:
        jsr rb_parse_num0
        rts

parse_expr_int_string:
        jsr rb_parse_string_value
        rts

parse_expr_zsumnumarray:
        jsr rb_parse_int_array_input
        jsr rb_resolve_int_array_input_ptr
        rts

parse_expr_string_out:
        jsr rb_parse_string_value
        lda #RB_EXPR_STRING
        sta rb_expr_type
        rts

rb_expr_expect_close:
        jsr rb_skip_spaces
        cmp #')'
        beq :+
        jmp BASIC_SYNERR
:       jmp CHRGET

rb_resolve_int_array_input_ptr:
        clc
        lda CF_PTR0_LO
        adc ARYTAB
        sta CF_PTR0_LO
        lda CF_PTR0_HI
        adc ARYTAB+1
        sta CF_PTR0_HI
        rts

rb_normalize_int_array_ptr_from_varpnt:
        lda VARPNT
        sta rb_ptr2_lo
        lda VARPNT+1
        sta rb_ptr2_hi
        ldy #0
        lda (rb_ptr2_lo),y
        cmp #$C1
        bcc @done
        cmp #$DB
        bcs @done
        iny
        lda (rb_ptr2_lo),y
        cmp #$80
        bne @done
        ldy #4
        lda (rb_ptr2_lo),y
        beq @done
        cmp #11
        bcs @done
        clc
        lda rb_ptr2_lo
        adc #7
        sta rb_ptr2_lo
        lda rb_ptr2_hi
        adc #0
        sta rb_ptr2_hi
@done:
        rts

rb_clear_int_array_output:
        lda rb_out_count_hi
        bne @done
        ldx rb_out_count_lo
        beq @done
@loop:
        ldy #0
        lda #0
        sta (rb_ptr2_lo),y
        iny
        sta (rb_ptr2_lo),y
        clc
        lda rb_ptr2_lo
        adc #2
        sta rb_ptr2_lo
        bcc :+
        inc rb_ptr2_hi
:       dex
        bne @loop
@done:
        rts

; ---------------------------------------------------------------------------
; Overlay loading, result commit, and errors.
; ---------------------------------------------------------------------------

rb_clear_result_frame:
        lda #0
        ldx #0
@loop:
        sta RB_RF,x
        inx
        bne @loop
        lda #RB_OUT_NONE
        sta rb_out_type
        sta rb_out_count
        rts

rb_load_and_call_command:
        lda RB_DESC_BUF+4
        ora RB_DESC_BUF+5
        beq @done
        lda RB_DESC_BUF+2
        sta rb_reu_off_lo
        lda RB_DESC_BUF+3
        sta rb_reu_off_hi
        lda RB_DESC_BUF+4
        sta rb_reu_len_lo
        lda RB_DESC_BUF+5
        sta rb_reu_len_hi
        jsr rb_desc_runtime_base
        clc
        lda rb_ptr_lo
        adc RB_DESC_BUF+10
        sta rb_reu_c64_lo
        lda rb_ptr_hi
        adc RB_DESC_BUF+11
        sta rb_reu_c64_hi
        clc
        lda rb_ptr_lo
        adc RB_DESC_BUF+12
        sta rb_overlay_vec_lo
        lda rb_ptr_hi
        adc RB_DESC_BUF+13
        sta rb_overlay_vec_hi
        lda #RB_REU_CODE_BANK
        sta rb_reu_bank
        jsr rb_fetch_underrom_payload
        jsr rb_mark_slot_resident
        jsr rb_call_underrom_payload
@done:
        rts

rb_desc_runtime_base:
        lda #>RB_SLOT0_BASE
        ldx RB_DESC_BUF+8
        cpx #RB_SLOT_PROOF_1
        bne :+
        lda #>RB_SLOT1_BASE
:       cpx #RB_SLOT_PROOF_2
        bne :+
        lda #>RB_SLOT2_BASE
:       ldx #0
        stx rb_ptr_lo
        sta rb_ptr_hi
        rts

rb_mark_slot_resident:
        lda RB_DESC_BUF+8
        cmp #RB_SLOT_LEGACY_LOW
        bne @done
        lda RB_DESC_BUF+1
        sta rb_slot0_module
        lda RB_DESC_BUF+6
        sta rb_slot0_submodule
        lda RB_DESC_BUF+7
        sta rb_slot0_overlay
        lda RB_DESC_BUF+9
        sta rb_slot0_generation
@done:
        rts

rb_fetch_underrom_payload:
        php
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jsr rb_reu_fetch
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

rb_call_underrom_payload:
        php
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jsr rb_hidden_overlay_jmp
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

rb_hidden_overlay_jmp:
        jmp (rb_overlay_vec_lo)

rb_commit_result:
        lda RF_STATUS
        beq @ok
        lda RF_ERROR
        bne :+
        lda RF_STATUS
:       jmp rb_runtime_error
@ok:
        lda rb_out_count
        beq @done
        lda rb_out_type
        cmp #RB_OUT_INT
        bne :+
        jmp rb_commit_int
:       cmp #RB_OUT_STRING
        bne :+
        jmp rb_commit_string
:       cmp #RB_OUT_ARRAYI
        bne :+
        jmp rb_commit_arrayi
:       cmp #RB_OUT_FLOAT
        bne @done
        jmp rb_commit_float
@done:
        rts

rb_commit_int:
        lda RF_TAG
        cmp #RB_VAL_INT
        bne @done
        lda rb_out_ptr_lo
        sta rb_ptr_lo
        lda rb_out_ptr_hi
        sta rb_ptr_hi
        ldy #0
        lda RF_VAL_HI
        sta (rb_ptr_lo),y
        iny
        lda RF_VAL_LO
        sta (rb_ptr_lo),y
@done:
        rts

rb_commit_float:
        lda RF_TAG
        cmp #RB_VAL_FLOAT
        bne @done
        lda rb_out_ptr_lo
        sta rb_ptr_lo
        lda rb_out_ptr_hi
        sta rb_ptr_hi
        ldy #0
@copy:
        lda RF_FLOAT,y
        sta (rb_ptr_lo),y
        iny
        cpy #5
        bcc @copy
@done:
        rts

rb_commit_string:
        lda RF_TAG
        cmp #RB_VAL_STRING
        bne @done
        lda RF_STR_LEN
        beq @empty
        jsr rb_alloc_string_heap
        bcs rb_commit_string_error
        lda rb_out_ptr_lo
        sta rb_ptr2_lo
        lda rb_out_ptr_hi
        sta rb_ptr2_hi
        ldy #0
        lda RF_STR_LEN
        sta (rb_ptr2_lo),y
        iny
        lda rb_ptr_lo
        sta (rb_ptr2_lo),y
        iny
        lda rb_ptr_hi
        sta (rb_ptr2_lo),y
        rts
@empty:
        lda rb_out_ptr_lo
        sta rb_ptr2_lo
        lda rb_out_ptr_hi
        sta rb_ptr2_hi
        ldy #0
        lda #0
        sta (rb_ptr2_lo),y
        iny
        sta (rb_ptr2_lo),y
        iny
        sta (rb_ptr2_lo),y
@done:
        rts
rb_commit_string_error:
        lda #$02
        jmp rb_runtime_error

rb_alloc_string_heap:
        sec
        lda FRETOP
        sbc RF_STR_LEN
        sta rb_ptr_lo
        lda FRETOP+1
        sbc #0
        sta rb_ptr_hi
        lda rb_ptr_hi
        cmp STREND+1
        bcc @oom
        bne @copy
        lda rb_ptr_lo
        cmp STREND
        bcc @oom
@copy:
        ldy #0
@loop:
        cpy RF_STR_LEN
        beq @done
        lda RF_STR_BUF,y
        sta (rb_ptr_lo),y
        iny
        jmp @loop
@done:
        lda rb_ptr_lo
        sta FRETOP
        lda rb_ptr_hi
        sta FRETOP+1
        clc
        rts
@oom:
        sec
        rts

rb_commit_arrayi:
        lda RF_TAG
        cmp #RB_VAL_ARRAYI
        bne @done
        lda rb_out_ptr_lo
        sta rb_ptr_lo
        lda rb_out_ptr_hi
        sta rb_ptr_hi
        ldx RF_COUNT_LO
        beq @done
        ldy #0
@loop:
        lda RF_ARRAY_BUF,y
        sta (rb_ptr_lo),y
        iny
        lda RF_ARRAY_BUF,y
        sta (rb_ptr_lo),y
        iny
        dex
        beq @done
        jmp @loop
@done:
        rts

rb_runtime_error:
        sta rb_error
        sta rb_last_error
        lda CURLIN+1
        cmp #$FF
        bne @store_line
        lda #0
        sta rb_last_line_lo
        sta rb_last_line_hi
        beq @print
@store_line:
        lda CURLIN
        sta rb_last_line_lo
        lda CURLIN+1
        sta rb_last_line_hi
@print:
        lda #<rb_error_text
        sta rb_ptr_lo
        lda #>rb_error_text
        sta rb_ptr_hi
        jsr rb_print_z
        ldx rb_error
        lda #0
        jsr BASIC_LINPRT
        lda #13
        jsr K_CHROUT
        jmp BASIC_READY

rb_error_text:
        .byte "?RB ERROR ",0

; ---------------------------------------------------------------------------
; REU DMA, registry seed, debug, and handle heap.
; ---------------------------------------------------------------------------

rb_reu_stash:
        lda rb_reu_c64_lo
        sta REU_C64_LO
        lda rb_reu_c64_hi
        sta REU_C64_HI
        lda rb_reu_off_lo
        sta REU_ADDR_LO
        lda rb_reu_off_hi
        sta REU_ADDR_HI
        lda rb_reu_bank
        sta REU_BANK
        lda rb_reu_len_lo
        sta REU_LEN_LO
        lda rb_reu_len_hi
        sta REU_LEN_HI
        lda #$90
        sta REU_CMD
        rts

rb_reu_fetch:
        lda rb_reu_c64_lo
        sta REU_C64_LO
        lda rb_reu_c64_hi
        sta REU_C64_HI
        lda rb_reu_off_lo
        sta REU_ADDR_LO
        lda rb_reu_off_hi
        sta REU_ADDR_HI
        lda rb_reu_bank
        sta REU_BANK
        lda rb_reu_len_lo
        sta REU_LEN_LO
        lda rb_reu_len_hi
        sta REU_LEN_HI
        lda #$91
        sta REU_CMD
        rts

rb_stash_call_frame:
        lda #<RB_CF
        sta rb_reu_c64_lo
        lda #>RB_CF
        sta rb_reu_c64_hi
        lda #<RB_REU_CALL_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_CALL_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #$80
        sta rb_reu_len_lo
        lda #0
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

rb_stash_result_frame:
        lda #<RB_RF
        sta rb_reu_c64_lo
        lda #>RB_RF
        sta rb_reu_c64_hi
        lda #<RB_REU_RESULT_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_RESULT_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #$80
        sta rb_reu_len_lo
        lda #0
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

        .segment "REGSEED"

rb_reu_header:
        .byte "RBPL"
        .byte 1
        .byte RB_CMD_DESC_COUNT
        .byte RB_CMD_DESC_SIZE
        .byte RB_MAX_NAME
        .word RB_REU_DESC_OFF
        .word RB_REU_CALL_OFF
        .word RB_REU_RESULT_OFF
        .word RB_REU_HANDLE_OFF
rb_reu_header_end:

.macro CMD_LOW id, sig, label, endlabel, name
        .byte id, RB_MODULE_SYSTEM
        .word 0
        .word __LOWPACK_SIZE__
        .byte RB_SUBMOD_LEGACY_LOW
        .byte 0
        .byte RB_SLOT_LEGACY_LOW
        .byte 1
        .word 0
        .word label - __LOWPACK_RUN__
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_LOW_ALL id, sig, label, name
        .byte id, RB_MODULE_SYSTEM
        .word 0
        .word __LOWPACK_SIZE__
        .byte RB_SUBMOD_LEGACY_LOW
        .byte 0
        .byte RB_SLOT_LEGACY_LOW
        .byte 1
        .word 0
        .word label - __LOWPACK_RUN__
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_HIDDEN id, sig, label, endlabel, name
        .byte id, RB_MODULE_SYSTEM
        .word 0
        .word __LOWPACK_SIZE__
        .byte RB_SUBMOD_LEGACY_LOW
        .byte 0
        .byte RB_SLOT_LEGACY_LOW
        .byte 1
        .word 0
        .word label - __LOWPACK_RUN__
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_SLOT1 id, sig, label, name
        .byte id, 2
        .word __SLOTPACK1_LOAD__ - __LOWPACK_LOAD__
        .word __SLOTPACK1_SIZE__
        .byte RB_SUBMOD_PROOF_SLOT1
        .byte 0
        .byte RB_SLOT_PROOF_1
        .byte 1
        .word 0
        .word label - __SLOTPACK1_RUN__
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_SLOT2 id, sig, label, name
        .byte id, 2
        .word __SLOTPACK2_LOAD__ - __LOWPACK_LOAD__
        .word __SLOTPACK2_SIZE__
        .byte RB_SUBMOD_PROOF_SLOT2
        .byte 0
        .byte RB_SLOT_PROOF_2
        .byte 1
        .word 0
        .word label - __SLOTPACK2_RUN__
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

rb_command_descriptors:
        CMD_LOW_ALL CMD_ZECHO1, SIG_ZECHO1, cmd_zecho1_low, "ZECHO1"
        CMD_LOW CMD_ZADD16, SIG_ZADD16, cmd_zadd16_low, cmd_zadd16_low_end, "ZADD16"
        CMD_LOW CMD_UPPER, SIG_UPPER, cmd_upper_low, cmd_upper_low_end, "UPPER"
        CMD_LOW CMD_LOWER, SIG_LOWER, cmd_lower_low, cmd_lower_low_end, "LOWER"
        CMD_HIDDEN CMD_ZHIDDENRAM, SIG_ZHIDDENRAM, cmd_zhiddenram_hidden, cmd_zhiddenram_hidden_end, "ZHIDDENRAM"
        CMD_LOW CMD_ZSUMNUMARRAY, SIG_ZSUMNUMARRAY, cmd_zsumnumarray_low, cmd_zsumnumarray_low_end, "ZSUMNUMARRAY"
        CMD_LOW CMD_ZRANGENUMARRAY, SIG_ZRANGENUMARRAY, cmd_zrangenumarray_low, cmd_zrangenumarray_low_end, "ZRANGENUMARRAY"
        CMD_LOW_ALL CMD_BUFNEW, SIG_BUFNEW, cmd_bufnew_low, "BUFNEW"
        CMD_LOW_ALL CMD_BUFFILL, SIG_BUFFILL, cmd_buffill_low, "BUFFILL"
        CMD_LOW_ALL CMD_BUFFREE, SIG_BUFFREE, cmd_buffree_low, "BUFFREE"
        CMD_LOW_ALL CMD_ZTEMPSCRATCH, SIG_ZTEMPSCRATCH, cmd_ztempscratch_low, "ZTEMPSCRATCH"
        CMD_LOW CMD_ZFAIL, SIG_ZFAIL, cmd_zfail_low, cmd_zfail_low_end, "ZFAIL"
        CMD_LOW CMD_FREEMEM, SIG_FREEMEM, cmd_freemem_low, cmd_freemem_low_end, "FREEMEM"
        CMD_LOW_ALL CMD_SCRCAP, SIG_SCRCAP, cmd_scrcap_low, "SCRCAP"
        CMD_LOW CMD_FADD, SIG_FADD, cmd_fadd_low, cmd_fadd_low_end, "FADD"
        CMD_LOW CMD_ZPAUSE, SIG_ZPAUSE, cmd_zpause_low, cmd_zpause_low_end, "ZPAUSE"
        CMD_LOW CMD_ERRCODE, SIG_ERRCODE, cmd_zecho1_low, cmd_zecho1_low_end, "ERRCODE"
        CMD_LOW CMD_ERRLINE, SIG_ERRLINE, cmd_zecho1_low, cmd_zecho1_low_end, "ERRLINE"
        CMD_LOW CMD_ZSLOT0, SIG_SCRCAP, cmd_zslot0_low, cmd_zslot0_low_end, "ZSLOT0"
        CMD_SLOT1 CMD_ZSLOT1, SIG_SCRCAP, cmd_zslot1, "ZSLOT1"
        CMD_SLOT2 CMD_ZSLOT2, SIG_SCRCAP, cmd_zslot2, "ZSLOT2"
        .res (RB_CMD_DESC_COUNT - 22) * RB_CMD_DESC_SIZE, 0
        CMD_LOW_ALL CMD_SCRPUT, SIG_SCRPUT, cmd_scrput_low, "SCRPUT"

; ---------------------------------------------------------------------------
; Hidden helper code, called by visible resident code with BASIC ROM hidden.
; ---------------------------------------------------------------------------

        .segment "HIDDEN"

hidden_restore_basic_runtime_state:
        lda RUNTIME_MAGIC1
        cmp #RB_STATE_MAGIC1
        beq :+
        jmp @fallback
:
        lda RUNTIME_MAGIC2
        cmp #RB_STATE_MAGIC2
        beq :+
        jmp @fallback
:
        lda RUNTIME_LINE_OK
        bne :+
        jmp @fallback
:

        lda #<RUNTIME_STACK_BUF
        sta rb_reu_c64_lo
        lda #>RUNTIME_STACK_BUF
        sta rb_reu_c64_hi
        lda #<RB_REU_RUNTIME_STACK_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_RUNTIME_STACK_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_fetch

        lda #<RUNTIME_ZP_BUF
        sta rb_reu_c64_lo
        lda #>RUNTIME_ZP_BUF
        sta rb_reu_c64_hi
        lda #<RB_REU_RUNTIME_ZP_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_RUNTIME_ZP_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_fetch

        jsr set_basic_memory_bounds
        lda #0
        sta KEYD_COUNT
        lda RUNTIME_MODE
        cmp #RB_RESUME_RUN
        beq @copy_runtime
        jsr prepare_basic_console
        jsr rb_draw_header
        jsr position_basic_prompt

@copy_runtime:
        ldx #0
@stack:
        lda RUNTIME_STACK_BUF,x
        sta $0100,x
        inx
        bne @stack
        ldx #2
@zp:
        lda RUNTIME_ZP_BUF,x
        sta $0000,x
        inx
        bne @zp
        lda RUNTIME_MODE
        cmp #RB_RESUME_RUN
        beq @running_resume
        jmp restore_basic_finish_ready
@running_resume:
        jmp restore_basic_finish_run
@fallback:
        jmp restore_basic_runtime_state_fallback

draw_default_header:
        lda #6
        sta VIC_BG
        sta VIC_BORDER
        jsr clear_default_screen
        jsr draw_box_top_row
        jsr draw_box_middle_row
        jsr draw_box_bottom_row
        ldx #0
@title:
        lda default_title_screen,x
        beq @free_label
        sta SCREEN+15,x
        lda #7
        sta COLOR_RAM+15,x
        inx
        bne @title
@free_label:
        ldx #0
@free_label_loop:
        lda default_free_label_screen,x
        beq @free_value
        sta SCREEN+42,x
        lda #15
        sta COLOR_RAM+42,x
        inx
        bne @free_label_loop
@free_value:
        ldx #0
        lda #32
@free_value_loop:
        sta SCREEN+48,x
        lda #13
        sta COLOR_RAM+48,x
        inx
        cpx #5
        bcc @free_value_loop
        ldx #0
@free_suffix_loop:
        lda default_free_suffix_screen,x
        beq @done
        sta SCREEN+53,x
        lda #15
        sta COLOR_RAM+53,x
        inx
        bne @free_suffix_loop
@done:
        rts

clear_default_screen:
        ldx #0
        lda #32
@screen_full:
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        inx
        bne @screen_full
        ldx #$E7
@screen_tail:
        sta SCREEN+$300,x
        dex
        bpl @screen_tail
        ldx #0
        lda #1
@color_full:
        sta COLOR_RAM,x
        sta COLOR_RAM+$100,x
        sta COLOR_RAM+$200,x
        inx
        bne @color_full
        ldx #$E7
@color_tail:
        sta COLOR_RAM+$300,x
        dex
        bpl @color_tail
        rts

draw_box_top_row:
        ldx #39
        lda #$40
@loop:
        sta SCREEN,x
        lda #14
        sta COLOR_RAM,x
        lda #$40
        dex
        bpl @loop
        lda #$70
        sta SCREEN
        lda #$6E
        sta SCREEN+39
        rts

draw_box_middle_row:
        ldx #39
        lda #32
@loop:
        sta SCREEN+40,x
        lda #1
        sta COLOR_RAM+40,x
        lda #32
        dex
        bpl @loop
        lda #$5D
        sta SCREEN+40
        sta SCREEN+79
        lda #14
        sta COLOR_RAM+40
        sta COLOR_RAM+79
        rts

draw_box_bottom_row:
        ldx #39
        lda #$40
@loop:
        sta SCREEN+80,x
        lda #14
        sta COLOR_RAM+80,x
        lda #$40
        dex
        bpl @loop
        lda #$6D
        sta SCREEN+80
        lda #$7D
        sta SCREEN+119
        rts

default_title_screen:
        .byte 18,5,1,4,25,2,1,19,9,3,0
default_free_label_screen:
        .byte 6,18,5,5,58,0
default_free_suffix_screen:
        .byte 32,2,1,19,9,3,32,2,25,20,5,19,0

rb_seed_plugin_reu_hidden:
        jsr rb_mark_reu_banks_hidden
        lda rb_seed_cold
        bne :+
        rts
:
        lda #<rb_reu_header
        sta rb_reu_c64_lo
        lda #>rb_reu_header
        sta rb_reu_c64_hi
        lda #<RB_REU_HEADER_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_HEADER_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #rb_reu_header_end-rb_reu_header
        sta rb_reu_len_lo
        lda #0
        sta rb_reu_len_hi
        jsr rb_reu_stash

        lda #<rb_command_descriptors
        sta rb_reu_c64_lo
        lda #>rb_command_descriptors
        sta rb_reu_c64_hi
        lda #<RB_REU_DESC_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_DESC_OFF
        sta rb_reu_off_hi
        lda #<((RB_CMD_DESC_COUNT * RB_CMD_DESC_SIZE))
        sta rb_reu_len_lo
        lda #>((RB_CMD_DESC_COUNT * RB_CMD_DESC_SIZE))
        sta rb_reu_len_hi
        jsr rb_reu_stash

        lda #<__LOWPACK_LOAD__
        sta rb_reu_c64_lo
        lda #>__LOWPACK_LOAD__
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        sta rb_reu_off_hi
        lda #RB_REU_CODE_BANK
        sta rb_reu_bank
        lda #<((__SLOTPACK2_LOAD__ - __LOWPACK_LOAD__) + __SLOTPACK2_SIZE__)
        sta rb_reu_len_lo
        lda #>((__SLOTPACK2_LOAD__ - __LOWPACK_LOAD__) + __SLOTPACK2_SIZE__)
        sta rb_reu_len_hi
        jsr rb_reu_stash

        jsr rb_clear_slot_residency
        jsr rb_clear_handle_heap
        rts

rb_clear_slot_residency:
        lda #0
        sta rb_slot0_module
        sta rb_slot0_submodule
        sta rb_slot0_overlay
        sta rb_slot0_generation
        rts

rb_mark_reu_banks_hidden:
        lda #RB_REU_TYPE_CORE
        sta RB_REU_ALLOC_TABLE + RB_REU_CORE_BANK
        lda #RB_REU_TYPE_CODE
        sta RB_REU_ALLOC_TABLE + RB_REU_CODE_BANK
        rts

rb_clear_handle_heap:
        ldx #0
        lda #0
@zero:
        sta RB_PAGEBUF,x
        inx
        bne @zero
        ldx #0
@stash:
        lda rb_clear_heap_pages,x
        sta rb_reu_off_hi
        lda #0
        sta rb_reu_off_lo
        jsr rb_stash_zero_pagebuf
        inx
        cpx #3
        bcc @stash
        rts

rb_clear_heap_pages:
        .byte >RB_REU_HANDLE_OFF, >(RB_REU_HANDLE_OFF + $0100), >RB_REU_HEAP_OFF

rb_stash_zero_pagebuf:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

save_basic_runtime_state:
        tsx
        txa
        clc
        adc #4
        sta RUNTIME_SP

        lda #0
        sta rb_reu_c64_lo
        sta rb_reu_c64_hi
        lda #<RB_REU_RUNTIME_ZP_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_RUNTIME_ZP_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash

        lda #0
        sta rb_reu_c64_lo
        lda #1
        sta rb_reu_c64_hi
        lda #<RB_REU_RUNTIME_STACK_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_RUNTIME_STACK_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash

        jsr refresh_hidden_shadow

        lda #RB_STATE_MAGIC1
        sta RUNTIME_MAGIC1
        lda #RB_STATE_MAGIC2
        sta RUNTIME_MAGIC2
        lda BASIC_START
        sta RUNTIME_FIRST_LO
        lda BASIC_START+1
        sta RUNTIME_FIRST_HI
        jmp validate_basic_line_chain

validate_basic_line_chain:
        lda #1
        sta RUNTIME_LINE_OK
        lda #<BASIC_START
        sta rb_ptr_lo
        lda #>BASIC_START
        sta rb_ptr_hi
@line:
        ldy #0
        lda (rb_ptr_lo),y
        sta rb_hidden_next_lo
        iny
        lda (rb_ptr_lo),y
        sta rb_hidden_next_hi
        ora rb_hidden_next_lo
        beq @done
        lda rb_hidden_next_hi
        cmp #>BASIC_START
        bcc @bad
        cmp #>BASIC_LIMIT
        bcs @bad
        cmp rb_ptr_hi
        bcc @bad
        bne @advance
        lda rb_hidden_next_lo
        cmp rb_ptr_lo
        beq @bad
        bcc @bad
@advance:
        lda rb_hidden_next_lo
        sta rb_ptr_lo
        lda rb_hidden_next_hi
        sta rb_ptr_hi
        jmp @line
@done:
        clc
        lda rb_ptr_lo
        adc #2
        sta RUNTIME_END_LO
        lda rb_ptr_hi
        adc #0
        sta RUNTIME_END_HI
        rts
@bad:
        lda #0
        sta RUNTIME_LINE_OK
        rts

rb_hidden_next_lo: .byte 0
rb_hidden_next_hi: .byte 0

refresh_hidden_shadow:
        lda #<__HIDDEN_RUN__
        sta rb_entry_src
        lda #>__HIDDEN_RUN__
        sta rb_entry_src+1
        lda #<HIDDEN_SHADOW
        sta rb_entry_dst
        lda #>HIDDEN_SHADOW
        sta rb_entry_dst+1
        lda #<__HIDDEN_SIZE__
        sta rb_entry_len
        lda #>__HIDDEN_SIZE__
        sta rb_entry_len+1
        jsr entry_copy_block
        rts

; ---------------------------------------------------------------------------
; Bridge state only.  Code stays out of $C000 unless it must be resident there.
; ---------------------------------------------------------------------------

        .segment "BRIDGE"

rb_draw_header:
        jsr call_hidden_draw_default_header
        jsr rb_update_header_free
        lda #1
        sta COLOR_CODE
        rts

rb_calc_basic_free:
        sec
        lda FRETOP
        sbc STREND
        sta rb_free_lo
        lda FRETOP+1
        sbc STREND+1
        sta rb_free_hi
        rts

rb_print_live_free:
        jsr rb_calc_basic_free
        lda #0
        sta rb_digit_seen
        ldx #0
@place:
        lda #0
        sta rb_digit_count
@sub:
        sec
        lda rb_free_lo
        sbc rb_decimal_lo,x
        sta rb_tmp_lo
        lda rb_free_hi
        sbc rb_decimal_hi,x
        bcc @emit
        sta rb_free_hi
        lda rb_tmp_lo
        sta rb_free_lo
        inc rb_digit_count
        jmp @sub
@emit:
        lda rb_digit_count
        bne @print
        lda rb_digit_seen
        bne @print
        cpx #4
        bne @next
        lda #0
@print:
        ora #'0'
        jsr K_CHROUT
        lda #1
        sta rb_digit_seen
@next:
        inx
        cpx #5
        bcc @place
        rts

rb_decimal_lo:
        .byte <10000,<1000,<100,<10,<1
rb_decimal_hi:
        .byte >10000,>1000,>100,>10,>1

rb_update_header_free:
        sec
        jsr K_PLOT
        stx rb_saved_plot_x
        sty rb_saved_plot_y

        clc
        ldx #1
        ldy #8
        jsr K_PLOT
        lda #13
        sta COLOR_CODE
        lda #' '
        jsr K_CHROUT
        lda #' '
        jsr K_CHROUT
        lda #' '
        jsr K_CHROUT
        lda #' '
        jsr K_CHROUT
        lda #' '
        jsr K_CHROUT

        clc
        ldx #1
        ldy #8
        jsr K_PLOT
        jsr rb_print_live_free

        lda #1
        sta COLOR_CODE
        clc
        ldx rb_saved_plot_x
        ldy rb_saved_plot_y
        jsr K_PLOT
        rts

call_hidden_draw_default_header:
        php
        sei
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda CPU_PORT
        sta rb_saved_cpu
        and #RAM_UNDER_BASIC_KEEP_KERNAL
        sta CPU_PORT
        jsr draw_default_header
        lda rb_saved_cpu
        sta CPU_PORT
        plp
        rts

rb_crunch:
        jsr rb_call_orig_crunch
        sty rb_crunch_len
        ldx #0
@scan:
        cpx rb_crunch_len
        bcs @done
        lda BASIC_INPUT_BUF,x
        cmp #TOKEN_THEN
        bne @advance
@skip:
        inx
        cpx rb_crunch_len
        bcs @done
        lda BASIC_INPUT_BUF,x
        cmp #' '
        beq @skip
        stx rb_peek_lo
        lda #>BASIC_INPUT_BUF
        sta rb_peek_hi
        jsr rb_match_exec
        bcs @matched
        jsr rb_match_jump
        bcc @advance
@matched:
        lda rb_crunch_len
        cmp #BASIC_INPUT_MAX
        bcs @done
        tax
@shift:
        lda BASIC_INPUT_BUF,x
        sta BASIC_INPUT_BUF+1,x
        cpx rb_peek_lo
        beq @insert
        dex
        jmp @shift
@insert:
        ldx rb_peek_lo
        lda #':'
        sta BASIC_INPUT_BUF,x
        inc rb_crunch_len
        inx
        inx
        jmp @scan
@done:
        ldy rb_crunch_len
        rts

@advance:
        inx
        jmp @scan

rb_call_orig_crunch:
        jmp (rb_orig_crunch_lo)

rb_magic:       .byte 0
rb_magic2:      .byte 0
rb_seed_cold:   .byte 0
rb_error:       .byte 0
rb_saved_cpu:   .byte 0
rb_vectors_saved:.byte 0
rb_orig_crunch_lo:.byte 0
rb_orig_crunch_hi:.byte 0
rb_orig_list_lo:.byte 0
rb_orig_list_hi:.byte 0
rb_orig_execute_lo:.byte 0
rb_orig_execute_hi:.byte 0
rb_peek_lo:     .byte 0
rb_peek_hi:     .byte 0
rb_crunch_len:  .byte 0
rb_eval_save_lo:.byte 0
rb_eval_save_hi:.byte 0
rb_eval_after_lo:.byte 0
rb_eval_after_hi:.byte 0
rb_expr_type:   .byte 0

rb_cmd_len:     .byte 0
rb_lookup_index:.byte 0
rb_lookup_slots:.byte 0
rb_lookup_char: .byte 0
rb_target_off:  .byte 0
rb_saved_count_lo:.byte 0
rb_saved_count_hi:.byte 0

        .segment "RESIDENT"
rb_num_save_depth:.byte 0
rb_save_num0_lo:.res 4
rb_save_num0_hi:.res 4
rb_float_save_depth:.byte 0
rb_save_float0_buf:.res 20

        .segment "BRIDGE"
rb_free_lo:     .byte 0
rb_free_hi:     .byte 0
rb_tmp_lo:      .byte 0
rb_digit_count: .byte 0
rb_digit_seen:  .byte 0
rb_saved_plot_x:.byte 0
rb_saved_plot_y:.byte 0

rb_kw_proc:     .byte "PROC",0
rb_kw_func:     .byte "FUNC",0
rb_kw_exec:     .byte "EXEC",0
rb_kw_ret:      .byte "RET",0
rb_kw_repeat:   .byte "REPEAT",0
        .segment "RESIDENT"
rb_kw_until:    .byte "UNTIL",0
rb_kw_label:    .byte "LABEL",0
rb_kw_jump:     .byte "JUMP",0
        .segment "BRIDGE"
rb_kw_endp:     .byte "ENDP",0
rb_kw_char:     .byte 0

rb_found_kind:  .byte 0
rb_found_line_lo:.byte 0
rb_found_line_hi:.byte 0
rb_scan_line_lo:.byte 0
rb_scan_line_hi:.byte 0
rb_next_line_lo:.byte 0
rb_next_line_hi:.byte 0
rb_stmt_lo:     .byte 0
rb_stmt_hi:     .byte 0
rb_def_lo:      .byte 0
rb_def_hi:      .byte 0
rb_form_lo:     .byte 0
rb_form_hi:     .byte 0
rb_form_next_lo:.byte 0
rb_form_next_hi:.byte 0
rb_formal_lo:  .byte 0
rb_formal_hi:  .byte 0
rb_actual_lo:  .byte 0
rb_actual_hi:  .byte 0
rb_actual_wrapped:.byte 0
rb_bind_expr_mode:.byte 0
rb_command_precomputed:.byte 0
rb_exec_out_type:.byte 0
rb_exec_out_lo:.byte 0
rb_exec_out_hi:.byte 0
rb_proc_depth: .byte 0
rb_proc_ret_lo:.res RB_PROC_DEPTH
rb_proc_ret_hi:.res RB_PROC_DEPTH
rb_proc_cur_lo:.res RB_PROC_DEPTH
rb_proc_cur_hi:.res RB_PROC_DEPTH

        .segment "RESIDENT"
rb_loop_depth: .byte 0
rb_loop_txt_lo:.res RB_LOOP_DEPTH
rb_loop_txt_hi:.res RB_LOOP_DEPTH
rb_loop_cur_lo:.res RB_LOOP_DEPTH
rb_loop_cur_hi:.res RB_LOOP_DEPTH
rb_last_error: .byte 0
rb_last_line_lo:.byte 0
rb_last_line_hi:.byte 0

rb_func_depth:.byte 0
rb_form_save_count:.res RB_PROC_DEPTH
        .segment "BRIDGE"
rb_form_save_type:.res 16
rb_form_save_lo:.res 16
        .segment "RESIDENT"
rb_form_save_hi:.res 16
rb_form_save_val0:.res 16
rb_form_save_val1:.res 16
rb_form_save_val2:.res 16
rb_form_save_val3:.res 16
rb_form_save_val4:.res 16
rb_save_type_tmp:.byte 0
rb_save_depth_tmp:.byte 0
rb_save_count_tmp:.byte 0
rb_save_idx:.byte 0

        .segment "BRIDGE"
RUNTIME_MAGIC1:  .byte 0
RUNTIME_MAGIC2:  .byte 0
RUNTIME_SP:      .byte 0
RUNTIME_MODE:    .byte 0
RUNTIME_LINE_OK: .byte 0
RUNTIME_FIRST_LO:.byte 0
RUNTIME_FIRST_HI:.byte 0
RUNTIME_END_LO:  .byte 0
RUNTIME_END_HI:  .byte 0

rb_out_type:    .byte 0
rb_out_count:   .byte 0
rb_out_ptr_lo:  .byte 0
rb_out_ptr_hi:  .byte 0
rb_out_count_lo:.byte 0
rb_out_count_hi:.byte 0

rb_overlay_vec_lo:.byte 0
rb_overlay_vec_hi:.byte 0
rb_slot0_module:.byte 0
rb_slot0_submodule:.byte 0
rb_slot0_overlay:.byte 0
rb_slot0_generation:.byte 0

rb_reu_c64_lo:  .byte 0
rb_reu_c64_hi:  .byte 0
rb_reu_off_lo:  .byte 0
rb_reu_off_hi:  .byte 0
rb_reu_bank:    .byte 0
rb_reu_len_lo:  .byte 0
rb_reu_len_hi:  .byte 0

rb_handle_bank: .byte 0
rb_handle_page: .byte 0
rb_handle_pages:.byte 0
rb_handle_type: .byte 0
rb_handle_index:.byte 0
rb_needed_pages:.byte 0
rb_handle_new_type:.byte 0
rb_found_page:  .byte 0
rb_handle_desc_off:.byte 0
rb_handle_scan_base:.byte 0
rb_fill_page:   .byte 0
rb_copy_page:   .byte 0
rb_copy_chunks: .byte 0
rb_copy_len_lo: .byte 0
rb_copy_len_hi: .byte 0

; ---------------------------------------------------------------------------
; Packed command submodule 0. This 2KB slot image is copied from REU bank $45
; into $A800-$AFFF on demand, then reused while residency metadata matches.
; ---------------------------------------------------------------------------

        .segment "LOWPACK"

cmd_zecho1_low:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_zecho1_low_end:

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

cmd_zslot0_low:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #30
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_zslot0_low_end:

cmd_fadd_low:
        rts
cmd_fadd_low_end:

cmd_zpause_low:
        lda CF_NUM0_LO
        beq @done
        sta RF_COUNT_LO
@outer:
        ldx #$20
@middle:
        ldy #$ff
@inner:
        dey
        bne @inner
        dex
        bne @middle
        dec RF_COUNT_LO
        bne @outer
@done:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_NONE
        sta RF_TAG
        rts
cmd_zpause_low_end:

cmd_upper_low:
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
        sbc #$80
        jmp @store
@ascii_case:
        cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        sec
        sbc #$20
@store:
:       sta RF_STR_BUF,y
        iny
        jmp @loop
@done:
        rts
cmd_upper_low_end:

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
        sbc #$60
        jmp @store
@ascii_case:
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        clc
        adc #$20
@store:
:       sta RF_STR_BUF,y
        iny
        jmp @loop
@done:
        rts
cmd_lower_low_end:

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
        ldy #1
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
        adc #2
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

cmd_zrangenumarray_low:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_ARRAYI
        sta RF_TAG
        lda CF_NUM1_LO
        sta RF_COUNT_LO
        lda CF_NUM1_HI
        sta RF_COUNT_HI
        lda CF_NUM0_LO
        sta rb_ptr_lo
        lda CF_NUM0_HI
        sta rb_ptr_hi
        ldx CF_NUM1_LO
        beq @done
        ldy #0
@loop:
        lda rb_ptr_hi
        sta RF_ARRAY_BUF,y
        iny
        lda rb_ptr_lo
        sta RF_ARRAY_BUF,y
        iny
        inc rb_ptr_lo
        bne :+
        inc rb_ptr_hi
:       dex
        bne @loop
@done:
        rts
cmd_zrangenumarray_low_end:

cmd_bufnew_low:
        jsr rb_handle_alloc
        rts
cmd_bufnew_low_end:

cmd_buffill_low:
        jsr rb_handle_fill
        rts
cmd_buffill_low_end:

cmd_buffree_low:
        jsr rb_handle_free
        rts
cmd_buffree_low_end:

cmd_ztempscratch_low:
        jsr rb_temp_alloc
        rts
cmd_ztempscratch_low_end:

cmd_zfail_low:
        lda CF_NUM0_LO
        bne :+
        lda #$7F
:       sta RF_STATUS
        sta RF_ERROR
        lda #RB_VAL_INT
        sta RF_TAG
        lda #0
        sta RF_VAL_LO
        sta RF_VAL_HI
        rts
cmd_zfail_low_end:

cmd_freemem_low:
        jsr rb_print_live_free
        lda #13
        jsr K_CHROUT
        jsr rb_update_header_free
        lda #0
        sta RF_STATUS
        lda #RB_VAL_NONE
        sta RF_TAG
        rts
cmd_freemem_low_end:

cmd_scrcap_low:
        jsr rb_screen_handle_alloc
        lda RF_STATUS
        beq :+
        rts
:       jsr rb_screen_save_text
        jsr rb_screen_save_color
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        ldx rb_handle_index
        txa
        clc
        adc #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_scrcap_low_end:

cmd_scrput_low:
        jsr rb_screen_handle_validate
        lda RF_STATUS
        beq :+
        rts
:       jsr rb_screen_load_text
        jsr rb_screen_load_color
        lda #0
        sta RF_STATUS
        lda #RB_VAL_NONE
        sta RF_TAG
        rts
cmd_scrput_low_end:

rb_handle_alloc:
        jsr rb_len_to_pages
        bcc :+
        jmp rb_overlay_bad_length
:       lda #RB_HANDLE_TYPE_BUFFER
        sta rb_handle_new_type
        jmp rb_handle_alloc_with_pages

rb_screen_handle_alloc:
        lda #RB_SCREEN_HANDLE_PAGES
        sta rb_needed_pages
        lda #RB_HANDLE_TYPE_SCREEN_TC
        sta rb_handle_new_type

rb_handle_alloc_with_pages:
        jsr rb_find_free_handle
        bcc @got_handle
        lda #$21
        jmp rb_overlay_fail
@got_handle:
        jsr rb_find_pages
        bcs @no_pages
        lda #RB_REU_CORE_BANK
        sta rb_handle_bank
        lda rb_found_page
        clc
        adc #RB_HEAP_PAGE_BASE
        sta rb_handle_page
        lda rb_needed_pages
        sta rb_handle_pages
        lda rb_handle_new_type
        sta rb_handle_type
        jsr rb_mark_pages_used
        jsr rb_store_heap_bitmap
        jsr rb_handle_store
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda rb_handle_index
        clc
        adc #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
@no_pages:
        lda #$22
        jmp rb_overlay_fail

rb_screen_handle_validate:
        jsr rb_handle_load_arg
        bcs @bad
        lda rb_handle_type
        cmp #RB_HANDLE_TYPE_SCREEN_TC
        bne @wrong_type
        clc
        rts
@wrong_type:
        lda #$28
        jmp rb_overlay_fail
@bad:
        lda #$24
        jmp rb_overlay_fail

rb_overlay_bad_length:
        lda #$23
rb_overlay_fail:
        sta RF_STATUS
        sta RF_ERROR
        rts

rb_len_to_pages:
        lda CF_NUM0_LO
        ora CF_NUM0_HI
        beq @bad
        lda CF_NUM0_HI
        sta rb_needed_pages
        lda CF_NUM0_LO
        beq @check
        inc rb_needed_pages
@check:
        lda rb_needed_pages
        beq @bad
        cmp #RB_HEAP_PAGES + 1
        bcs @bad
        clc
        rts
@bad:
        sec
        rts

rb_handle_desc_fetch_page:
        lda rb_handle_index
        and #$3F
        asl
        asl
        sta rb_handle_desc_off
        lda #0
        sta rb_reu_off_lo
        lda #>RB_REU_HANDLE_OFF
        ldx rb_handle_index
        cpx #RB_HANDLE_PAGE_SLOTS
        bcc :+
        clc
        adc #1
:       sta rb_reu_off_hi
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        rts

rb_handle_fetch:
        jsr rb_handle_desc_fetch_page
        ldy rb_handle_desc_off
        lda RB_PAGEBUF,y
        sta rb_handle_bank
        iny
        lda RB_PAGEBUF,y
        sta rb_handle_page
        iny
        lda RB_PAGEBUF,y
        sta rb_handle_pages
        iny
        lda RB_PAGEBUF,y
        sta rb_handle_type
        rts

rb_handle_store:
        jsr rb_handle_desc_fetch_page
        ldy rb_handle_desc_off
        lda rb_handle_bank
        sta RB_PAGEBUF,y
        iny
        lda rb_handle_page
        sta RB_PAGEBUF,y
        iny
        lda rb_handle_pages
        sta RB_PAGEBUF,y
        iny
        lda rb_handle_type
        sta RB_PAGEBUF,y
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

rb_find_free_handle:
        lda #0
        sta rb_handle_scan_base
@page:
        lda rb_handle_scan_base
        sta rb_handle_index
        jsr rb_handle_desc_fetch_page
        ldy #0
        ldx #0
@slot:
        lda RB_PAGEBUF,y
        beq @found
        tya
        clc
        adc #RB_HANDLE_DESC_SIZE
        tay
        inx
        cpx #RB_HANDLE_PAGE_SLOTS
        bcc @slot
        lda rb_handle_scan_base
        bne @full
        lda #RB_HANDLE_PAGE_SLOTS
        sta rb_handle_scan_base
        jmp @page
@found:
        txa
        clc
        adc rb_handle_scan_base
        sta rb_handle_index
        clc
        rts
@full:
        sec
        rts

rb_handle_load_arg:
        lda CF_NUM0_HI
        bne @bad
        lda CF_NUM0_LO
        beq @bad
        cmp #RB_HANDLE_COUNT + 1
        bcs @bad
        sec
        sbc #1
        sta rb_handle_index
        jsr rb_handle_fetch
        lda rb_handle_bank
        beq @bad
        clc
        rts
@bad:
        sec
        rts

rb_fetch_heap_bitmap:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #<RB_REU_HEAP_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_HEAP_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        rts

rb_store_heap_bitmap:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #<RB_REU_HEAP_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_HEAP_OFF
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

rb_find_pages:
        jsr rb_fetch_heap_bitmap
        lda #0
        sta rb_found_page
@outer:
        lda rb_found_page
        clc
        adc rb_needed_pages
        cmp #RB_HEAP_PAGES + 1
        bcc :+
        sec
        rts
:       ldx #0
@inner:
        txa
        clc
        adc rb_found_page
        tay
        lda RB_PAGEBUF,y
        bne @next_start
        inx
        cpx rb_needed_pages
        bcc @inner
        clc
        rts
@next_start:
        inc rb_found_page
        jmp @outer

rb_mark_pages_used:
        ldx #0
@loop:
        txa
        clc
        adc rb_found_page
        tay
        lda #1
        sta RB_PAGEBUF,y
        inx
        cpx rb_needed_pages
        bcc @loop
        rts

rb_handle_free:
        jsr rb_handle_load_arg
        bcs @bad
        lda rb_handle_page
        sec
        sbc #RB_HEAP_PAGE_BASE
        sta rb_found_page
        lda rb_handle_pages
        sta rb_needed_pages
        jsr rb_fetch_heap_bitmap
        jsr rb_mark_pages_free
        lda #0
        sta rb_handle_bank
        sta rb_handle_page
        sta rb_handle_pages
        sta rb_handle_type
        jsr rb_store_heap_bitmap
        jsr rb_handle_store
        lda #0
        sta RF_STATUS
        sta RF_TAG
        rts
@bad:
        lda #$24
        jmp rb_overlay_fail

rb_mark_pages_free:
        ldx #0
@loop:
        txa
        clc
        adc rb_found_page
        tay
        lda #0
        sta RB_PAGEBUF,y
        inx
        cpx rb_needed_pages
        bcc @loop
        rts

rb_handle_fill:
        jsr rb_handle_load_arg
        bcs @bad
        lda rb_handle_type
        cmp #RB_HANDLE_TYPE_BUFFER
        bne @wrong_type
        lda CF_NUM1_LO
        ldx #0
@fillbuf:
        sta RB_PAGEBUF,x
        inx
        bne @fillbuf
        lda rb_handle_page
        sta rb_fill_page
        lda rb_handle_pages
        sta rb_needed_pages
@page:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        lda rb_fill_page
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #0
        sta rb_reu_len_lo
        lda #1
        sta rb_reu_len_hi
        jsr rb_reu_stash
        inc rb_fill_page
        dec rb_needed_pages
        bne @page
        lda #0
        sta RF_STATUS
        sta RF_TAG
        rts
@bad:
        lda #$25
        jmp rb_overlay_fail
@wrong_type:
        lda #$28
        jmp rb_overlay_fail

rb_temp_alloc:
        jsr rb_len_to_pages
        bcs @bad
        jsr rb_find_pages
        bcs @bad
        jsr rb_mark_pages_used
        jsr rb_mark_pages_free
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda rb_needed_pages
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
@bad:
        lda #$26
        jmp rb_overlay_fail

rb_screen_save_text:
        lda #<SCREEN
        sta rb_reu_c64_lo
        lda #>SCREEN
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        lda rb_handle_page
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #<RB_SCREEN_BYTES
        sta rb_reu_len_lo
        lda #>RB_SCREEN_BYTES
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

rb_screen_load_text:
        lda #<SCREEN
        sta rb_reu_c64_lo
        lda #>SCREEN
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        lda rb_handle_page
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #<RB_SCREEN_BYTES
        sta rb_reu_len_lo
        lda #>RB_SCREEN_BYTES
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        rts

rb_screen_save_color:
        lda #<COLOR_RAM
        sta rb_ptr_lo
        lda #>COLOR_RAM
        sta rb_ptr_hi
        lda rb_handle_page
        clc
        adc #4
        sta rb_copy_page
        lda #4
        sta rb_copy_chunks
@chunk:
        jsr rb_screen_set_copy_len
        jsr rb_copy_ptr_to_pagebuf
        jsr rb_stash_pagebuf_to_copy_page
        inc rb_ptr_hi
        inc rb_copy_page
        dec rb_copy_chunks
        bne @chunk
        rts

rb_screen_load_color:
        lda #<COLOR_RAM
        sta rb_ptr_lo
        lda #>COLOR_RAM
        sta rb_ptr_hi
        lda rb_handle_page
        clc
        adc #4
        sta rb_copy_page
        lda #4
        sta rb_copy_chunks
@chunk:
        jsr rb_screen_set_copy_len
        jsr rb_fetch_pagebuf_from_copy_page
        jsr rb_copy_pagebuf_to_ptr
        inc rb_ptr_hi
        inc rb_copy_page
        dec rb_copy_chunks
        bne @chunk
        rts

rb_screen_set_copy_len:
        lda rb_copy_chunks
        cmp #1
        beq @tail
        lda #0
        sta rb_copy_len_lo
        lda #1
        sta rb_copy_len_hi
        rts
@tail:
        lda #<RB_SCREEN_BYTES
        sta rb_copy_len_lo
        lda #0
        sta rb_copy_len_hi
        rts

rb_copy_ptr_to_pagebuf:
        lda rb_copy_len_hi
        beq @short
        ldy #0
@full:
        lda (rb_ptr_lo),y
        sta RB_PAGEBUF,y
        iny
        bne @full
        rts
@short:
        ldy #0
@short_loop:
        cpy rb_copy_len_lo
        beq @done
        lda (rb_ptr_lo),y
        sta RB_PAGEBUF,y
        iny
        jmp @short_loop
@done:
        rts

rb_copy_pagebuf_to_ptr:
        lda rb_copy_len_hi
        beq @short
        ldy #0
@full:
        lda RB_PAGEBUF,y
        sta (rb_ptr_lo),y
        iny
        bne @full
        rts
@short:
        ldy #0
@short_loop:
        cpy rb_copy_len_lo
        beq @done
        lda RB_PAGEBUF,y
        sta (rb_ptr_lo),y
        iny
        jmp @short_loop
@done:
        rts

rb_stash_pagebuf_to_copy_page:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        lda rb_copy_page
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda rb_copy_len_lo
        sta rb_reu_len_lo
        lda rb_copy_len_hi
        sta rb_reu_len_hi
        jsr rb_reu_stash
        rts

rb_fetch_pagebuf_from_copy_page:
        lda #<RB_PAGEBUF
        sta rb_reu_c64_lo
        lda #>RB_PAGEBUF
        sta rb_reu_c64_hi
        lda #0
        sta rb_reu_off_lo
        lda rb_copy_page
        sta rb_reu_off_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda rb_copy_len_lo
        sta rb_reu_len_lo
        lda rb_copy_len_hi
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        rts

; ---------------------------------------------------------------------------
; Former hidden worker command implementation. It now lives in the same
; default command submodule as the other command workers.
; ---------------------------------------------------------------------------

cmd_zhiddenram_hidden:
        lda #0
        sta RF_VAL_LO
        sta RF_VAL_HI
        ldy #0
@loop:
        cpy CF_STR_LEN
        beq @done
        lda RF_VAL_LO
        sta rb_ptr_lo
        lda CF_STR_BUF,y
        cmp #$C1
        bcc @ascii_case
        cmp #$DB
        bcs @ascii_case
        sec
        sbc #$80
        jmp @sum
@ascii_case:
        cmp #'a'
        bcc @sum
        cmp #'z' + 1
        bcs @sum
        sec
        sbc #$20
@sum:
        clc
        adc rb_ptr_lo
        sta RF_VAL_LO
        lda RF_VAL_HI
        adc #0
        sta RF_VAL_HI
        iny
        jmp @loop
@done:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        rts
cmd_zhiddenram_hidden_end:

        .segment "SLOTPACK1"

cmd_zslot1:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #31
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_zslot1_end:

        .segment "SLOTPACK2"

cmd_zslot2:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #32
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_zslot2_end:
