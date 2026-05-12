;
; readybasic.s - lean ReadyBASIC REU plugin command spine
;
; Load address: $1000
; Visible resident core: $1200-$1BFF
; Low command overlay: $1C00-$23FF
; Shared call/result buffers: $2400-$27FF
; BASIC workspace: $3001-$95FF
; Runtime save state: $9600-$99FF
; Hidden helper shadow: $9A00-$9FFF, restored to $A000-$A5FF
; Bridge state/trampolines: $C000-$C5FF
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
BASIC_FRMNUM    = $AD8A
BASIC_CHKCOM    = $AEFD
BASIC_SYNERR    = $AF08
BASIC_PTRGET    = $B08B
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
KEYD_COUNT      = $00C6
COLOR_CODE      = $0286
KERNAL_MEMTOP   = $0281
KERNAL_MEMBOT   = $0283

BASIC_START     = $3001
BASIC_SENTINEL  = BASIC_START - 1
BASIC_LIMIT     = $9600
BASIC_BYTES_FREE = BASIC_LIMIT - (BASIC_START + 2)
RUNTIME_ZP      = $9600
RUNTIME_STACK   = $9700
RUNTIME_META    = $9800
RUNTIME_MAGIC1  = RUNTIME_META + $00
RUNTIME_MAGIC2  = RUNTIME_META + $01
RUNTIME_SP      = RUNTIME_META + $02
RUNTIME_MODE    = RUNTIME_META + $03
RUNTIME_LINE_OK = RUNTIME_META + $04
RUNTIME_FIRST_LO= RUNTIME_META + $05
RUNTIME_FIRST_HI= RUNTIME_META + $06
RUNTIME_END_LO  = RUNTIME_META + $07
RUNTIME_END_HI  = RUNTIME_META + $08
HIDDEN_SHADOW   = $9A00

CPU_DDR         = $0000
CPU_PORT        = $0001
VIC_MEM         = $D018

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

RAM_UNDER_BASIC = $FD
RAM_UNDER_BASIC_KEEP_KERNAL = $FE
VIC_MEM_LOWERCASE = $16

; ---------------------------------------------------------------------------
; ReadyBASIC plugin ABI constants
; ---------------------------------------------------------------------------

RB_LOW_BASE     = $1C00
RB_HIDDEN_BASE  = $A000
RB_SHARED       = $2400
RB_CF           = $2400
RB_RF           = $2500
RB_DESC_BUF     = $2680
RB_CMDBUF       = $26A0
RB_PAGEBUF      = $2700

CF_CMD_ID       = RB_CF + $00
CF_PARAM_COUNT  = RB_CF + $01
CF_NUM0_LO      = RB_CF + $10
CF_NUM0_HI      = RB_CF + $11
CF_NUM1_LO      = RB_CF + $12
CF_NUM1_HI      = RB_CF + $13
CF_NUM2_LO      = RB_CF + $14
CF_NUM2_HI      = RB_CF + $15
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
RF_STR_LEN      = RB_RF + $10
RF_STR_BUF      = RB_RF + $20
RF_ARRAY_BUF    = RB_RF + $80

RB_VAL_NONE     = 0
RB_VAL_INT      = 1
RB_VAL_STRING   = 2
RB_VAL_ARRAYI   = 3

RB_OUT_NONE     = 0
RB_OUT_INT      = 1
RB_OUT_STRING   = 2
RB_OUT_ARRAYI   = 3

RB_CMD_F_LOW    = $01
RB_CMD_F_HIDDEN = $02

RB_REU_CORE_BANK= $44
RB_REU_CODE_BANK= $45
RB_REU_TYPE_CORE= 14
RB_REU_TYPE_CODE= 15
RB_REU_ALLOC_TABLE = $C600
RB_REU_HEADER_OFF  = $0000
RB_REU_DESC_OFF    = $0100
RB_REU_CALL_OFF    = $0400
RB_REU_RESULT_OFF  = $0500
RB_REU_DEBUG_OFF   = $0600
RB_REU_HANDLE_OFF  = $0800
RB_REU_HEAP_OFF    = $0900
RB_REU_DATA_OFF    = $8000

