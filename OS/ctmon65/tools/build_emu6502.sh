#!/bin/bash
# 构建 6502 模拟器版 CTMon65（CorshamTech/CTMon65，KIM 风格串口监控）
# 依赖: vasm（vasm6502_oldstyle）
#
# 适配点：
#   1. 上游用自家 basm/as65 汇编器，语法与 vasm oldstyle 接近，
#      但 bss/code/page/list 段伪指令不被支持，需剥掉（org 仍控制布局）。
#   2. io.asm 中标签 space 与 vasm 指令冲突（warning 41），改名为 xspace。
#   3. acia.asm 的 6850 ACIA 驱动换成模拟器终端：
#        cout    = STA $F001（写 stdout）
#        cin     = 读 $F000 自旋到 1，再读 $F001 取字符（阻塞）
#        cstatus = LDA $F000（Z=1 无字符）
#      并打开 -DNOECHO，由 CTMon65 自己回显（cinecho），
#      避免与模拟器终端的逐字符无回显模式重复。
#   4. 保留 SD_ENABLED=TRUE：SD/并口代码仅访问 $E060 附近的 6821 寄存器，
#      在模拟器里是无害 RAM 读写，避免关闭后大片符号未定义。
#   5. vasm -Fbin 输出从最低 org（$00F0 零页变量）开始，直接铺进
#      64KB 镜像的 $00F0 处；复位/中断向量已在源码 org $FFFA 处生成。
#   6. 源码为纯 NMOS 6502（无 65C02 指令），无需指令级修改。
set -e
cd "$(dirname "$0")/.."

BUILD=/tmp/ctmon65_emu_build
rm -rf "$BUILD"
mkdir -p "$BUILD"
cp ctmon65.asm acia.asm config.inc io.asm pario.asm parproto.inc diskfunc.asm "$BUILD/"

python3 - << 'PYEOF'
import re, os

BUILD = '/tmp/ctmon65_emu_build'

# 上游源文件含 Windows-1252 智能引号（0x92 等），用 latin-1 原样透传
def load(name):
    return open(os.path.join(BUILD, name), encoding='latin-1').read()

def save(name, s):
    open(os.path.join(BUILD, name), 'w', encoding='latin-1').write(s)

# ---- 1. 剥掉 vasm oldstyle 不支持的段/列表伪指令 ----
for name in ['ctmon65.asm', 'io.asm', 'acia.asm', 'pario.asm', 'diskfunc.asm', 'config.inc']:
    s = load(name)
    s2 = re.sub(r'^[ \t]*(bss|code|page|list)[ \t]*$', '', s, flags=re.M)
    save(name, s2)

# ---- 2. io.asm: 标签 space 与 vasm 指令冲突，改名 xspace ----
s = load('io.asm')
n = len(re.findall(r'\bspace\b', s))
assert n >= 3, 'io.asm 中未找到 space 标签'
s = re.sub(r'\bspace\b', 'xspace', s)
save('io.asm', s)
s = load('ctmon65.asm')
assert re.search(r'\bjsr[ \t]+space\b', s), 'ctmon65.asm 中未找到 jsr space'
s = re.sub(r'\bspace\b', 'xspace', s)
save('ctmon65.asm', s)

# ---- 3. acia.asm: 6850 ACIA -> 模拟器终端 $F000/$F001 ----
s = load('acia.asm')

old = '''cinit		lda	#%00000011	;reset
		sta	ACIA
		nop
		lda	#%00010001	;8N2
		sta	ACIA
		rts'''
new = '''cinit		rts			;emulator: nothing to init'''
assert old in s, '未找到 cinit'
s = s.replace(old, new, 1)

old = '''cout		pha
cout1		lda	ACIA
		and	#TDRE
		beq	cout1		;not empty
		pla
		sta	ACIA+1
		rts'''
new = '''cout		sta	$f001		;emulator stdout
		rts'''
assert old in s, '未找到 cout'
s = s.replace(old, new, 1)

old = '''cin		lda	ACIA
		and	#RDRF
		beq	cin
		lda	ACIA+1
		rts'''
new = '''cin		lda	$f000		;emulator input status
		beq	cin		;spin until a char is ready
		lda	$f001		;take the char
		rts'''
assert old in s, '未找到 cin'
s = s.replace(old, new, 1)

old = '''cstatus		lda	ACIA
		and	#RDRF
		rts'''
new = '''cstatus		lda	$f000		;Z set if no char ready
		rts'''
assert old in s, '未找到 cstatus'
s = s.replace(old, new, 1)

save('acia.asm', s)
print('文本补丁完成（段伪指令剥离 / space->xspace / ACIA->$F000-$F001）')
PYEOF

(cd "$BUILD" && vasm6502_oldstyle -Fbin -o ctmon65_raw.bin ctmon65.asm)

python3 - << 'PYEOF'
raw = open('/tmp/ctmon65_emu_build/ctmon65_raw.bin', 'rb').read()
BASE = 0x00F0   # vasm -Fbin 从最低 org（ZERO_PAGE_START）开始
assert len(raw) == 0x10000 - BASE, 'raw 大小异常: %x' % len(raw)

img = bytearray(0x10000)
img[BASE:BASE+len(raw)] = raw

# 向量由源码 org $FFFA 生成， sanity check：复位向量必须落在 $F000-$FFFF 代码区
rst = img[0xFFFC] | (img[0xFFFD] << 8)
assert 0xF000 <= rst, '复位向量异常: %04x' % rst
print('复位向量: $%04X  NMI: $%04X  IRQ/BRK: $%04X' % (
    rst,
    img[0xFFFA] | (img[0xFFFB] << 8),
    img[0xFFFE] | (img[0xFFFF] << 8)))

open('CTMON65_EMU.bin', 'wb').write(img)
print('镜像: CTMON65_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 CTMON65_EMU.bin"
