;; for emacs: -*- MODE: asm; tab-width: 4; -*-

;; 6502 模拟器键盘驱动（替代 c64/keyboard.s 的 CIA 矩阵扫描）
;; 由 IRQ 任务链周期调用：
;;   读 $f000 = 输入状态（0=无字符，1=有字符）
;;   读 $f001 = 取出一个字符
;; UART 直接提供 ASCII，无需扫描码转换表；
;; 字符交给 keyboard.s 公共部分的 _addkey 进入控制台输入缓冲。

		.global keyb_scan

;; 公共部分（_queue_key/_addkey）引用这些表；
;; emu 路径不走 _queue_key，表仅用于链接完整。
locktab:
		.byte keyb_alt, keyb_ex1, keyb_ex2, keyb_ex3
_keytab_normal:
_keytab_shift:
		.byte 0

keyb_scan:
		lda  $f000			; 有输入？
		beq  _nokey
		lda  $f001			; 取字符
		cmp  #$0d			; CR -> LF（LUnix 行输入以 $0a 结束）
		bne  _gotkey
		lda  #$0a
_gotkey:
		jmp  _addkey
_nokey:
		rts
