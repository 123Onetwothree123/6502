#!/bin/bash
# 构建 6502 模拟器版 open-roms（MEGA65 开源 C64 KERNAL+BASIC 替代 ROM，generic 目标）
# 依赖: gcc, make, python3（汇编器 ACME 由 3rdparty/acme 现场编译）
# 可重复执行；中间文件全部在 build/ 下。
#
# 除本脚本的二进制补丁外，移植还包含源码级改动（构建时自动生效）：
# - src/,,config_generic.s: SHOW_FEATURES=NO、BANNER_SIMPLE=YES（为下方补丁腾空间）
# - src/basic/emu6502_intmath.s（新增）：整数运算基础设施（字面量解析、
#   FAC1/FAC2↔int16 转换、FRMEVL 浮点值入栈/出栈、变量读写、FOR 帧压栈）
# - src/basic/engine_runtime/frmevl.s: 接上整数字面量获取与浮点变量读取/压栈
# - src/basic/basic_operators/oper_mul.s, oper_add.s: 整数乘/加（上游为 stub）
# - src/basic/,stubs_math/aabc.print_FAC1.s: 整数子集实现（上游为 stub）
# - src/basic/basic_commands/cmd_print.s: cmd_print_float 接 print_FAC1
# - src/basic/basic_commands/cmd_for_next.s（新增）: 最小 FOR/NEXT
# - src/basic/engine_variables/assign_variable.s: assign_float(50K) 实现
set -e
cd "$(dirname "$0")/.."

# 1. 用上游 Makefile 构建 generic（最接近原版 C64 的纯 NMOS 6502 目标）
make -s build/kernal_generic.rom build/basic_generic.rom

# 2. 打模拟器适配补丁并拼装 64K 镜像
python3 - << 'PYEOF'
img = bytearray(0x10000)
basic  = open('build/basic_generic.rom','rb').read()
kernal = open('build/kernal_generic.rom','rb').read()
assert len(basic) == 8192 and len(kernal) == 8192
img[0xA000:0xBFFF+1] = basic
img[0xE000:0xFFFF+1] = kernal

def k(addr):  # KERNAL 地址 → 镜像偏移（与 $E000 基址相同，直接返回）
    return addr

# --- 补丁 1: CINT 尾部 jmp setup_pal_ntsc → 初始化 stub ---
# setup_pal_ntsc($FCB8) 在 VIC $D012 光栅寄存器上死等（本模拟器无 VIC，$D012 是静态 RAM）。
# 替换为跳转到 boot 初始化 stub（见补丁 4 后，置 STKEY=$FF 后 rts）。
# 原字节: 4C B8 FC @ $FF5E（前面是 jsr cint_legacy）
assert img[k(0xFF5E):k(0xFF61)] == bytes([0x4C, 0xB8, 0xFC]), 'CINT 补丁点字节不符'

# --- 补丁 2: STOP($F6ED) 恒返回"未按下" ---
# STKEY($91) 由 IRQ 键盘扫描维护；本移植无 IRQ，RAMTAS 清零后 STKEY=0
# 会被误判为 STOP 按下（每个 BASIC 语句都 BREAK）。
# 原: A5 91 (lda $91) → A9 FF (lda #$FF)，落入原有 lda #$FF; clc; rts 路径
# （BASIC 运行时还会直接读 STKEY，故另在 boot stub 里把 $91 置为 $FF，双保险）
assert img[k(0xF6ED):k(0xF6EF)] == bytes([0xA5, 0x91]), 'STOP 补丁点字节不符'
img[k(0xF6ED):k(0xF6EF)] = bytes([0xA9, 0xFF])

