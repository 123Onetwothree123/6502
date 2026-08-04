;
; readyirc_config.s - export hard-coded ReadyIRC defaults to C
;

        .export _readyirc_config_server
        .export _readyirc_config_channel
        .export _readyirc_config_nick
        .export _readyirc_config_port

        .include "readyirc_config.inc"
