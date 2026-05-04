;
; sysinfo_uci_asm.s - tiny UCI register accessors for System Info
;

        .export _sysinfo_uci_asm_write_cmd
        .export _sysinfo_uci_asm_id
        .export _sysinfo_uci_asm_status
        .export _sysinfo_uci_asm_read_data
        .export _sysinfo_uci_asm_read_stat
        .export _sysinfo_uci_asm_push_cmd
        .export _sysinfo_uci_asm_accept_data
        .export _sysinfo_uci_asm_abort
        .export _sysinfo_uci_asm_clear_error
        .export _sysinfo_rom_asm_read_basic
        .export _sysinfo_rom_asm_read_chargen
        .export _sysinfo_rom_asm_read_kernal

UCI_CONTROL = $DF1C
UCI_STATUS  = $DF1C
UCI_COMMAND = $DF1D
UCI_ID      = $DF1D
UCI_DATA    = $DF1E
UCI_STAT    = $DF1F
CPU_PORT    = $0001

_sysinfo_uci_asm_write_cmd:
        sta UCI_COMMAND
        rts

_sysinfo_uci_asm_id:
        lda UCI_ID
        rts

_sysinfo_uci_asm_status:
        lda UCI_STATUS
        rts

_sysinfo_uci_asm_read_data:
        lda UCI_DATA
        rts

_sysinfo_uci_asm_read_stat:
        lda UCI_STAT
        rts

_sysinfo_uci_asm_push_cmd:
        lda #$01
        sta UCI_CONTROL
        rts

_sysinfo_uci_asm_accept_data:
        lda #$02
        sta UCI_CONTROL
        rts

_sysinfo_uci_asm_abort:
        lda #$04
        sta UCI_CONTROL
        rts

_sysinfo_uci_asm_clear_error:
        lda #$08
        sta UCI_CONTROL
        rts

_sysinfo_rom_asm_read_basic:
        sta read_basic+1
        txa
        clc
        adc #$A0
        sta read_basic+2
        php
        sei
        lda CPU_PORT
        pha
        ora #$03
        sta CPU_PORT
read_basic:
        lda $A000
        tax
        pla
        sta CPU_PORT
        plp
        txa
        rts

_sysinfo_rom_asm_read_chargen:
        sta read_chargen+1
        txa
        clc
        adc #$D0
        sta read_chargen+2
        php
        sei
        lda CPU_PORT
        pha
        ora #$03
        and #$FB
        sta CPU_PORT
read_chargen:
        lda $D000
        tax
        pla
        sta CPU_PORT
        plp
        txa
        rts

_sysinfo_rom_asm_read_kernal:
        sta read_kernal+1
        txa
        clc
        adc #$E0
        sta read_kernal+2
        php
        sei
        lda CPU_PORT
        pha
        ora #$02
        sta CPU_PORT
read_kernal:
        lda $E000
        tax
        pla
        sta CPU_PORT
        plp
        txa
        rts
