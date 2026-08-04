#!/bin/bash
# 构建 6502 模拟器版 CPM-65：转换语法 -> xa 汇编 -> 组装 64KB 镜像
# 依赖: xa (pacman: xa), python3
set -e
cd "$(dirname "$0")/.."

# 1. 6502MASM -> xa 语法转换 + 模拟器移植补丁
python3 tools/convert_6502asm.py

# 2. 汇编
mkdir -p build
for f in BIOS BDOS CCP BOOT; do
  xa -XMASM -o build/$f.o System/$f.xa.asm
  echo "汇编 $f OK"
done

# 3. 组装 64KB 镜像
python3 - << PYEOF
def load(f, addr, img):
    d = open(f, 'rb').read()
    img[addr:addr+len(d)] = d
img = bytearray(0x10000)
load('build/BOOT.o', 0x0200, img)
load('build/CCP.o', 0xD800, img)
load('build/BDOS.o', 0xDC00, img)
load('build/BIOS.o', 0xE400, img)
img[0xFFFC:0xFFFE] = bytes([0x00, 0xE4])  # reset -> BIOS BOOT
open('OS_EMU6502.bin', 'wb').write(img)
print('镜像: OS_EMU6502.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 OS_EMU6502.bin"
