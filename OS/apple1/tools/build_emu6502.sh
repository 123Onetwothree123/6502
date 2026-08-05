#!/bin/bash
# 构建 6502 模拟器版 Apple 1 固件（WozMon 监控 + Woz Integer BASIC + Krusader）
# 上游: tebl/RC6502-Apple-1-Replica, software/firmware/8K Basic & Monitor.bin
#   $E000-$FFFF 8KB 镜像：$E000 Integer BASIC（Woz 写的原版 Apple-1 BASIC，
#   冷启动 JMP $E2B0），$F000 Krusader 1.2（Ken Wessen 的汇编/调试器），
#   $FF00 WozMon，复位向量 -> $FF00。
# 适配方式：二进制补丁，把 6820 PIA（$D010-$D013 及镜像 $D0F2）访问
# 换成模拟器终端（读 $F000=输入状态 0/1，读 $F001=取字符，写 $F001=输出）。
set -e
cd "$(dirname "$0")/.."

SRC="software/firmware/8K Basic & Monitor.bin"
cp "$SRC" /tmp/apple1_8k.bin

python3 - << 'PYEOF'
d = bytearray(open('/tmp/apple1_8k.bin', 'rb').read())
assert len(d) == 8192, '8K 镜像长度不对'

def patch(off, old, new, what):
    old_b, new_b = bytes.fromhex(old), bytes.fromhex(new)
    assert bytes(d[off:off+len(old_b)]) == old_b, \
        f'{what}: @${0xE000+off:04X} 原字节不符: {d[off:off+len(old_b)].hex()} != {old}'
    assert len(new_b) <= len(old_b), f'{what}: 补丁超长'
    d[off:off+len(new_b)] = new_b
    for i in range(off+len(new_b), off+len(old_b)):
        d[i] = 0xEA  # 多余字节填 NOP
    print(f'patch {what} @${0xE000+off:04X}')

# ---- Integer BASIC 键盘输入例程 $E003 ----
# LDA $D011 / BPL -5 / LDA $D010 / RTS
#  -> LDA $F000 / BEQ -5 / LDA $F001 / RTS（返回无 bit7 的 ASCII）
patch(0x0003, 'ad11d010fbad10d060', 'ad00f0f0fbad01f060', 'BASIC 输入例程 $E003')
# 唯一调用点 $E29E: JSR $E003 / NOP / NOP / JSR $E3C9
# 调用方按 Apple 1 约定比较带 bit7 的字符（$8D/$9B/$DF/$84），
# 把两个 NOP 改成 ORA #$80，恢复 bit7，后续逻辑零改动。
patch(0x02a1, 'eaea', '0980', 'JSR $E003 后 ORA #$80')

# ---- Integer BASIC 字符输出例程 $E3C9（尾部 $E3D5）----
# BIT $D0F2 / BMI -5 / STA $D0F2 / RTS（$D0F2 是 DSP $D012 的镜像）
#  -> JMP $0300（终端输出桩，见下），其余填 NOP
patch(0x03d5, '2cf2d030fb8df2d060', '4c0003', 'BASIC 输出 -> $0300 桩')

# ---- BASIC 按键中止检查 $E86F（语句执行循环内）----
# 原为 BIT $D011 / BMI +$4F（KBDCR bit7=有键则中止），BIT 不破坏 A——
# A 里是语句指针低字节，随后的 ADC #$03 依赖它。不能用 LDA $F000 代替！
#  -> JMP $0330（中止检查桩：先 PHA 保存 A，再读 $F000 判断，见下）
patch(0x086f, '2c11d0304f', '4c3003', 'BREAK 检查 $E86F -> $0330 桩')

# ---- Krusader 输入例程 $FEED ----
# LDA $D011 / BPL -5 / LDA $D010 / AND #$7F / RTS
# 调用方比较纯 ASCII（$08/$0D/$1B/$09），AND #$7F 保留无害。
patch(0x1eed, 'ad11d010fbad10d0297f60', 'ad00f0f0fbad01f0297f60', 'Krusader 输入 $FEED')

# ---- WozMon 复位初始化 $FF04 ----
# STY $D012 / LDA #$A7 / STA $D011 / STA $D013 全是 PIA 初始化，模拟器不需要；
# 仅保留 Y=$7F（NOTCR 依赖它触发自动 ESCAPE 打印首个提示符），其余 NOP。
patch(0x1f04, '8c12d0a9a78d11d08d13d0', 'a07f', 'WozMon 复位初始化')

