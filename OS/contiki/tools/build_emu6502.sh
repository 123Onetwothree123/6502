#!/bin/bash
# 构建 6502 模拟器版 Contiki 程序
# 用法: ./tools/build_emu6502.sh <项目目录> [输出镜像名]
# 例:   ./tools/build_emu6502.sh examples/hello-world HELLO_EMU.bin
# 依赖: cc65（AUR: cc65-git）
set -e
cd "$(dirname "$0")/.."

PROJ="${1:-examples/hello-world}"
OUT="${2:-HELLO_EMU.bin}"
NAME=$(basename "$PROJ")

cd "$PROJ"
make TARGET=c64 CONTIKI_WITH_IPV4=1 \
  LDFLAGS="-t c64 -m contiki-c64.map -D __STACKSIZE__=0x200 -D __HIMEM__=0xFF00"
cd ../..

python3 - "$PROJ" "$OUT" << PYEOF
import os, re, sys
proj, out = sys.argv[1], sys.argv[2]

def load(f, addr, img, strip_header=True):
    d = open(f, 'rb').read()
    if strip_header:
        d = d[2:]
    img[addr:addr+len(d)] = d

def find_sym(mapfile, name):
    with open(mapfile) as f:
        for line in f:
            m = re.search(rf'\b{name}\s+([0-9A-Fa-f]{{6}})', line)
            if m:
                return int(m.group(1), 16)
    return None

mapf = f"{proj}/contiki-c64.map"
config_read = find_sym(mapf, '_config_read')
eth_init = find_sym(mapf, '_ethernet_init')
eth_poll = find_sym(mapf, '_ethernet_poll')

img = bytearray(0x10000)
import glob
c64s = glob.glob(f'{proj}/*.c64')
if not c64s:
    raise SystemExit(f'{proj}: 没有 .c64 产物')
load(sorted(c64s)[0], 0x0801, img)
img[0xFFFC:0xFFFE] = bytes([0x0D, 0x08])          # RESET -> crt0

def stub(addr, code):
    for i, b in enumerate(code):
        img[addr + i] = b

# 周期定时器 IRQ（模拟器 IRQ_INTERVAL 环境变量触发）
# 模拟真 C64 UDTIM：$A2=LSD 每 jiffy 递增，$A1 中位，$A0=MSD（与 KERNAL 及 cc65 clock() 约定一致；
# 注意分支偏移：BNE 必须跳到最后的 RTI，偏移错 2 会导致 $A2 每拍多 INC 一次）
stub(0xFF00, [0xE6, 0xA2, 0xD0, 0x06, 0xE6, 0xA1, 0xD0, 0x02, 0xE6, 0xA0, 0x40])  # IRQ: jiffy++
stub(0xFFFE, [0x00, 0xFF])                       # IRQ 向量 -> $FF00
stub(0xFFDE, [0x4C, 0x26, 0xF2])                 # RDTIM -> jmp $F226（原子版）
# RDTIM（$F226-$F22E）：与真 KERNAL 一致 SEI/CLI 原子读，A=$A2(LSD) X=$A1 Y=$A0(MSD)
stub(0xF226, [0x78, 0xA5, 0xA2, 0xA6, 0xA1, 0xA4, 0xA0, 0x58, 0x60])
# KERNAL stub
stub(0xFFD2, [0x4C, 0x00, 0xF2])                 # CHROUT -> jmp $F200（PETSCII->ASCII）
# PETSCII->ASCII 转换例程（$F200-$F225，cc65 c64 目标编译期把字符串转成 PETSCII：
# 小写=$41-$5A、大写=$C1-$DA，另有字符集切换码 $0E/$8E）。入口 A=字符，X/Y 不动，A 经 PHA/PLA 恢复。
stub(0xF200, [
    0x48,                    # PHA
    0xC9, 0x0E, 0xF0, 0x1F,  # CMP #$0E / BEQ done   （$0E 丢弃）
    0xC9, 0x8E, 0xF0, 0x1B,  # CMP #$8E / BEQ done   （$8E 丢弃）
    0xC9, 0x41, 0x90, 0x14,  # CMP #$41 / BCC out    （<$41 原样）
    0xC9, 0x5B, 0x90, 0x0D,  # CMP #$5B / BCC lower  （$41-$5A: +$20）
    0xC9, 0xC1, 0x90, 0x0C,  # CMP #$C1 / BCC out    （$5B-$C0 原样）
    0xC9, 0xDB, 0xB0, 0x08,  # CMP #$DB / BCS out    （>=$DB 原样）
    0x38, 0xE9, 0x80,        # SEC / SBC #$80        （$C1-$DA: -$80）
    0xD0, 0x03,              # BNE out
    0x18, 0x69, 0x20,        # lower: CLC / ADC #$20
    0x8D, 0x01, 0xF0,        # out: STA $F001
    0x68,                    # done: PLA
    0x60,                    # RTS
])
stub(0xFFCF, [0x4C, 0xEB, 0xFF])                 # CHRIN -> $FFEB
stub(0xFFE5, [0x4C, 0xEB, 0xFF])                 # GETIN -> $FFEB
stub(0xFFEB, [0xAD, 0x0B, 0xFF, 0xF0, 0x05, 0xCE, 0x0B, 0xFF, 0xA9, 0x20, 0x60, 0xA9, 0x0D, 0x60])  # 先空格后换行
img[0xFF0B] = 0x01                              # CHRIN 计数器（勿用 $FF01：与 IRQ stub 操作数冲突）
stub(0xFFBA, [0x60])                             # SETNAM
stub(0xFFBD, [0x60])                             # SETLFS
stub(0xFFC0, [0x18, 0xA9, 0x00, 0x60])           # OPEN: 成功
stub(0xFFC3, [0x60])                             # CLOSE
stub(0xFFC6, [0x60])                             # CHKIN
stub(0xFFC9, [0x60])                             # CHKOUT
stub(0xFFCC, [0x60])                             # CLRCHN
stub(0xFFB7, [0xA9, 0x00, 0x60])                 # 字节写成功

# cc65 库级 patch（所有程序通用）
img[0x0836:0x0839] = bytes([0x4C, 0x7C, 0x08])   # crt0 尾部 -> jmp main（无 BASIC）
img[0x3A2A:0x3A2D] = bytes([0xA9, 0x00, 0x60])   # open 设备就绪检查通过
if config_read:
    img[config_read] = 0x60                      # config_read -> rts（无磁盘）
if eth_init:
    img[eth_init] = 0x60                         # ethernet_init -> rts（无网卡）
if eth_poll:
    img[eth_poll] = 0x60                         # ethernet_poll -> rts（无网卡）

open(out, 'wb').write(img)
print(f'镜像: {out}')
PYEOF
echo "运行: IRQ_INTERVAL=30000 /home/abc/6502/build/6502 $OUT"
