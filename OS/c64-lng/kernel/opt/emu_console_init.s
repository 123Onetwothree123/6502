;; for emacs: -*- MODE: asm; tab-width: 4; -*-

;; 6502 模拟器控制台初始化（替代 vic_console_init.s）
;; 无屏幕内存：只初始化驱动状态与 fs_cons 记账
;; 输出驱动见 opt/emu_console.s（字符写 $f001 UART）

#include <config.h>
#include <system.h>
#include MACHINE_H
#include <console.h>
#include <zp.h>

		;; initialise console driver
		;; (and set lk_consmax value)

console_init:
		lda  #1
		sta  lk_consmax			; exactly one console
		lda  #0
		sta  usage_count		; initialize fs_cons stuff
		sta  usage_map
		sta  current_output
		sta  cons_visible		; console 0 receives keyboard input
		sta  esc_flag
		sta  rvs_flag
		sta  scrl_y1
		lda  #$80
		sta  cflag				; cursor enabled (ignored by emu driver)
		lda  #24
		sta  scrl_y2

		;; print startup message
		ldx  #0
	-	lda  start_text,x
		beq  +
		jsr  lkf_printk
		inx
		bne  -

	+	rts

start_text:
		.text "EMU console (6502 simulator, UART $f001)",$0a,0
