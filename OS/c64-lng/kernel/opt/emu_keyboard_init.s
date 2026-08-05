;; for emacs: -*- MODE: asm; tab-width: 4; -*-

;; 6502 模拟器键盘初始化（替代 c64/keyboard_init.s）
;; 把 UART 轮询例程挂进 IRQ 任务链；不触碰 CIA 端口。

#include <config.h>
#include <system.h>
#include MACHINE_H
#include <keyboard.h>

		;; initialize and install keyboard scanning routine
keyboard_init:
		ldx  #<lkf_keyb_scan
		ldy  #>lkf_keyb_scan
		jsr  lkf_hook_irq		; hook into system
		ldx  #0
	-	lda  _startmsg,x
		beq  +
		jsr  lkf_printk
		inx
		bne  -
	+	rts

_startmsg:
		.text "EMU-Keyboard module (UART $f000/$f001)"
		.byte $0a,$00
