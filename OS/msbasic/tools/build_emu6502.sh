#!/bin/bash
# 构建 6502 模拟器版 Microsoft BASIC（mist64/msbasic，OSI 配置）
# 依赖: ca65/ld65（/usr/sbin）、python3
# 思路：
#   1. 直接用上游 make.sh 的 osi 目标构建（纯 NMOS 6502，.setcpu "6502" 保证无 65C02 指令）。
#   2. OSI 版 BASIC 通过 OSI ROM 监控入口做 I/O：
#        MONCOUT  = $FFEE  字符输出（A=字符，需保护 A/X/Y）
#        MONRDKEY = $FFEB  阻塞式字符输入（A=字符）
#        MONISCNTC= $FFF1  Ctrl-C 检测（A bit0=1 表示有键按下）
#      本脚本在 $FE00-$FFFF 生成一个假的"监控 ROM"：
#        MONCOUT  -> sta $F001（模拟器 stdout），其余寄存器不动
#        MONRDKEY -> 先放完一小段罐头前缀（$FE80 计数器 + $FE90 表），
#                    然后切换为实时输入：轮询 $F000 直到为 1，再读 $F001 取字符
#        MONISCNTC-> lda #$00 / rts（永远无键，程序循环不会被打断）
#   3. 罐头前缀只回答启动两问：MEMORY SIZE=40960 跳过 RAM 自检——
#      模拟器是完整 64KB RAM，自检永远不会失败而死循环并 scribble BASIC 自身；
#      TERMINAL WIDTH 回车用默认 72。之后所有输入来自模拟器 stdin（终端或管道）。
set -e
cd "$(dirname "$0")/.."

TMP=/tmp/msbasic_emu
mkdir -p "$TMP"

/usr/sbin/ca65 -D osi msbasic.s -o "$TMP/osi.o"
/usr/sbin/ld65 -C osi.cfg "$TMP/osi.o" -o "$TMP/osi.bin" -Ln "$TMP/osi.lbl"

python3 - << 'PYEOF'
import re

# 从 ld65 符号表取 COLD_START 地址作为复位入口
cold = None
for line in open('/tmp/msbasic_emu/osi.lbl'):
    m = re.match(r'al\s+([0-9A-Fa-f]{6})\s+\.COLD_START\b', line)
    if m:
        cold = int(m.group(1), 16) & 0xFFFF
        break
assert cold, 'COLD_START 未找到'
print('COLD_START = $%04X' % cold)

basic = open('/tmp/msbasic_emu/osi.bin', 'rb').read()
assert len(basic) <= 0x5E00, 'BASIC 与 $FE00 监控 stub 冲突'
img = bytearray(0x10000)
img[0xA000:0xA000 + len(basic)] = basic   # osi.cfg: BASROM start = $A000

# ---- 假监控 ROM，$FE00-$FE9F + $FFEB-$FFFF ----
CANIN   = 0xFE00
CANIDX  = 0xFE80   # 启动罐头前缀读指针（BASIC 不会碰这一页）
SAVEX   = 0xFE81
CANTBL  = 0xFE90

# 罐头前缀：只自动回答启动两问。
# MEMORY SIZE 直接回车会触发 RAM 探测写测试，在 64KB 全 RAM 的
# 模拟器上永不失败而死循环并 scribble BASIC 自身，故必须回答 40960。
prefix = b'40960\r\r'   # MEMORY SIZE=$A000；TERMINAL WIDTH=默认 72
assert len(prefix) < 256

stub = []
def e(*bs):
    stub.extend(bs)
# CANIN: 前缀未用完 -> 查表返回；用完 -> 轮询模拟器 stdin。返回值在 A，保护 X/Y
e(0x8E, SAVEX & 0xFF, SAVEX >> 8)     # stx SAVEX
e(0xAE, CANIDX & 0xFF, CANIDX >> 8)   # ldx CANIDX
e(0xE0, len(prefix))                  # cpx #len(prefix)
bcs_pos = len(stub); e(0xB0, 0x00)    # bcs LIVE（偏移稍后回填）
e(0xBD, CANTBL & 0xFF, CANTBL >> 8)   # lda CANTBL,x
e(0xEE, CANIDX & 0xFF, CANIDX >> 8)   # inc CANIDX
e(0xAE, SAVEX & 0xFF, SAVEX >> 8)     # ldx SAVEX
e(0x60)                               # rts
live = len(stub)
e(0xAD, 0x00, 0xF0)                   # LIVE: lda $F000（输入状态）
beq_pos = len(stub); e(0xF0, 0x00)    # beq LIVE（无字符则自旋，偏移稍后回填）
e(0xAD, 0x01, 0xF0)                   # lda $F001（取字符）
e(0xAE, SAVEX & 0xFF, SAVEX >> 8)     # ldx SAVEX
e(0x60)                               # rts
stub[bcs_pos + 1] = (live - (bcs_pos + 2)) & 0xFF
stub[beq_pos + 1] = (live - (beq_pos + 2)) & 0xFF
REALCOUT = CANIN + len(stub)
# REALCOUT: 字符输出到模拟器 stdout，A/X/Y 全部保持
e(0x8D, 0x01, 0xF0)                   # sta $F001
e(0x60)                               # rts
RTISTUB = CANIN + len(stub)
# RTISTUB: NMI/IRQ/BRK 向量目标
e(0x40)                               # rti
for i, b in enumerate(stub):
    img[CANIN + i] = b

assert CANTBL + len(prefix) < 0xFFEB, '罐头前缀越界'
for i, b in enumerate(prefix):
    img[CANTBL + i] = b

# ---- OSI ROM 入口（地址被 BASIC 硬编码，不可移动）----
def put(addr, bs):
    for i, b in enumerate(bs):
        img[addr + i] = b
put(0xFFEB, [0x4C, CANIN & 0xFF, CANIN >> 8])       # MONRDKEY -> 前缀罐头 + 实时 stdin
put(0xFFEE, [0x4C, REALCOUT & 0xFF, REALCOUT >> 8]) # MONCOUT  -> sta $F001
put(0xFFF1, [0xA9, 0x00, 0x60])                     # MONISCNTC-> lda #0 / rts（无键）
put(0xFFF4, [0x60])                                 # LOAD（OSI 版未使用）
put(0xFFF7, [0x60])                                 # SAVE（OSI 版未使用）
# ---- 向量 ----
put(0xFFFA, [RTISTUB & 0xFF, RTISTUB >> 8])         # NMI
put(0xFFFC, [cold & 0xFF, cold >> 8])               # RESET -> COLD_START
put(0xFFFE, [RTISTUB & 0xFF, RTISTUB >> 8])         # IRQ/BRK

open('MSBASIC_EMU.bin', 'wb').write(img)
print('镜像: MSBASIC_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 MSBASIC_EMU.bin"
