#!/bin/bash
# 构建 6502 模拟器版 Contiki（hello-world 示例）
# 依赖: cc65（AUR: cc65-git）
set -e
cd "$(dirname "$0")/.."

cd examples/hello-world
make TARGET=c64 CONTIKI_WITH_IPV4=1 \
  LDFLAGS="-t c64 -m contiki-c64.map -D __STACKSIZE__=0x200 -D __HIMEM__=0xFF00"

cd ../..
python3 - << PYEOF
def load(f, addr, img, strip_header=True):
    d = open(f, 'rb').read()
    if strip_header:
        d = d[2:]
    img[addr:addr+len(d)] = d

img = bytearray(0x10000)
load('examples/hello-world/hello-world.c64', 0x0801, img)
img[0xFFFC:0xFFFE] = bytes([0x0D, 0x08])          # RESET -> crt0

def stub(addr, code):
    for i, b in enumerate(code):
        img[addr + i] = b

stub(0xFFD2, [0x8D, 0x01, 0xF0, 0x60])            # CHROUT -> UART $F001
stub(0xFFCF, [0xA9, 0x0D, 0x60])                  # CHRIN: 返回换行
stub(0xFFE4, [0xA9, 0x0D, 0x60])                  # GETIN
stub(0xFFBA, [0x60])                              # SETNAM
stub(0xFFBD, [0x60])                              # SETLFS
stub(0xFFC0, [0x18, 0xA9, 0x00, 0x60])            # OPEN: 成功
stub(0xFFC3, [0x60])                              # CLOSE
stub(0xFFC6, [0x60])                              # CHKIN
stub(0xFFC9, [0x60])                              # CHKOUT
stub(0xFFCC, [0x60])                              # CLRCHN
stub(0xFFB7, [0xA9, 0x00, 0x60])                  # 字节写成功

img[0x08D8:0x08DB] = bytes([0xEA, 0xEA, 0xEA])    # initstdio 读控制台失败不退出
img[0x0883:0x0886] = bytes([0xEA, 0xEA, 0xEA])    # 跳过 config_read（无磁盘）
img[0x0886:0x0889] = bytes([0xEA, 0xEA, 0xEA])    # 跳过 SLIP_INIT（无网卡）
img[0x3A2A:0x3A2D] = bytes([0xA9, 0x00, 0x60])    # open 设备就绪检查直接通过
img[0x0836:0x0839] = bytes([0x4C, 0x7C, 0x08])    # crt0 尾部 -> jmp main（无 BASIC）

open('HELLO_EMU.bin', 'wb').write(img)
print('镜像: HELLO_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 HELLO_EMU.bin"