# --- 补丁 3: chrin_keyboard($F657) → UART 轮询输入 stub ---
# 无 CIA/IRQ，KERNAL 键盘缓冲永远为空；直接把键盘输入接到 $F000(状态)/$F001(取字符)。
# 契约：仅破坏 A/标志位（CHRIN 要求保持 X/Y），CLC 返回；含回显（终端无本地回显），CR 回显为 CR+LF。
emu_chrin = 0xF6F9  # ROM 内 181 字节空闲区起点（构建报告显示 still free: 181）
stub_in = bytes([
    0xAD, 0x00, 0xF0,       # F6F9 lda $F000   ; 输入状态
    0xF0, 0xFB,             #      beq -5      ; 无字符 → 继续轮询
    0xAD, 0x01, 0xF0,       #      lda $F001   ; 取字符（弹出队列）
    0x48,                   #      pha
    0xC9, 0x0D,             #      cmp #$0D
    0xF0, 0x07,             #      beq +7 → CR 回显路径
    0x8D, 0x01, 0xF0,       #      sta $F001   ; 回显普通字符
    0x68,                   #      pla
    0x18,                   #      clc
    0x60,                   #      rts
    0xEA,                   #      nop（对齐）
    0x8D, 0x01, 0xF0,       # cr:  sta $F001  ; CR
    0xA9, 0x0A,             #      lda #$0A
    0x8D, 0x01, 0xF0,       #      sta $F001   ; LF
    0x68,                   #      pla
    0x18,                   #      clc
    0x60,                   #      rts
])
assert img[k(0xF657):k(0xF65A)] == bytes([0x86, 0x97, 0x98]), 'chrin_keyboard 补丁点字节不符'
img[k(0xF657):k(0xF65A)] = bytes([0x4C, emu_chrin & 0xFF, emu_chrin >> 8])
img[emu_chrin:emu_chrin+len(stub_in)] = stub_in

# --- 补丁 4: chrout_screen($EDE2) → UART 输出 stub ---
# 无 VIC 屏幕，可打印字符写 $F001，CR 翻译为 CR+LF，其余控制码丢弃。
# 注意：chrout_screen 入口时 A=DFLTO，字符在 SCHAR($D7)（原例程先 jsr cursor_hide
# 再 lda SCHAR），stub 必须先 lda $D7！
# 从 CHROUT($F1CA) 经 beq 进入，返回必须走 chrout_done_success($F1F1) 恢复栈/寄存器。
emu_chrout = emu_chrin + len(stub_in)  # F718
stub_out = bytes([
    0xA5, 0xD7,             # F718 lda $D7    ; SCHAR —— 真正的输出字符
    0xC9, 0x0D,             #      cmp #$0D
    0xF0, 0x0E,             #      beq +0x0E → CR 路径
    0xC9, 0x20,             #      cmp #$20
    0x90, 0x07,             #      bcc +7 → done（控制码丢弃）
    0xC9, 0x80,             #      cmp #$80
    0xB0, 0x03,             #      bcs +3 → done（≥$80 丢弃）
    0x8D, 0x01, 0xF0,       #      sta $F001
    0x4C, 0xF1, 0xF1,       # done: jmp $F1F1 (chrout_done_success)
    0x8D, 0x01, 0xF0,       # cr:   sta $F001
    0xA9, 0x0A,             #       lda #$0A
    0x8D, 0x01, 0xF0,       #       sta $F001
    0x4C, 0xF1, 0xF1,       #       jmp $F1F1
])
assert img[k(0xEDE2):k(0xEDE5)] == bytes([0x20, 0xC5, 0xED]), 'chrout_screen 补丁点字节不符'
img[k(0xEDE2):k(0xEDE5)] = bytes([0x4C, emu_chrout & 0xFF, emu_chrout >> 8])
img[emu_chrout:emu_chrout+len(stub_out)] = stub_out

# --- 补丁 5: boot 初始化 stub（补丁 1 的跳转目标）---
# 无 IRQ 键盘扫描，STKEY($91) 永远是 RAMTAS 清零后的 0 → BASIC 直接读 $91 判 STOP
# 会误 BREAK；这里置 $FF 表示未按下。
boot_stub = emu_chrout + len(stub_out)
img[boot_stub:boot_stub+5] = bytes([0xA9, 0xFF, 0x85, 0x91, 0x60])  # lda #$FF; sta $91; rts
img[k(0xFF5E):k(0xFF61)] = bytes([0x4C, boot_stub & 0xFF, boot_stub >> 8])

# 说明：RAMTAS/IOINIT/RESTOR 无需补丁——本模拟器是全平 RAM，
# RAMTAS 的 $8000 写测能通过（MEMSIZK=$A000，38911 BASIC BYTES FREE），
# CIA/VIC/SID 寄存器写只是无害的 RAM 写。复位向量 $FCE2 由上游 ROM 自带。
# 已知残余风险：KERNAL $F000 落在磁带装载例程内（load_tape_normal_switch_turbo
# 区域），若执行磁带 LOAD 会在 $F000 取指时拿到 UART 状态——本移植不走磁带路径。

open('OPENROMS_EMU.bin','wb').write(img)
print('镜像: OPENROMS_EMU.bin')
PYEOF

echo "运行: /home/abc/6502/build/6502 OPENROMS_EMU.bin"