RB_CMD_DESC_SIZE   = 32
RB_CMD_DESC_COUNT  = 11
RB_MAX_NAME        = 15
RB_MAX_STR         = 64
RB_HANDLE_COUNT    = 8
RB_HEAP_PAGES      = 16

SIG_PING        = 1
SIG_ADD16       = 2
SIG_STRUP       = 3
SIG_HCRC        = 4
SIG_SUMAI       = 5
SIG_RANGEAI     = 6
SIG_BUFNEW      = 7
SIG_BUFFILL     = 8
SIG_BUFFREE     = 9
SIG_TEMPSCRATCH = 10
SIG_FAIL        = 11

CMD_PING        = 1
CMD_ADD16       = 2
CMD_STRUP       = 3
CMD_HCRC        = 4
CMD_SUMAI       = 5
CMD_RANGEAI     = 6
CMD_BUFNEW      = 7
CMD_BUFFILL     = 8
CMD_BUFFREE     = 9
CMD_TEMPSCRATCH = 10
CMD_FAIL        = 11

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
        .import __HIDDENPACK_LOAD__, __HIDDENPACK_RUN__, __HIDDENPACK_SIZE__

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
        .res $0C00, 0

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
        jsr rb_draw_banner
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
        lda #<rb_execute
        sta $0308
        lda #>rb_execute
        sta $0309
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
@done:
        rts

rb_execute:
        jsr rb_peek_next_nonspace
        cmp #'R'
        beq @maybe_rb
        cmp #'r'
        beq @maybe_rb
        cmp #'E'
        beq @maybe_exit
        cmp #'e'
        beq @maybe_exit
        jmp rb_call_orig_execute
@maybe_rb:
        lda rb_peek_lo
        sta rb_ptr_lo
        lda rb_peek_hi
        sta rb_ptr_hi
        ldy #1
        lda (rb_ptr_lo),y
        cmp #'B'
        beq @got_rb
        cmp #'b'
        bne rb_call_orig_execute
@got_rb:
        lda rb_peek_lo
        sta TXTPTR
        lda rb_peek_hi
        sta TXTPTR+1
        jsr CHRGET
        jsr CHRGET
        jmp rb_plugin_statement
@maybe_exit:
        jsr rb_match_exit
        bcc rb_call_orig_execute
        jmp cmd_exit

rb_call_orig_execute:
        jmp (rb_orig_execute_lo)

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
        lda RUNTIME_MAGIC1
        cmp #RB_STATE_MAGIC1
        bne @fallback
        lda RUNTIME_MAGIC2
        cmp #RB_STATE_MAGIC2
        bne @fallback
        lda RUNTIME_LINE_OK
        beq @fallback
        ldx #0
@stack:
        lda RUNTIME_STACK,x
        sta $0100,x
        inx
        bne @stack
        ldx #2
@zp:
        lda RUNTIME_ZP,x
        sta $0000,x
        inx
        bne @zp
        lda CPU_DDR
        ora #$07
        sta CPU_DDR
        lda #$37
        sta CPU_PORT
        jsr set_basic_memory_bounds
        lda #0
        sta KEYD_COUNT
        lda RUNTIME_MODE
        cmp #RB_RESUME_RUN
        beq @running_resume
        jsr prepare_basic_console
        jsr rb_draw_banner
        jsr position_basic_prompt
        ldx RUNTIME_SP
        txs
        jmp BASIC_READY
@running_resume:
        ldx RUNTIME_SP
        txs
        jmp BASIC_NEXT_STMT
@fallback:
        jsr force_basic_workspace_pointers
        cli
        jmp BASIC_READY

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
        lda #5
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

