#!/bin/bash
# 构建 6502 模拟器版 LUnix（c64-lng）
set -e
cd "$(dirname "$0")/.."
export PATH=$PWD/devel_utils:$PWD/devel_utils/atari:$PATH
make devel
make kernel
python3 - << PYEOF
def load(f, addr, img, strip_header=True):
    d = open(f, 'rb').read()
    if strip_header:
        d = d[2:]
    img[addr:addr+len(d)] = d
img = bytearray(0x10000)
load('kernel/boot.c64', 0x1000, img)
load('kernel/lunix.c64', 0x2000, img)
img[0xFFFC:0xFFFE] = bytes([0x78, 0x10])
img[0x1150:0x1153] = bytes([0x4C, 0x05, 0x20])
open('LUNIX_EMU.bin', 'wb').write(img)
print('镜像: LUNIX_EMU.bin')
PYEOF
echo "运行: IRQ_INTERVAL=100000 /home/abc/6502/build/6502 LUNIX_EMU.bin"
