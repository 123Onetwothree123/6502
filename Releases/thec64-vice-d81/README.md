# ReadyOS THEC64 D81 Experimental Staging

This folder is an experimental THEC64 Mini/Maxi staging copy for compatibility testing. It is not wired into the build.

Files:

- `readyos-v0.2.4-d81_M6TPRM.d81`
- `readyos-v0.2.4-d81_M6TPRM.cjm`

The filename flags request C64, PAL, and 16 MB REU:

- `M6` = C64
- `TP` = PAL
- `RM` = 16 MB REU

The CJM repeats the same baseline with `X:64,pal,reu16384`, adds explicit joystick mappings so THEC64 controllers remain active, and leaves accurate disk mode off because THEC64 documents `accuratedisk` as applying to `d64`/`g64`.
