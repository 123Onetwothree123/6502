#!/bin/bash
# 构建 6502 模拟器版 JMON（jefftranter/6502 仓库的 JMON 监控程序，SBC 平台）
# 依赖: ca65/ld65（cc65，/usr/sbin）
set -e
cd "$(dirname "$0")/.."

BUILD=/tmp/jmon_emu_build
rm -rf "$BUILD"
mkdir -p "$BUILD"
cp asm/jmon/*.s "$BUILD/"

# 文本补丁：ROM 版起始地址 $E100 改为 $2000（RAM），
# 避免代码与放在 $FF3B/$FF4A 的模拟器 I/O 桩冲突。
python3 - << 'PYEOF'
s = open('/tmp/jmon_emu_build/jmon.s').read()
old = '  .org $E100                    ; For running from ROM'
new = '  .org $2000                    ; Emulator build: run from RAM'
assert old in s, '未找到 .org $E100'
s = s.replace(old, new, 1)
open('/tmp/jmon_emu_build/jmon.s', 'w').write(s)
print('源码补丁完成（.org $E100 -> $2000）')
PYEOF

# -DMINIASM 启用内置迷你汇编器（A 命令），上游 Makefile 默认未开；
# miniasm.s 无条件引用 65C02 寻址模式常量，故需 -DD65C02（仅扩充反汇编/汇编表，
# JMON 本身仍是纯 NMOS 6502 代码）
(cd "$BUILD" && ca65 -DSBC -DMINIASM -DD65C02 -g -l jmon.lst jmon.s -o jmon.o)
ld65 -C /usr/share/cc65/cfg/none.cfg -vm -m "$BUILD/jmon.map" -o "$BUILD/jmon.bin" "$BUILD/jmon.o"

python3 - << 'PYEOF'
code = open('/tmp/jmon_emu_build/jmon.bin', 'rb').read()
ORG = 0x2000
assert len(code) < 0x7FC0 - ORG, '代码与变量区 $7FC0 重叠'
img = bytearray(0x10000)
img[ORG:ORG+len(code)] = code

# ---- I/O 桩（SBC 平台约定：MONCOUT=$FF3B, MONRDKEY=$FF4A）----
# MONCOUT: 输出 A 中字符
img[0xFF3B:0xFF3F] = bytes([0x8D, 0x01, 0xF0, 0x60])  # STA $F001; RTS
# MONRDKEY: 实时轮询版。调用方（jmon.s 的 WaitForKeypress）是
#   JSR MONRDKEY / BCC WaitForKeypress，即轮询语义：carry=0 无键，
#   carry=1 有键且字符在 A，自旋等待由调用方负责，桩本身不阻塞。
# 新硬件约定：读 $F000 = 输入状态（0/1），读 $F001 = 取出一个字符。
# 只用 A 寄存器，满足 GetKey "Registers changed: A" 的约定。
stub = bytes([
    0xAD, 0x00, 0xF0,       # LDA $F000   ; 输入状态
    0xF0, 0x05,             # BEQ nokey   ; 无字符
    0xAD, 0x01, 0xF0,       # LDA $F001   ; 取出字符
    0x38,                   # SEC         ; carry=1 表示有键
    0x60,                   # RTS
    0x18,                   # nokey: CLC
    0x60,                   # RTS
])
img[0xFF4A:0xFF4A+len(stub)] = stub

# ---- 向量 ----
img[0xFFFC] = ORG & 0xFF; img[0xFFFD] = ORG >> 8   # 复位 -> JMON
img[0xFFFE] = ORG & 0xFF; img[0xFFFF] = ORG >> 8   # BRK/IRQ（模拟器随后停机）

open('JMON_EMU.bin', 'wb').write(img)
print('镜像: JMON_EMU.bin（实时 stdin 输入）')
PYEOF
echo "运行: /home/abc/6502/build/6502 JMON_EMU.bin"
