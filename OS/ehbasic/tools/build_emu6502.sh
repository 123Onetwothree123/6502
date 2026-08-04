#!/bin/bash
# 构建 6502 模拟器版 EhBASIC 2.22（Enhanced BASIC）
# 依赖: vasm（vasm6502_oldstyle）
set -e
cd "$(dirname "$0")/.."

python3 - << 'PYEOF'
import re

def to_oldstyle(src):
    lines = src.split('\n')
    out = []
    for ln in lines:
        st = ln.lstrip()
        ind = ln[:len(ln)-len(st)]
        for d in ['.org', '.byte', '.asciiz', '.word', '.ascii', '.text', '.ds', '.dc']:
            if (st.startswith(d) and (len(st) == len(d) or st[len(d)] in ' \t')):
                st = d[1:] + st[len(d):]
                break
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+\.(byte|word|asciiz|ascii|text|ds|res)\b', st)
        if m:
            st = m.group(1) + ':' + st[m.end(1):]
        out.append(ind + st)
    s = '\n'.join(out)
    s = re.sub(r'^([A-Za-z_][A-Za-z0-9_]*:\s+)\.(byte|word|asciiz|ascii|text|ds|res)\b', r'\1\2', s, flags=re.M)
    return s

def fix_expr(src):
    lines = src.split('\n')
    out = []
    for ln in lines:
        st = ln.lstrip()
        ind = ln[:len(ln)-len(st)]
        if ';' in st:
            code, _, comment = st.partition(';')
        else:
            code, comment = st, ''
        code = code.replace('[', '(').replace(']', ')')
        st = code + (';' + comment if comment else '')
        out.append(ind + st)
    return '\n'.join(out)

s = fix_expr(to_oldstyle(open('basic.asm').read()))
s = s.replace('Ibuffs		= IRQ_vec+$14', 'IRQ_vec		= $0200\nIbuffs		= IRQ_vec+$14', 1)
open('/tmp/ehbasic_basic.asm', 'w').write(s)
print('转换完成')
PYEOF

vasm6502_oldstyle -Fbin -o /tmp/ehbasic_basic.bin /tmp/ehbasic_basic.asm

python3 - << 'PYEOF'
basic = bytearray(open('/tmp/ehbasic_basic.bin','rb').read())
# 1. 跳过内存检测: $11/$12 = $00/$C0, jmp $C07F（完成路径）
patch = bytes([0xA9, 0x00, 0x85, 0x11,
               0xA9, 0xC0, 0x85, 0x12,
               0x4C, 0x7F, 0xC0])
basic[0x54:0x54+len(patch)] = patch
for i in range(0x54+len(patch), 0x7F):
    basic[i] = 0xEA
# 2. 修复 LAB_PRNA 的 V_OUTP 编译错位
basic[0x90A:0x90D] = bytes([0x20, 0xF0, 0xE0])
open('/tmp/ehbasic_basic.bin','wb').write(basic)
print('patch 完成')
PYEOF

python3 - << 'PYEOF'
base = 0xF200
start_len = 58
out_byte = base + start_len
seq_routine = out_byte + 4
SEQ_LEN = 26
table = seq_routine + SEQ_LEN
code = []
def w(b): code.append(b)
def wa(addr, target):
    w(0xA9); w(target & 0xFF); w(0x8D); w(addr & 0xFF); w(addr >> 8)
    w(0xA9); w(target >> 8); w(0x8D); w((addr+1) & 0xFF); w((addr+1) >> 8)
wa(0x0209, out_byte); wa(0x0207, seq_routine); wa(0x0205, seq_routine)
wa(0x020B, seq_routine); wa(0x020D, seq_routine)
w(0xA9); w(11); w(0x8D); w(0x00); w(0x3F)
w(0x4C); w(0x00); w(0xC0)
w(0x8D); w(0x01); w(0xF0); w(0x60)
seq = [0x98, 0x48, 0xAD, 0x00, 0x3F, 0xF0, 0x0A,
       0xCE, 0x00, 0x3F, 0xA8, 0xB9, 0, 0,
       0xD0, 0x02, 0xA9, 0x0D,
       0x8D, 0x01, 0x3F, 0x68, 0xA8,
       0xAD, 0x01, 0x3F, 0x38, 0x60]
seq[12] = table & 0xFF
seq[13] = table >> 8
code += seq
tbl = [0x0D, ord('6'), ord('*'), ord('7'), ord(' '), ord('T'), ord('N'), ord('I'), ord('R'), ord('P'), 0x0D]
code += tbl
img = bytearray(0x10000)
img[0xC000:0xC000+10277] = open('/tmp/ehbasic_basic.bin','rb').read()
for i, b in enumerate(code): img[base+i] = b
irq = [0xE6,0xA0,0xD0,0x04,0xE6,0xA1,0xD0,0x00,0xE6,0xA2,0x40]
for i, b in enumerate(irq): img[0xFF00+i] = b
img[0xFFFC] = 0x00; img[0xFFFD] = 0xF2
img[0xFFFE] = 0x00; img[0xFFFF] = 0xFF
open('EHBASIC_EMU.bin','wb').write(img)
print('镜像: EHBASIC_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 EHBASIC_EMU.bin"
