#!/bin/bash
# 构建 6502 模拟器版 atari64（C64 KERNAL 移植）
# 依赖: dasm, python3
set -e
cd "$(dirname "$0")/.."
bash build.sh >/dev/null 2>&1
python3 - << 'PYEOF'
img = bytearray(0x10000)
img[0xA000:0xA000+8192] = open('rom.a000','rb').read()
img[0xD800:0xD800+10240] = open('rom.d800','rb').read()
# RAMTAS: 跳过 $0300-$03FF 清零（否则会毁掉 $0334 自动输入钩子和 $036B 表）
img[0xFA31:0xFA34] = bytes([0xEA, 0xEA, 0xEA])
# RAMTAS: 跳过内存检测，直接设顶：LDA #$A0; STA $C2; JMP $FA66 (bSIZE → SETTOP/MEMSTR/HIBASE)
img[0xFA40:0xFA47] = bytes([0xA9, 0xA0, 0x85, 0xC2, 0x4C, 0x66, 0xFA])
for i in range(0xFA47, 0xFA66): img[i] = 0xEA
img[0xF9E5:0xF9E8] = bytes([0x6C, 0x00, 0xA0])
img[0xEAA6:0xEAA9] = bytes([0x4C, 0x1C, 0xEB])
img[0xE614:0xE616] = bytes([0xEA, 0xEA])
img[0xE617:0xE61B] = bytes([0xEA, 0xEA, 0xEA, 0xEA])
img[0xE61B:0xE61E] = bytes([0x4C, 0x34, 0x03])
# $0334 自动输入钩子（一次性）：flag=$0375=1 后不再重复填充，缓冲空时 BRK 结束演示
# 表为 PETSCII；CR 走 $E627（移位+回车处理，不回显到屏幕）；其余走 $E620（回显+PRT 推进光标）
plat = bytes([
    0xAD, 0x75, 0x03,             # LDA $0375   ; 已填充过?
    0xF0, 0x11,                   # BEQ +0x11   ; 否 → 填充路径
    0xAD, 0x77, 0x02,             # LDA $0277   ; 缓冲还有字符?
    0xF0, 0x0A,                   # BEQ +0x0A   ; 空 → 演示结束
    0xC9, 0x0D,                   # CMP #$0D    ; 回车?
    0xF0, 0x03,                   # BEQ +0x03   ; 是 → CR 路径
    0x4C, 0x20, 0xE6,             # JMP $E620   ; 处理字符（DSPP 回显+PRT）
    0x4C, 0x27, 0xE6,             # JMP $E627   ; CR：JSR $E5F4 移缓冲→回车处理
    0x00, 0x00,                   # BRK BRK     ; 演示结束 → 停机
    0xAD, 0x77, 0x02,             # LDA $0277   ; 填充路径：缓冲忙?
    0xD0, 0xF3,                   # BNE -0x0D   ; 是 → 处理字符
    0xA9, 0x01,                   # LDA #$01
    0x8D, 0x75, 0x03,             # STA $0375   ; 置一次性标志
    0xA2, 0x00,                   # LDX #$00
    0xBD, 0x6B, 0x03,             # LDA $036B,X ; 填 "PRINT 7*6\r"（PETSCII）
    0x9D, 0x77, 0x02,             # STA $0277,X
    0xE8,                         # INX
    0xE0, 0x0A,                   # CPX #$0A
    0xD0, 0xF5,                   # BNE -0x0B
    0xA9, 0x0A,                   # LDA #$0A
    0x85, 0xC6,                   # STA $C6     ; 缓冲计数=10（E5F4 移位循环依赖它）
    0xAD, 0x77, 0x02,             # LDA $0277   ; 取第一个字符
    0x4C, 0x20, 0xE6])            # JMP $E620   ; 处理第一个字符
img[0x0334:0x0334+len(plat)] = plat
table = b'PRINT 7*6\r'
img[0x036B:0x036B+len(table)] = table
# PRT 输出镜像到 $F001 UART（运行期屏幕渲染）：E756 → JMP $FB9D（$FF 填充区内的 stub）
img[0xE756:0xE759] = bytes([0x4C, 0x9D, 0xFB])
uart_stub = bytes([0x48, 0x85, 0xD7,           # PHA; STA $D7
                   0xC9, 0x0D,                 # CMP #$0D
                   0xF0, 0x12,                 # BEQ +0x12 ; CR → CR+LF
                   0x30, 0x0D,                 # BMI +0x0D ; ≥0x80 跳过
                   0xC9, 0x20,                 # CMP #$20
                   0x90, 0x09,                 # BCC +0x09 ; <0x20 跳过
                   0x8D, 0x01, 0xF0,           # STA $F001 ; 可打印 → UART
                   0x4C, 0x59, 0xE7,           # JMP $E759
                   0xEA, 0xEA, 0xEA,
                   0x4C, 0x59, 0xE7,           # 跳过路径
                   0x8D, 0x01, 0xF0,           # CR
                   0xA9, 0x0A,                 # LF
                   0x8D, 0x01, 0xF0,
                   0x4C, 0x59, 0xE7])          # 回原 PRT
img[0xFB9D:0xFB9D+len(uart_stub)] = uart_stub
# $ECEC 保持原内容（行地址表/自动输入表，勿改）
img[0xFFFC] = 0xD3; img[0xFFFD] = 0xF9
img[0xFFFA] = 0x3C; img[0xFFFB] = 0xFB
img[0xFFFE] = 0x84; img[0xFFFF] = 0xFB
open('ATARI64_EMU.bin','wb').write(img)
print('镜像: ATARI64_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 ATARI64_EMU.bin"
