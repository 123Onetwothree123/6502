#!/bin/bash
# 构建 6502 模拟器版 sixty5o2（Ben Eater 面包板微内核）
# 依赖: vasm（vasm6502_oldstyle，/usr/local/bin）
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
            if st.startswith(d + ' ') or st == d:
                st = d[1:] + st[len(d):]
                break
        out.append(ind + st)
    return '\n'.join(out)

def replace_fn(src, name, newbody):
    start = src.find(name + ':')
    if start < 0: raise SystemExit(f'{name} 未找到')
    body_start = src.index('\n', start) + 1
    body_end = len(src)
    for mm in re.finditer(r'^\S[^:]*:\s*$', src[body_start:], re.M):
        body_end = body_start + mm.start()
        break
    return src[:start] + name + ':\n' + newbody + '\n' + src[body_end:]

# ---- bootloader: LCD->UART、键盘自动选择 Run、去延时 ----
s = to_oldstyle(open('bootloader.asm').read())
s = s.replace('''main:                                           ; boot routine, first thing loaded
    ldx #$ff                                    ; initialize the stackpointer with 0xff
    txs''', '''main:                                           ; boot routine, first thing loaded
    ldx #$ff                                    ; initialize the stackpointer with 0xff
    txs
    lda #3
    sta $3fd9                                   ; 模拟器: 自动按键序列计数 (DOWN DOWN SELECT)''')
s = replace_fn(s, 'LIB__sleep', '    rts')
s = replace_fn(s, 'LCD__send_data', '''    sta $F001
    rts''')
s = replace_fn(s, 'LCD__send_instruction', '    rts')
s = replace_fn(s, 'LCD__check_busy_flag', '''    lda #0
    rts''')
s = replace_fn(s, 'VIA__read_keyboard_input', '''    lda $3fd9
    beq .kbd_none
    dec $3fd9
    lda $3fd9
    cmp #$02
    beq .kbd_down
    cmp #$01
    beq .kbd_down
    lda #$08
    rts
.kbd_down:
    lda #$02
    rts
.kbd_none:
    lda #$00
    rts''')
s = replace_fn(s, 'VIA__configure_ddrs', '    rts')
open('/tmp/bootloader_emu.asm', 'w').write(s)

# ---- hello_world 示例: LCD->UART、去延时 ----
s = to_oldstyle(open('examples/hello_world.asm').read())
s = replace_fn(s, 'sleep', '    rts')
s = replace_fn(s, 'send_lcd_data', '''    sta $F001
    rts''')
s = replace_fn(s, 'send_lcd_instruction', '    rts')
s = replace_fn(s, 'check_busy_flag', '''    lda #0
    rts''')
s = replace_fn(s, 'init_lcd', '    rts')
s = replace_fn(s, 'init_via_ports', '    rts')
s = replace_fn(s, 'clear_lcd', '''    pha
    lda #$01
    jsr send_lcd_instruction
    pla
    rts''')
open('/tmp/hello_world_emu.asm', 'w').write(s)
print('模拟器版源码生成')
PYEOF

vasm6502_oldstyle -Fihex -o /tmp/boot_emu.hex /tmp/bootloader_emu.asm
vasm6502_oldstyle -Fihex -o /tmp/hello.hex /tmp/hello_world_emu.asm

python3 - << 'PYEOF'
def parse_hex(f):
    recs = []
    for line in open(f):
        line = line.strip()
        if not line.startswith(':'): continue
        n = int(line[1:3],16); addr = int(line[3:7],16); typ = int(line[7:9],16)
        data = bytes(int(line[9+i*2:11+i*2],16) for i in range(n))
        recs.append((addr, typ, data))
    return recs
def emit(addr, data):
    n = len(data)
    body = f'{n:02X}{addr:04X}00' + data.hex().upper()
    cksum = (~sum(bytes.fromhex(body)) + 1) & 0xFF
    return f':{body}{cksum:02X}'
out = []
for addr, typ, data in parse_hex('/tmp/boot_emu.hex') + parse_hex('/tmp/hello.hex'):
    if typ == 0: out.append(emit(addr, data))
out.append(':00000001FF')
open('SIXTY5O2_EMU.hex', 'w').write('\n'.join(out) + '\n')
print('镜像: SIXTY5O2_EMU.hex')
PYEOF
echo "运行: /home/abc/6502/build/6502 SIXTY5O2_EMU.hex"