rb_draw_banner:
        lda #<rb_banner_text
        sta rb_ptr_lo
        lda #>rb_banner_text
        sta rb_ptr_hi
        jsr rb_print_z
        lda #<rb_bytes_text
        sta rb_ptr_lo
        lda #>rb_bytes_text
        sta rb_ptr_hi
        jsr rb_print_z
        ldx #<BASIC_BYTES_FREE
        lda #>BASIC_BYTES_FREE
        jsr BASIC_LINPRT
        lda #13
        jsr K_CHROUT
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

rb_banner_text:
        .byte "READYBASIC REU PLUGINS",13,0
rb_bytes_text:
        .byte "BYTES FREE ",0

; ---------------------------------------------------------------------------
; RB command parsing and dispatch.
; ---------------------------------------------------------------------------

rb_plugin_statement:
        jsr rb_stage_start
        jsr rb_parse_command_name
        bcs @name_ok
        jmp BASIC_SYNERR
@name_ok:
        lda #$A1
        sta rb_debug_ring
        jsr rb_lookup_command
        bcs @found
        lda #$01
        jmp rb_runtime_error
@found:
        lda #$A2
        sta rb_debug_ring
        lda RB_DESC_BUF
        sta CF_CMD_ID
        lda #0
        sta CF_PARAM_COUNT
        jsr rb_clear_result_frame
        lda #$A3
        sta rb_debug_ring
        jsr rb_parse_by_signature
        lda #$A4
        sta rb_debug_ring
        jsr rb_stash_call_frame
        jsr rb_load_and_call_command
        jsr rb_stash_result_frame
        jsr rb_commit_result
        jmp BASIC_NEXT_STMT

rb_parse_command_name:
        jsr rb_skip_spaces
        ldx #0
@loop:
        jsr CHRGOT
        cmp #$A5
        bne @not_fn_token
        cpx #RB_MAX_NAME - 1
        bcs @too_long
        lda #'F'
        sta RB_CMDBUF,x
        inx
        lda #'N'
        sta RB_CMDBUF,x
        inx
        jsr CHRGET
        jmp @loop
@not_fn_token:
        cmp #$B8
        bne @not_fre_token
        cpx #RB_MAX_NAME - 2
        bcs @too_long
        lda #'F'
        sta RB_CMDBUF,x
        inx
        lda #'R'
        sta RB_CMDBUF,x
        inx
        lda #'E'
        sta RB_CMDBUF,x
        inx
        jsr CHRGET
        jmp @loop
@not_fre_token:
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
        jsr CHRGET
        jmp @loop
@done:
        stx rb_cmd_len
        beq @bad
        jsr rb_skip_spaces
        sec
        rts
@too_long:
@bad:
        clc
        rts

rb_skip_spaces:
@loop:
        jsr CHRGOT
        cmp #' '
        bne @done
        jsr CHRGET
        jmp @loop
@done:
        rts

rb_lookup_command:
        lda #<RB_REU_DESC_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_DESC_OFF
        sta rb_reu_off_hi
        lda #0
        sta rb_lookup_index
@loop:
        lda rb_lookup_index
        cmp #RB_CMD_DESC_COUNT
        bcc :+
        clc
        rts
:       lda #<RB_DESC_BUF
        sta rb_reu_c64_lo
        lda #>RB_DESC_BUF
        sta rb_reu_c64_hi
        lda #RB_REU_CORE_BANK
        sta rb_reu_bank
        lda #RB_CMD_DESC_SIZE
        sta rb_reu_len_lo
        lda #0
        sta rb_reu_len_hi
        jsr rb_reu_fetch
        lda RB_DESC_BUF+15
        cmp rb_cmd_len
        bne @next
        ldy #0
@cmp:
        cpy rb_cmd_len
        beq @match
        lda RB_DESC_BUF+16,y
        cmp RB_CMDBUF,y
        bne @next
        iny
        jmp @cmp
@match:
        sec
        rts
@next:
        clc
        lda rb_reu_off_lo
        adc #RB_CMD_DESC_SIZE
        sta rb_reu_off_lo
        bcc :+
        inc rb_reu_off_hi
