# ReadyOS THEC64 EasyFlash Experimental Staging

This folder is an experimental THEC64 Mini/Maxi staging copy for compatibility testing. It is not wired into the build.

Files:

- `readyos_easyflash_M6TPRM.crt`
- `readyos_easyflash_M6TPRM.cjm`
- `readyos_data.d64`

The filename flags request C64, PAL, and 16 MB REU:

- `M6` = C64
- `TP` = PAL
- `RM` = 16 MB REU

The CJM repeats the same baseline with `X:64,pal,reu16384` and adds explicit joystick mappings so THEC64 controllers remain active. `readyos_data.d64` is included beside the cartridge for runtime app data access; the CJM cannot auto-mount it.
