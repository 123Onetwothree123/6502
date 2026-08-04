#!/bin/bash
# 构建 6502 模拟器版 sixty5o2（Ben Eater 面包板微内核）
# 依赖: vasm（vasm6502_oldstyle，已装到 /usr/local/bin）
set -e
cd "$(dirname "$0")/.."

# 1. 汇编 bootloader（模拟器版：LCD->UART、键盘自动选择 Run）
vasm6502_oldstyle -Fihex -o /tmp/boot_emu.hex bootloader_emu.asm 2>/dev/null

# 2. 汇编示例程序（模拟器版）
vasm6502_oldstyle -Fihex -o /tmp/hello.hex hello_world_emu.asm 2>/dev/null

# 3. 合并为一个 ihex 镜像
python3 - << PYEOF
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