:       inc rb_lookup_index
        jmp @loop

rb_parse_by_signature:
        lda RB_DESC_BUF+14
        cmp #SIG_PING
        beq parse_sig_ping
        cmp #SIG_ADD16
        beq parse_sig_add16
        cmp #SIG_STRUP
        beq parse_sig_strup
        cmp #SIG_HCRC
        beq parse_sig_hcrc
        cmp #SIG_SUMAI
        beq parse_sig_sumai
        cmp #SIG_RANGEAI
        beq parse_sig_rangeai
        cmp #SIG_BUFNEW
        beq parse_sig_bufnew
        cmp #SIG_BUFFILL
        beq parse_sig_buffill
        cmp #SIG_BUFFREE
        beq parse_sig_buffree
        cmp #SIG_TEMPSCRATCH
        beq parse_sig_tempscratch
        cmp #SIG_FAIL
        beq parse_sig_fail
        jmp BASIC_SYNERR

parse_sig_ping:
        lda #$31
        sta rb_debug_ring
        jsr rb_parse_out_int
        rts

parse_sig_add16:
        jsr rb_parse_num0
        jsr rb_parse_num1
        jsr rb_parse_out_int
        rts

parse_sig_strup:
        jsr rb_parse_string_value
        jsr rb_parse_out_string
        rts

parse_sig_hcrc:
        jsr rb_parse_string_value
        jsr rb_parse_out_int
        rts

parse_sig_sumai:
        jsr rb_parse_int_array_input
        jsr rb_parse_out_int
        jsr rb_resolve_int_array_input_ptr
        rts

parse_sig_rangeai:
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

parse_sig_tempscratch:
        jsr rb_parse_num0
        jsr rb_parse_out_int
        rts

parse_sig_fail:
        jsr rb_parse_num0
        jsr rb_parse_out_int
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
        jsr BASIC_CHKCOM
        jsr BASIC_FRMNUM
        jsr BASIC_GETADR
        ldy rb_target_off
        lda LINNUM
        sta RB_CF,y
        iny
        lda LINNUM+1
        sta RB_CF,y
        inc CF_PARAM_COUNT
        rts

rb_parse_out_int:
        jsr BASIC_CHKCOM
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
        jsr BASIC_CHKCOM
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

rb_parse_out_int_array:
        jsr BASIC_CHKCOM
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
        jsr BASIC_CHKCOM
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
        jsr rb_parse_num2
        lda CF_NUM2_LO
        sta CF_COUNT0_LO
        sta rb_saved_count_lo
        lda CF_NUM2_HI
        sta CF_COUNT0_HI
        sta rb_saved_count_hi
        inc CF_PARAM_COUNT
        rts

rb_parse_string_value:
        jsr BASIC_CHKCOM
        jsr CHRGOT
        cmp #$22
        beq rb_parse_quoted_string
        lda #0
        sta SUBFLG
        jsr BASIC_PTRGET
        lda VALTYP
        cmp #$FF
        bne rb_parse_type_error
        lda VARPNT
        sta rb_ptr2_lo
        lda VARPNT+1
        sta rb_ptr2_hi
        ldy #0
        lda (rb_ptr2_lo),y
        cmp #RB_MAX_STR + 1
        bcc :+
        lda #RB_MAX_STR
:       sta CF_STR_LEN
        iny
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
        beq @hidden
        lda RB_DESC_BUF+2
        sta rb_reu_off_lo
        lda RB_DESC_BUF+3
        sta rb_reu_off_hi
        lda RB_DESC_BUF+4
        sta rb_reu_len_lo
        lda RB_DESC_BUF+5
        sta rb_reu_len_hi
        clc
        lda #<RB_LOW_BASE
        adc RB_DESC_BUF+2
        sta rb_reu_c64_lo
        lda #>RB_LOW_BASE
        adc RB_DESC_BUF+3
        sta rb_reu_c64_hi
        clc
        lda #<RB_LOW_BASE
        adc RB_DESC_BUF+10
        sta rb_overlay_vec_lo
        lda #>RB_LOW_BASE
        adc RB_DESC_BUF+11
        sta rb_overlay_vec_hi
        lda #RB_REU_CODE_BANK
        sta rb_reu_bank
        jsr rb_reu_fetch
        jsr rb_call_low_overlay