# ---- WozMon 键盘输入 $FF29 ----
# LDA $D011 / BPL -5 -> LDA $F000 / BEQ -5（等键）
patch(0x1f29, 'ad11d010fb', 'ad00f0f0fb', 'WozMon 输入状态 $FF29')
# LDA $D010 -> JMP $0320（输入桩：LDA $F001 / ORA #$80 / JMP 回 $FF31）。
# 恢复 Apple 1 的 bit7 高位约定，WozMon 内部所有比较常量（$8D/$9B/$AE/$BA/$D2、
# EOR #$B0 十六进制解析、MODE 字节的 bit7=BLOCK XAM 标志）保持原样不动。
patch(0x1f2e, 'ad10d0', '4c2003', 'WozMon 取字符 -> $0320 桩')
def imm(off, old, new, what):
    assert d[off] == old, f'{what}: @${0xE000+off:04X} ${d[off]:02X} != ${old:02X}'
    d[off] = new
    print(f'patch {what} @${0xE000+off:04X}: ${old:02X}->${new:02X}')
# 终端 Backspace 发 DEL($7F)，置 bit7 后是 $FF；原为 #$DF（Apple 1 的 '_' 键）
imm(0x1f10, 0xDF, 0xFF, 'WozMon 退格键')

# ---- WozMon 字符输出 ECHO $FFEF ----
# BIT $D012 / BMI -5 / STA $D012 / RTS -> JMP $0300，其余 NOP
patch(0x1fef, '2c12d030fb8d12d060', '4c0003', 'WozMon ECHO -> $0300 桩')

open('/tmp/apple1_8k_patched.bin', 'wb').write(d)
print('8K 补丁完成')
PYEOF

python3 - << 'PYEOF'
rom = open('/tmp/apple1_8k_patched.bin', 'rb').read()
img = bytearray(0x10000)
img[0xE000:0x10000] = rom

# ---- 终端输出桩 $0300（RAM，两个输出例程共用）----
# 输入 A=待输出字符（可能带 bit7），保留 A；CR($0D) 扩成 CR+LF。
stub = bytes([
    0x48,             # PHA
    0x29, 0x7F,       # AND #$7F        ; 去 Apple 1 高位约定
    0x8D, 0x01, 0xF0, # STA $F001       ; 输出
    0xC9, 0x0D,       # CMP #$0D
    0xD0, 0x05,       # BNE +5
    0xA9, 0x0A,       # LDA #$0A        ; CR 后补 LF
    0x8D, 0x01, 0xF0, # STA $F001
    0x68,             # PLA
    0x60,             # RTS
])
img[0x0300:0x0300+len(stub)] = stub

# ---- 键盘输入桩 $0320（RAM，WozMon 专用）----
# 取一个字符并置 bit7（Apple 1 高位约定），然后跳回 WozMon $FF31。
istub = bytes([
    0xAD, 0x01, 0xF0, # LDA $F001       ; 取出字符
    0x09, 0x80,       # ORA #$80        ; 置 bit7
    0x4C, 0x31, 0xFF, # JMP $FF31       ; 回到 STA $0200,Y
])
img[0x0320:0x0320+len(istub)] = istub

# ---- 按键中止检查桩 $0330（RAM，BASIC 语句循环用）----
# 原 BIT $D011 不破坏 A（A=语句指针低字节，随后 ADC #$03 要用），
# 故先 PHA 保存，读 $F000（0=无键 1=有键）判断后再恢复。
bstub = bytes([
    0x48,             # PHA             ; 保存 A
    0xAD, 0x00, 0xF0, # LDA $F000       ; 输入状态
    0xF0, 0x03,       # BEQ +3 -> nokey
    0x68,             # PLA
    0x4C, 0xC3, 0xE8, # JMP $E8C3       ; 有键 -> 中止处理（原 BMI 目标）
    0x68,             # nokey: PLA      ; 恢复 A=语句指针低字节
    0x4C, 0x74, 0xE8, # JMP $E874       ; 回到 CLC; ADC #$03
])
img[0x0330:0x0330+len(bstub)] = bstub

# 向量（镜像自带，断言确认）：NMI=$0F00 RESET=$FF00 IRQ/BRK=$0100
assert img[0xFFFC] == 0x00 and img[0xFFFD] == 0xFF, '复位向量不是 $FF00'
open('APPLE1_EMU.bin', 'wb').write(img)
print('镜像: APPLE1_EMU.bin（64KB，复位 -> WozMon $FF00）')
PYEOF
echo "运行: /home/abc/6502/build/6502 APPLE1_EMU.bin"
echo "BASIC: WozMon 提示符下输入 E000R 回车进入 Integer BASIC"
