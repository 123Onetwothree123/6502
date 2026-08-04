;; 6502 模拟器控制台驱动
;; 字符直接输出到 $F001 UART（替代 VIC 屏幕）
;; 提供 vic_console.s 的全部接口，光标/滚动/多控制台全部空操作

#include <config.h>
#include <system.h>
#include MACHINE_H
#include <zp.h>
#include <console.h>

		.global cons_regbuf
		.global cons_home
		.global cons_clear
		.global cons_out
		.global cons_setpos
		.global cons_setpos_sane
		.global cons_csrup
		.global cons_csrdown
		.global cons_csrleft
		.global cons_csrright
		.global cons_scroll_up
		.global cons_reu_scrollscr
		.global cons_showcsr
		.global cons_hidecsr
		.global cons_updatecsr
		.global cons_loadstat
		.global cons_savestat
		.global cons_a2p
		.global console_toggle

		;; zeropage assignments（mkzp_h 解析，分配零页）
;;; ZEROpage: sbase 1
;;; ZEROpage: cchar 1
;;; ZEROpage: current_output 1
;;; ZEROpage: cons_visible 1
;;; ZEROpage: mapl 1
;;; ZEROpage: maph 1
;;; ZEROpage: csrx 1
;;; ZEROpage: csry 1
;;; ZEROpage: buc 1
;;; ZEROpage: cflag 1
;;; ZEROpage: rvs_flag 1
;;; ZEROpage: scrl_y1 1
;;; ZEROpage: scrl_y2 1
;;; ZEROpage: esc_flag 1
;;; ZEROpage: esc_parcnt 1

cons_regbuf:
		.word 0

;; 输出一个字符到 $F001 UART（A=char, X=console号）
cons_out:
		pha
		sta  $F001
		pla
		rts

console_toggle:
		rts
cons_home:
cons_clear:
cons_setpos:
cons_setpos_sane:
cons_csrup:
cons_csrdown:
cons_csrleft:
cons_csrright:
cons_scroll_up:
cons_reu_scrollscr:
cons_showcsr:
cons_hidecsr:
cons_updatecsr:
cons_loadstat:
cons_savestat:
cons_a2p:
		rts
