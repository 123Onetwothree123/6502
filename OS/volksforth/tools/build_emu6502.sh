#!/bin/bash
# 构建 6502 模拟器版 VolksForth 3.83（forth-ev/VolksForth, py65 目标内核）
#
# 上游构建链是 Forth 元编译（需要 gforth/旧工具链），本机不可用；
# 仓库自带预编译的 py65 目标内核 6502/py65/vfpy65.bin（基址 $1000），
# 该目标恰好用 $F001 做输出（与模拟器约定一致），只有输入需要适配：
#   - $40B4: 65KEY? 的 LDA $F004 / STA $09FF  改为  JSR $F010 + NOP*3
#   - $F010: 实时输入例程：读 $F000 状态（0=无键，A=0 返回）；
#            有键则读 $F001 取字符写入 $09FF（供 GETKEY 读），A=字符返回
# 脚本无汇编器依赖，纯 python3 二进制补丁；中间文件放 /tmp。
set -e
cd "$(dirname "$0")/.."

SRC=6502/py65/vfpy65.bin
[ -f "$SRC" ] || { echo "缺少 $SRC（先 git clone 上游仓库）"; exit 1; }

python3 - << 'PYEOF'
base = 0x1000
kern = bytearray(open('6502/py65/vfpy65.bin','rb').read())
assert kern[0x30b4:0x30ba] == bytes([0xAD,0x04,0xF0,0x8D,0xFF,0x09]), '上游二进制已变化，补丁偏移失效'
assert kern[0x31d3:0x31d6] == bytes([0x8D,0x01,0xF0]), '(emit 未找到'

RTN = 0xF010

# 65KEY? 补丁：JSR $F010 ; NOP NOP NOP
kern[0x30b4:0x30ba] = bytes([0x20, RTN & 0xFF, RTN >> 8, 0xEA, 0xEA, 0xEA])

# 实时输入例程（不碰 X——X 是 volksFORTH 数据栈指针；LDA/BEQ/STA 均不影响 X）
# 返回 A=0 表示无键；有键则 A=字符（非零）并写入 $09FF
rtn = bytes([
    0xAD, 0x00, 0xF0,       # LDA $F000      输入状态
    0xF0, 0x06,             # BEQ ret        无字符：A 已是 0，直接返回
    0xAD, 0x01, 0xF0,       # LDA $F001      取出一个字符
    0x8D, 0xFF, 0x09,       # STA $09FF      GETKEY 的键缓冲
    0x60,                   # ret: RTS
])

img = bytearray(0x10000)
img[base:base+len(kern)] = kern
img[RTN:RTN+len(rtn)] = rtn
# 复位 / BRK 向量 -> 冷启动 $1000（NOP; JMP $402A）
img[0xFFFC] = 0x00; img[0xFFFD] = 0x10
img[0xFFFE] = 0x00; img[0xFFFF] = 0x10
open('VOLKSFORTH_EMU.bin','wb').write(img)
print('镜像: VOLKSFORTH_EMU.bin (%d 字节, 实时输入例程 %d 字节)' % (len(img), len(rtn)))
PYEOF
echo "运行: /home/abc/6502/build/6502 VOLKSFORTH_EMU.bin"