@hidden:
        lda RB_DESC_BUF+8
        ora RB_DESC_BUF+9
        beq @done
        lda RB_DESC_BUF+6
        sta rb_reu_off_lo
        lda RB_DESC_BUF+7
        sta rb_reu_off_hi
        lda RB_DESC_BUF+8
        sta rb_reu_len_lo
        lda RB_DESC_BUF+9
        sta rb_reu_len_hi
        clc
        lda #<RB_HIDDEN_BASE
        adc RB_DESC_BUF+12
        sta rb_reu_c64_lo
        sta rb_overlay_vec_lo
        lda #>RB_HIDDEN_BASE
        adc RB_DESC_BUF+13
        sta rb_reu_c64_hi
        sta rb_overlay_vec_hi
        lda #RB_REU_CODE_BANK
        sta rb_reu_bank
        jsr rb_fetch_hidden_overlay
        jsr rb_call_hidden_overlay
@done:
        rts

rb_call_low_overlay:
        jmp (rb_overlay_vec_lo)

rb_fetch_hidden_overlay:
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

rb_call_hidden_overlay:
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
        bne @done
        jmp rb_commit_arrayi
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

rb_stage_start:
        lda #'S'
        sta rb_debug_ring
        rts

rb_clear_handle_heap:
        ldx #0
        lda #0
@h:
        sta rb_handle_bank,x
        sta rb_handle_page,x
        sta rb_handle_pages,x
        sta rb_handle_type,x
        inx
        cpx #RB_HANDLE_COUNT
        bcc @h
        ldx #0
@p:
        sta rb_page_bitmap,x
        inx
        cpx #RB_HEAP_PAGES
        bcc @p
        jsr rb_stash_handle_meta
        rts

rb_stash_handle_meta:
        lda #<rb_handle_bank
        sta rb_reu_c64_lo
        lda #>rb_handle_bank
        sta rb_reu_c64_hi
        lda #<RB_REU_HANDLE_OFF
        sta rb_reu_off_lo
        lda #>RB_REU_HANDLE_OFF
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
        .byte id, RB_CMD_F_LOW
        .word label - __LOWPACK_RUN__
        .word endlabel - label
        .word 0
        .word 0
        .word label - __LOWPACK_RUN__
        .word 0
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_LOW_ALL id, sig, label, name
        .byte id, RB_CMD_F_LOW
        .word 0
        .word __LOWPACK_SIZE__
        .word 0
        .word 0
        .word label - __LOWPACK_RUN__
        .word 0
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

.macro CMD_HIDDEN id, sig, label, endlabel, name
        .byte id, RB_CMD_F_HIDDEN
        .word 0
        .word 0
        .word (__HIDDENPACK_LOAD__ - __LOWPACK_LOAD__) + (label - __HIDDENPACK_RUN__)
        .word endlabel - label
        .word 0
        .word label - RB_HIDDEN_BASE
        .byte sig, .strlen(name)
        .byte name
        .res 16 - .strlen(name), 0
.endmacro

