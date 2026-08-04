;
; 6502 模拟器平台层：UART 输出钩子 _write
;
; int _write(int fd, const void *buf, unsigned count)
;
; 注意：不能用 C 实现！cc65 编译器生成的 cdecl 函数会自己清理参数栈
; （addysp），但库里的 fwrite.s 调用 _write 时约定"参数留在栈上"（调用者
; 清理），两边冲突会导致栈错乱。所以必须用汇编，只读不清理。
;
; 进入时栈布局（c_sp 为软栈指针，cc65 从右到左压参，实测）：
;   c_sp+0/1: buf, c_sp+2/3: fd, c_sp+4/5: count
; 返回：A/X = 写入字节数（成功）或 $FFFF（失败）
;

        .export         _write
        .importzp       ptr1, ptr2
        .include        "zeropage.inc"

; 软栈指针符号：cc65 2.19+ 叫 c_sp，2.18 叫 sp
.ifdef c_sp
.define STACKPTR c_sp
.else
.define STACKPTR sp
.endif

        .segment        "CODE"

_write:
        ldy     #$03
        lda     (STACKPTR),y            ; fd 高字节
        bne     @bad
        dey
        lda     (STACKPTR),y            ; fd 低字节
        cmp     #$01
        bne     @bad

        ldy     #$01
        lda     (STACKPTR),y            ; buf 高字节
        sta     ptr1+1
        dey
        lda     (STACKPTR),y            ; buf 低字节
        sta     ptr1

        ldy     #$05
        lda     (STACKPTR),y            ; count 高字节
        sta     ptr2+1
        dey
        lda     (STACKPTR),y            ; count 低字节
        sta     ptr2

        lda     ptr2+1
        bne     @go
        lda     ptr2
        bne     @go
        jmp     @ret                ; count == 0

@go:
        ldy     #$00
@loop:
        lda     (ptr1),y
        sta     $F001               ; UART：模拟器输出到终端
        inc     ptr1
        bne     @skip
        inc     ptr1+1
@skip:
        lda     ptr2
        bne     @dec
        dec     ptr2+1
@dec:
        dec     ptr2
        lda     ptr2+1
        bne     @loop
        lda     ptr2
        bne     @loop

@ret:
        ldy     #$05

        tax
        dey
        lda     (STACKPTR),y            ; A/X = count
        rts
@bad:
        ldx     #$FF
        lda     #$FF                ; 返回 -1
        rts
