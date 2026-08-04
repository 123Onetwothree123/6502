;
; cc65 crt0 —— 6502 模拟器
; 参考 libsrc/sim6502/crt0.s，去掉 sim65 专用的 c_sp（本机硬件栈固定 $0100-$01FF）
; 程序结束后执行 BRK，模拟器把 BRK 当作停机陷阱
;

        .export         _exit
        .export         startup
        .export         __STARTUP__ : absolute = 1      ; 标记为启动模块
        .import         zerobss, callmain
        .import         initlib, donelib
        .include        "zeropage.inc"

; 软栈指针符号：cc65 2.19+ 叫 c_sp，2.18 叫 sp
.ifdef c_sp
.define STACKPTR c_sp
.else
.define STACKPTR sp
.endif

        .segment        "STARTUP"

startup:
        cld
        ldx     #$FF
        txs                             ; 硬件栈顶 $01FF
        lda     #$FF
        sta     STACKPTR
        sta     STACKPTR+1              ; 软栈顶 $FFFF（向下生长）
        jsr     zerobss                 ; 清零 BSS
        jsr     initlib                 ; 运行构造函数
        jsr     callmain                ; 调用 main()
_exit:
        jsr     donelib                 ; 运行析构函数
        brk                             ; 停机陷阱（A 寄存器 = main 返回值）

        .segment        "VECTORS"

        .word   $0000                   ; $FFFA NMI
        .word   startup                 ; $FFFC RESET
        .word   $0000                   ; $FFFE IRQ/BRK