rb_command_descriptors:
        CMD_LOW CMD_PING, SIG_PING, cmd_ping_low, cmd_ping_low_end, "PING"
        CMD_LOW CMD_ADD16, SIG_ADD16, cmd_add16_low, cmd_add16_low_end, "ADD16"
        CMD_LOW CMD_STRUP, SIG_STRUP, cmd_strup_low, cmd_strup_low_end, "STRUP"
        CMD_HIDDEN CMD_HCRC, SIG_HCRC, cmd_hcrc_hidden, cmd_hcrc_hidden_end, "HCRC"
        CMD_LOW CMD_SUMAI, SIG_SUMAI, cmd_sumai_low, cmd_sumai_low_end, "SUMAI"
        CMD_LOW CMD_RANGEAI, SIG_RANGEAI, cmd_rangeai_low, cmd_rangeai_low_end, "RANGEAI"
        CMD_LOW_ALL CMD_BUFNEW, SIG_BUFNEW, cmd_bufnew_low, "BUFNEW"
        CMD_LOW_ALL CMD_BUFFILL, SIG_BUFFILL, cmd_buffill_low, "BUFFILL"
        CMD_LOW_ALL CMD_BUFFREE, SIG_BUFFREE, cmd_buffree_low, "BUFFREE"
        CMD_LOW_ALL CMD_TEMPSCRATCH, SIG_TEMPSCRATCH, cmd_tempscratch_low, "TEMPSCRATCH"
        CMD_LOW CMD_FAIL, SIG_FAIL, cmd_fail_low, cmd_fail_low_end, "FAIL"

; ---------------------------------------------------------------------------
; Hidden helper code, called by visible resident code with BASIC ROM hidden.
; ---------------------------------------------------------------------------

        .segment "HIDDEN"

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
        lda #<__LOWPACK_SIZE__
        sta rb_reu_len_lo
        lda #>__LOWPACK_SIZE__
        sta rb_reu_len_hi
        jsr rb_reu_stash

        lda #<__HIDDENPACK_LOAD__
        sta rb_reu_c64_lo
        lda #>__HIDDENPACK_LOAD__
        sta rb_reu_c64_hi
        lda #<(__HIDDENPACK_LOAD__ - __LOWPACK_LOAD__)
        sta rb_reu_off_lo
        lda #>(__HIDDENPACK_LOAD__ - __LOWPACK_LOAD__)
        sta rb_reu_off_hi
        lda #<__HIDDENPACK_SIZE__
        sta rb_reu_len_lo
        lda #>__HIDDENPACK_SIZE__
        sta rb_reu_len_hi
        jsr rb_reu_stash

        jsr rb_clear_handle_heap
        rts

rb_mark_reu_banks_hidden:
        lda #RB_REU_TYPE_CORE
        sta RB_REU_ALLOC_TABLE + RB_REU_CORE_BANK
        lda #RB_REU_TYPE_CODE
        sta RB_REU_ALLOC_TABLE + RB_REU_CODE_BANK
        rts

save_basic_runtime_state:
        tsx
        txa
        clc
        adc #4
        sta RUNTIME_SP
        ldx #0
@copy:
        lda $0000,x
        sta RUNTIME_ZP,x
        lda $0100,x
        sta RUNTIME_STACK,x
        inx
        bne @copy
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

; ---------------------------------------------------------------------------
; Bridge state only.  Code stays out of $C000 unless it must be resident there.
; ---------------------------------------------------------------------------

        .segment "BRIDGE"

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

rb_cmd_len:     .byte 0
rb_lookup_index:.byte 0
rb_target_off:  .byte 0
rb_saved_count_lo:.byte 0
rb_saved_count_hi:.byte 0

rb_out_type:    .byte 0
rb_out_count:   .byte 0
rb_out_ptr_lo:  .byte 0
rb_out_ptr_hi:  .byte 0
rb_out_count_lo:.byte 0
rb_out_count_hi:.byte 0

rb_overlay_vec_lo:.byte 0
rb_overlay_vec_hi:.byte 0

rb_reu_c64_lo:  .byte 0
rb_reu_c64_hi:  .byte 0
rb_reu_off_lo:  .byte 0
rb_reu_off_hi:  .byte 0
rb_reu_bank:    .byte 0
rb_reu_len_lo:  .byte 0
rb_reu_len_hi:  .byte 0

rb_handle_bank: .res RB_HANDLE_COUNT, 0
rb_handle_page: .res RB_HANDLE_COUNT, 0
rb_handle_pages:.res RB_HANDLE_COUNT, 0
rb_handle_type: .res RB_HANDLE_COUNT, 0
rb_page_bitmap: .res RB_HEAP_PAGES, 0
rb_handle_index:.byte 0
rb_needed_pages:.byte 0
rb_found_page:  .byte 0
rb_fill_page:   .byte 0
rb_debug_ring:  .res 32, 0

