; llvm-mos 平台 crt0 —— 6502 模拟器
; 初始化链：.init.100(硬件栈) → .init.200(清BSS) → .call_main(main)
; → .after_main(exit) → _Exit(BRK 停机，模拟器视为陷阱)

; --- 初始化栈指针：__stack 在链接脚本里定义为 $01FF ---
; 硬件栈（SP）和软栈（c_sp = $00/$01）都指向它
.section .init.100,"ax",@progbits
.global __do_init_stack
__do_init_stack:
  ldx #mos16lo(__stack)
  txs
  lda #mos16lo(__stack)
  sta __rc0
  lda #mos16hi(__stack)
  sta __rc1

.zeropage __rc0, __rc1

; --- 清零 BSS（__bss_start / __bss_size 由链接脚本提供） ---
.section .init.200,"ax",@progbits
.global __do_zero_bss
__do_zero_bss:
  lda #0
  tay
  ldx #mos16hi(__bss_size)
  beq page_done
page_loop:
  sta __bss_start, y
  iny
  bne page_loop
  inc __bss_start + 1
  dex
  bne page_loop
  ldy #0
page_done:
  ldx #mos16lo(__bss_size)
  beq call_main
tail_loop:
  sta __bss_start, y
  iny
  dex
  bne tail_loop
; .init 链是顺序执行的（_start 不 jsr），不能在这里 rts，
; 直接落入 .call_main

; --- 调用 main() ---
.section .call_main,"ax",@progbits
call_main:
  jsr main

; --- main 返回后进入 _Exit（BRK 停机；平台输出无缓冲，无需 flush） ---
.section .after_main,"ax",@progbits
.global __after_main
__after_main:
  jmp _Exit

; --- 平台 _Exit：BRK 让模拟器停机 ---
.section .text._Exit,"ax",@progbits
.global _Exit
_Exit:
  brk