; ---------------------------------------------------------------------------
; Packed low overlay command implementations.  These are copied from REU bank
; $45 into $1C00-$23FF before call.
; ---------------------------------------------------------------------------

        .segment "LOWPACK"

cmd_ping_low:
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        lda #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
cmd_ping_low_end:

cmd_add16_low:
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
cmd_add16_low_end:

cmd_strup_low:
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
cmd_strup_low_end:

cmd_sumai_low:
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
cmd_sumai_low_end:

cmd_rangeai_low:
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
cmd_rangeai_low_end:

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

cmd_tempscratch_low:
        jsr rb_temp_alloc
        rts
cmd_tempscratch_low_end:

cmd_fail_low:
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
cmd_fail_low_end:

rb_handle_alloc:
        jsr rb_len_to_pages
        bcc @find_handle
        jmp rb_overlay_bad_length
@find_handle:
        ldx #0
@hloop:
        lda rb_handle_bank,x
        beq @got_handle
        inx
        cpx #RB_HANDLE_COUNT
        bcc @hloop
        lda #$21
        jmp rb_overlay_fail
@got_handle:
        stx rb_handle_index
        jsr rb_find_pages
        bcs @no_pages
        ldx rb_handle_index
        lda #RB_REU_CORE_BANK
        sta rb_handle_bank,x
        lda rb_found_page
        clc
        adc #$80
        sta rb_handle_page,x
        lda rb_needed_pages
        sta rb_handle_pages,x
        lda #1
        sta rb_handle_type,x
        jsr rb_mark_pages_used
        jsr rb_stash_handle_meta
        ldx rb_handle_index
        lda #0
        sta RF_STATUS
        lda #RB_VAL_INT
        sta RF_TAG
        txa
        clc
        adc #1
        sta RF_VAL_LO
        lda #0
        sta RF_VAL_HI
        rts
@no_pages:
        lda #$22
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

rb_find_pages:
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
        lda rb_page_bitmap,y
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
        sta rb_page_bitmap,y
        inx
        cpx rb_needed_pages
        bcc @loop
        rts

rb_handle_free:
        lda CF_NUM0_LO
        beq @bad
        cmp #RB_HANDLE_COUNT + 1
        bcs @bad
        sec
        sbc #1
        tax
        lda rb_handle_bank,x
        beq @bad
        stx rb_handle_index
        lda rb_handle_page,x
        sec
        sbc #$80
        sta rb_found_page
        lda rb_handle_pages,x
        sta rb_needed_pages
        jsr rb_mark_pages_free
        ldx rb_handle_index
        lda #0
        sta rb_handle_bank,x
        sta rb_handle_page,x
        sta rb_handle_pages,x
        sta rb_handle_type,x
        jsr rb_stash_handle_meta
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
        sta rb_page_bitmap,y
        inx
        cpx rb_needed_pages
        bcc @loop
        rts

rb_handle_fill:
        lda CF_NUM0_LO
        beq @bad
        cmp #RB_HANDLE_COUNT + 1
        bcs @bad
        sec
        sbc #1
        tax
        lda rb_handle_bank,x
        beq @bad
        stx rb_handle_index
        lda CF_NUM1_LO
        ldx #0
@fillbuf:
        sta RB_PAGEBUF,x
        inx
        bne @fillbuf
        ldx rb_handle_index
        lda rb_handle_page,x
        sta rb_fill_page
        lda rb_handle_pages,x
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

; ---------------------------------------------------------------------------
; Packed hidden overlay command implementations.  These are copied from REU
; bank $45 into RAM under BASIC ROM before call.
; ---------------------------------------------------------------------------

        .segment "HIDDENPACK"

cmd_hcrc_hidden:
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
cmd_hcrc_hidden_end:
