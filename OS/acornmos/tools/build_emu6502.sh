#!/bin/bash
# 构建 6502 模拟器版 Acorn MOS 3.20(NT)（tom-seddon/acorn_mos_disassembly）
# 依赖: 64tass（默认用 /tmp 下编译好的；可用 TASS= 覆盖）
#
# 适配要点：
#  1. 模拟器是严格 NMOS 6502，MOS 是 65C12 代码 —— 文本级翻译全部 CMOS 指令
#     （bra/phx/phy/plx/ply/stz/trb/tsb/inc a/dec a/(zp) 间接/jmp (abs,x)），
#     用 --m6502 重新汇编，由汇编器自动重定位。
#  2. HAZEL($DC00)/ANDY($8000) 是 Master 上与 ROM 分页重叠的 RAM，平坦 64KB
#     下会自毁代码 —— 重定位到 $7000/$6000。
#  3. OSWRCH/OSRDCH 替换为模拟器串口（$F000 状态 / $F001 数据）。
#  4. MOS ROM 会覆盖 $F000/$F001（UART 寄存器）—— 两遍汇编在 $F000-$F003
#     打出 4 字节空洞（$F002/$F003 顺便作 trb/tsb 翻译的暂存字节）。
#  5. 上电 clearRAM 会把 RAM 里的"ROM"抹掉 —— 跳过。
set -e
cd "$(dirname "$0")/.."

TASS=${TASS:-/tmp/64tass-src/64tass-1.59.3120-src/64tass}
BUILD=/tmp/acornmos_emu_build
rm -rf "$BUILD"
mkdir -p "$BUILD/src"
cp mos320nt.s65 "$BUILD/"
cp src/*.s65 "$BUILD/src/"

#-------------------------------------------------------------------------
# 文本补丁
#-------------------------------------------------------------------------
python3 - << 'PYEOF'
import re, os, sys

B = '/tmp/acornmos_emu_build'

def read(p):
    return open(os.path.join(B, p)).read()

def write(p, s):
    open(os.path.join(B, p), 'w').write(s)

def patch(p, old, new, count=1):
    s = read(p)
    assert old in s, f'{p}: 未找到补丁锚点: {old[:60]!r}'
    s = s.replace(old, new, count)
    write(p, s)

# 2. HAZEL $DC00 -> $7000, ANDY $8000 -> $6000（平坦 RAM 下不再分页重叠）
#=========================================================================
s = read('src/mos_workspace.s65')
assert s.count('.virtual $dc00') == 1
s = s.replace('.virtual $dc00', '.virtual $7000 ; EMU: HAZEL 重定位（原为 $dc00）')
assert s.count('.virtual $8000\nandy: .block') == 1
s = s.replace('.virtual $8000\nandy: .block',
              '.virtual $6000 ; EMU: ANDY 重定位（原为 $8000）\nandy: .block')
s = s.replace('.cerror *!=$9000,"ANDY is the wrong size"',
              '.cerror *!=$7000,"ANDY is the wrong size" ; EMU: $6000 基址')
# ANDY 块内的绝对地址填充也要重定位
s = s.replace('.fill $8800-*', '.fill $6800-* ; EMU: 随 ANDY 重定位')
# ANDY 常量区整体 $8xxx -> $6xxx（仅限 "符号=$8xxx" 定义行）
def rebase_def(m):
    return m.group(1) + '$6' + m.group(3)
s, n = re.subn(r'^(\s*[A-Za-z_][\w.]*=\s*)\$8([0-9a-fA-F]{3})\b',
               lambda m: m.group(1) + '$6' + m.group(2), s, flags=re.M)
print(f'ANDY 常量重定位: {n} 处')
assert n >= 30
write('src/mos_workspace.s65', s)

# ext.s65 里的原始 $88xx 字面量（ANDY 工作区）
s = read('src/ext.s65')
s, n1 = s.__class__(s), 0
for old, new in [('$8830', '$6830'), ('$8834', '$6834')]:
    c = s.count(old)
    assert c >= 1, f'ext.s65: {old} 未找到'
    s = s.replace(old, new)
    n1 += c
write('src/ext.s65', s)
print(f'ext.s65 字面量重定位: {n1} 处')

#=========================================================================
# 3. OSWRCH/OSRDCH -> 模拟器串口
#=========================================================================
# OSRDCH: 整个例程替换为两个跳转（osrdchWithTimeout 是 INKEY 入口）
s = read('src/mos.s65')
old = '''osrdchEntryPoint:
                stz readCharacterTimedFlag   ;clear the timed flag
osrdchWithTimeout:
                phx
                phy'''
new = '''osrdchEntryPoint:
                jmp emuOSRDCH                ; EMU: 串口阻塞读
osrdchWithTimeout:
                jmp emuOSRDCH                ; EMU: INKEY 也走串口（超时失效）
                phx
                phy'''
assert old in s
s = s.replace(old, new, 1)

# OSWRCH: 入口直接跳串口输出
old = '''oswrchEntryPoint:
                pha                          ;S=[ch]'''
new = '''oswrchEntryPoint:
                jmp emuOSWRCH                ; EMU: 串口输出
                pha                          ;S=[ch]'''
assert old in s
s = s.replace(old, new, 1)

#=========================================================================
# 4. 删除 credits（$FC00-$FEFF，腾出翻译膨胀空间），加锚点与串口桩
#=========================================================================
i0 = s.index('; Credits - normally hidden by the I/O region.')
i1 = s.index('E_USERV: ; ff00')
# 保留包裹 credits 的 .else ... .endif 结构：credits 块从 .if version<500 开始
seg = s[i0:i1]
j0 = seg.index('.if version<500')
j1 = seg.rindex('.endif')  # credits 块收尾的 .endif（对应 .if version!=400 之前的结构）
# 找到 credits 区最后一个 .endif（闭合 .else 的那个）——保留它
stub = '''; EMU: credits 已删除，原地放串口桩、BRK 模拟桩与布局锚点

; 模拟器串口 I/O（$F000=输入状态 0/1，$F001=数据）
emuOSWRCH:
                sta $f001                    ; 写 $F001 = 输出字符（A/X/Y/P 均不受影响）
                rts
emuOSRDCH:
                lda $f000                    ; 自旋等输入
                beq emuOSRDCH
                lda $f001                    ; 取字符
                clc                          ; C=0 = 读成功（无 ESCAPE）
                rts

; BRK 模拟：模拟器执行 BRK 会停机，错误抛出全部改走这里。
; 由 jsr emuBrk 调用（替代原 brk 指令）：jsr 压入的返回地址 = 原 brk 位置+2，
; 与真实 BRK 压栈值相同；但错误号现在在 brk 位置+3（jsr 占 3 字节），
; 所以把返回地址 +2，使 BRK 处理器算出的 errPtr 指向错误号。
emuBrk:
                pla                          ; 返回地址 lo
                clc
                adc #2
                sta TEMPA
                pla                          ; 返回地址 hi
                adc #0
                pha
                lda TEMPA
                pha                          ; 栈帧 = [调整后的 PC][P]，同真实 BRK
                php
                sei
                jmp irqEntryPoint

; doFollowingError 的 BRK 模拟：SEIWKA 指向错误号（原来会复制到 $0100 再
; jmp $0100 执行那里的 BRK）。构造 errPtr = SEIWKA 的 BRK 栈帧。
emuDoError:
                clc
                lda SEIWKA+0
                adc #1
                sta TEMPA
                lda SEIWKA+1
                adc #0
                pha
                lda TEMPA
                pha
                php
                sei
                jmp irqEntryPoint

.endif

; EMU 布局锚点：保证扩展向量表落在 $FF00
                .cerror *>$ff00,"MOS 代码溢出 $FF00"
                *=$ff00

'''
s = s[:i0] + stub + s[i1:]
write('src/mos.s65', s)
print('credits 删除 + 串口桩 + $FF00 锚点完成')

#=========================================================================
# 5. 跳过 clearRAM（平坦 RAM 会把 RAM 里的 MOS/Utils 代码一起抹掉）
#=========================================================================
patch('src/reset.s65',
      'startClearRAM:\n                tay             ;Y=0',
      'startClearRAM:\n                jmp nonPowerOnReset ; EMU: 跳过清 RAM（代码在 RAM 里）\n                tay             ;Y=0')

#=========================================================================
# 6. 跳过 R+BREAK 的 CMOS 复位死等（无键盘，"Press break" 永远等不到）
#=========================================================================
patch('src/reset.s65',
      'checkForResetKey:\n                cmp #key_r\n                bne softReset',
      'checkForResetKey:\n                cmp #key_r\n                jmp softReset ; EMU: 永不进 CMOS 复位死等')

#=========================================================================
# 7. OSBYTE/OSWORD 分派表从 mos 挪到 utils 段（纯数据，缓解 mos 溢出）
#=========================================================================
patch('src/mos.s65',
      '                .if version<500&&version!=350\n                .include "osbyte_osword_table.s65"\n                .endif',
      '                ; EMU: osbyte_osword_table 挪到 utils 段')
patch('src/utils.s65',
      'utilsUnusedBegin:',
      '                .if version<500&&version!=350\n                .include "osbyte_osword_table.s65" ; EMU: 从 mos 段挪入\n                .endif\n\nutilsUnusedBegin:')

#=========================================================================
# 8. .fill $fc00-*,$ff 在代码膨胀后会变负数 —— 条件化
#=========================================================================
patch('src/mos.s65',
      'mosUnusedBegin:\n                .fill $fc00-*,$ff',
      'mosUnusedBegin:\n                .if *<$fc00 ; EMU: 膨胀后可能已过 $FC00\n                .fill $fc00-*,$ff\n                .endif')

#=========================================================================
# 9. VDU 例程窗口放宽：MSB 打包编码实际支持 $C000-$CFFF（4 位 nibble），
#    原版 cerror 保守限制在 $C7FF —— 翻译膨胀后 VDU22/29 落在 $C8xx
#=========================================================================
patch('src/mos.s65',
      "+$7ff,format(\"illegal VDU routine address",
      "+$fff ; EMU: 编码支持到 $CFFF\n                .cerror vdu_routines[_i][0]<(vduRoutinesPage<<8) || vdu_routines[_i][0]>(vduRoutinesPage<<8)+$fff,format(\"illegal VDU routine address")

#=========================================================================
# 10. 删除 utils 里的默认字体数据（保留 LB900/chr127 标签；串口输出用不到，
#     restoreFont 复制全零数据无害）—— 为数据表搬迁腾空间
#=========================================================================
s = read('src/utils.s65')
# 字体起始标签不再页对齐，去掉对齐检查与 $b900 填充
s = s.replace('                .cerror (<LB900)!=0,"font data must be page aligned"\n',
              '                ; EMU: 字体已删，去掉页对齐检查\n')
s = s.replace('                .fill $b900-*,$ff',
              '                .if *<$b900 ; EMU: 数据块搬入后可能已过 $B900\n                .fill $b900-*,$ff\n                .endif')
i = s.index('; EMU: 字体已删，去掉页对齐检查')
i = s.index('\n', i) + 1
s = s[:i] + '''; EMU: 字体数据已删除（串口输出，无需 VDU 字体）
chr127=LB900+$2f8 ; EMU: 保留符号（CHR$127 = LB900+(127-32)*8），指向空洞，仅取地址
'''
write('src/utils.s65', s)
print('字体数据删除完成')

#=========================================================================
# 11. mos 的图形/CRT 数据表块搬到 utils 段（纯数据，绝对寻址引用，
#     平坦 RAM 下 utils 段永远可见）—— 缓解 mos 段溢出
#=========================================================================
s = read('src/mos.s65')
a = s.index('distanceMasksTable:')
b = s.index(';-------------------------------------------------------------------------\n;\n; Get address of soft character definition.')
block = s[a:b]
assert '.align' not in block and '*=' not in block, '数据块含位置敏感指令'
s = s[:a] + '; EMU: 数据表块(distanceMasksTable..scrollRoutinesTable)挪到 utils 段\n\n' + s[b:]
write('src/mos.s65', s)
u = read('src/utils.s65')
assert 'utilsUnusedBegin:' in u
u = u.replace('utilsUnusedBegin:', block + '\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
print('数据表块搬迁完成（%d 行）' % block.count('\n'))

#=========================================================================
# 12. vduRoutinesLSB/MSB 表也搬到 utils（纯数据，~66B）
#=========================================================================
s = read('src/mos.s65')
a = s.index('; LSB of routine address')
i = s.index('vduRoutinesMSBTable:')
i = s.index('.next', i) + len('.next')
b = s.index('\n', i) + 1
block = s[a:b]
s = s[:a] + '; EMU: vduRoutinesLSB/MSBTable 挪到 utils 段\n' + s[b:]
write('src/mos.s65', s)
u = read('src/utils.s65')
u = u.replace('utilsUnusedBegin:', block + '\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
print('vduRoutines 表搬迁完成')

#=========================================================================
# 12b. startupMessages + LE013/LE023 表（含 "Acorn MOS" 横幅，纯数据，
#      绝对寻址引用）搬到 utils，给 BRK 模拟桩腾地方
#=========================================================================
s = read('src/mos.s65')
a = s.index('startupMessages: .block')
b = s.index('; VDU control code dispatch tables')
block = s[a:b]
s = s[:a] + '; EMU: startupMessages+LE013/LE023 挪到 utils 段\n\n' + s[b:]
write('src/mos.s65', s)
u = read('src/utils.s65')
u = u.replace('utilsUnusedBegin:', block + '\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
print('startupMessages 搬迁完成')

#=========================================================================
# 12c. sound_stuff.s65 从 mos 挪到 utils（mos_workspace.s65 注释说明
#      这 ~750 字节声音代码本就支持放 ext ROM；utils 银行就是我们的 ext）。
#      引用全是绝对标签，平坦 RAM 下段间 jsr 可达。
#=========================================================================
patch('src/mos.s65',
      '                .if version<500&&version!=350&&!soundStuffInExtROM\n                .include "sound_stuff.s65"\n                .endif',
      '                ; EMU: sound_stuff 挪到 utils 段')
patch('src/utils.s65',
      'utilsUnusedBegin:',
      '                .include "sound_stuff.s65" ; EMU: 从 mos 段挪入\n\nutilsUnusedBegin:')
print('sound_stuff 搬迁完成')

#=========================================================================
# 12e. restoreFont32To255/32ToN 改 rts（字体数据已删，复制全零无意义）
#=========================================================================
s = read('src/restore_font.s65')
i = s.index('restoreFont32To255:')
j = s.index('restoreFontPart:')
header = 'restoreFont32ToN:\nrestoreFont32To255:\n                rts\n\n; EMU: 原实现不可达，仅保留 restoreFontPart 供引用\n'
s = s[:i] + header + s[j:]
write('src/restore_font.s65', s)
print('restore_font 裁剪完成')

#=========================================================================
# 12d. 裁掉 rtc.s65 的 CMOS 时钟部分（OSWORD 14/15、字符串表，~700B）。
#      无 RTC 硬件，*TIME 无意义；保留 CMOS RAM 字节读写（配置读取依赖）。
#=========================================================================
s = read('src/rtc.s65')
lines = s.split('\n')
# 找 readDefaults2 注释块前的分隔线作为切点
cut = None
for i, ln in enumerate(lines):
    if 'readDefaults2:' in ln:
        # 向上找 ;---- 分隔线
        for j in range(i, max(0, i - 30), -1):
            if lines[j].startswith(';-----'):
                cut = j
                break
        break
assert cut and cut > 400, f'rtc.s65 切点异常: {cut}'
stub = '''; EMU: CMOS 时钟部分（OSWORD 14/15、日期字符串表）已裁掉——
; 模拟器无 RTC 芯片，*TIME 无意义。保留下面的 CMOS RAM 字节读写。
osword0E:
osword0F:
finishRTCUpdate:
                rts

'''
s = stub + '\n'.join(lines[cut:])
write('src/rtc.s65', s)
print(f'rtc.s65 时钟段裁剪完成（删 {cut} 行）')

#=========================================================================
# 13. extendedVectorEntryPoint 等 4 个例程挪到 utils 段（$FF00-$FFFF 区域
#     塞不下翻译膨胀；平坦 RAM 下 utils 段永远可见，jsr 可达），
#     并在 API 跳表前加 $FFB3 锚点
#=========================================================================
s = read('src/mos.s65')
a = s.index('extendedVectorEntryPoint:')
b = s.index('; Except for the NMI routine in main RAM')
block = s[a:b]
s = s[:a] + s[b:]
write('src/mos.s65', s)
u = read('src/utils.s65')
u = u.replace('utilsUnusedBegin:', block + '\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
# API 跳表锚点
s = read('src/mos.s65')
s = s.replace('OSWRSC:\n                .entryPoint jmp,oswrscEntryPoint ; FFB3',
              '; EMU 布局锚点：保证 API 跳表落在 $FFB3\n                .cerror *>$ffb3,"MOS 代码溢出 $FFB3"\n                *=$ffb3\n\nOSWRSC:\n                .entryPoint jmp,oswrscEntryPoint ; FFB3')
write('src/mos.s65', s)
print('扩展向量例程搬迁 + $FFB3 锚点完成')

#=========================================================================
# 14. entryPoint 宏的 >=$E000 检查是 HAZEL 分页约束；HAZEL 已重定位到
#     $7000，MOS 全域 $C000-$FFFF 恒可执行 —— 放宽为 >=$C000
#=========================================================================
patch('src/mos.s65',
      'entryPoint: .macro instr,dest\n                .cerror (\\dest)<$e000',
      'entryPoint: .macro instr,dest\n                ; EMU: 平坦 RAM，无分页约束（osfileEntryPoint 等在 utils 段也可达）')

print('全部文本补丁完成（前段）')

#=========================================================================
# 15. BRK 模拟：模拟器执行 BRK 指令即停机，MOS 错误机制全靠 BRK ——
#     内联 brk 改 jsr emuBrk，doFollowingError 的 jmp $0100 改 jmp emuDoError。
#     注意只改代码 brk，表格/字符串里的 brk 数据字节不动。
#=========================================================================
for label in ['thisIsNotALanguageError', 'iCannotRunThisCodeError',
              'badStringError', 'badFilingSystemName', 'badCommandError']:
    patch('src/mos.s65',
          f'{label}:\n                brk',
          f'{label}:\n                jsr emuBrk ; EMU: BRK 会停机，改模拟')
patch('src/mos.s65',
      '; do a BRK and print MOS version number.\n\n                brk',
      '; do a BRK and print MOS version number.\n\n                jsr emuBrk ; EMU')
patch('src/utils.s65',
      '                jmp $0100',
      '                jmp emuDoError ; EMU: 不执行 BRK，直接模拟')

#=========================================================================
# 16. tubeHost 整体换标签桩（无 Tube 硬件，探测永远返回不存在，
#     这些代码是死的但标签被引用）—— utils 省 ~317B
#=========================================================================
s = read('src/utils.s65')
a = s.index('tubeHost: .block')
b = s.index('                .here\n                .bend', a) + len('                .here\n                .bend')
stub = '''tubeHost: .block          ;tube code —— EMU: 无 Tube，整体替换为标签桩
copyLanguage:
copyEscapeStatus:
getLanguageParasiteAddr:
resetTubeClaim:
eventHandler:
idleLoop:
idleStartup:
entryPoint:
brkHandler:
commandRoutines:
page:
codePage:
codePages:
codePage0:
codePages12:
                rts
zeroPageCode: .block
languageParasiteAddr:
                .dword $8000
transferRelocatedPageLoop:
relocationDelta:
tubeLanguageHostAddr:
tubeRelocationBitmapPtr:
tubeRelocationBitmapROMBank:
brkHandler:
idleLoop:
idleStartup:
                rts
                .endblock
                .bend'''
s = s[:a] + stub + s[b:]
write('src/utils.s65', s)
print('tubeHost 标签桩完成')

#=========================================================================
# 17. FSC 块（getCommandLinePointer..badCommandError）与 oscliEntryPoint
#     块挪到 utils 段，缓解 mos 溢出
#=========================================================================
s = read('src/mos.s65')
a = s.index('getCommandLinePointer: .proc')
b = s.index(';-------------------------------------------------------------------------\n\n                .if version==350\n                .if includeTubeSupport', a)
block = s[a:b]
s = s[:a] + '; EMU: FSC 块挪到 utils 段\n\n' + s[b:]
a2 = s.index('starLIBFS:')
b2 = s.index('emptyCommandLine=oscliEntryPoint.emptyCommandLine') + len('emptyCommandLine=oscliEntryPoint.emptyCommandLine')
block2 = s[a2:b2]
s = s[:a2] + '; EMU: oscliEntryPoint 块挪到 utils 段\n' + s[b2:]
write('src/mos.s65', s)
u = read('src/utils.s65')
u = u.replace('utilsUnusedBegin:', block + '\n' + block2 + '\n\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
print('FSC/oscli 块搬迁完成')

#=========================================================================
# 18. IRQ/键盘中断处理区（irq2EntryPoint..osbyte81Timed，~420B）挪到
#     utils 段。模拟器无 IRQ 源，该区大部分代码是死的；剩余活代码
#     （键盘轮询）经绝对 jsr 调用，平坦 RAM 下段间可达。
#=========================================================================
s = read('src/mos.s65')
a = s.index('irq2EntryPoint:')
b = s.index('osbyte81Timed:')
block = s[a:b]
s = s[:a] + '; EMU: IRQ/键盘中断处理区挪到 utils 段\n\n' + s[b:]
write('src/mos.s65', s)
u = read('src/utils.s65')
u = u.replace('utilsUnusedBegin:', block + '\nutilsUnusedBegin:', 1)
write('src/utils.s65', u)
print('IRQ 处理区搬迁完成')
#=========================================================================
# 8. CMOS -> NMOS 指令翻译（所有 src/*.s65，最后做，避免锚点失效）
#
# 设计要点：
#  - 模拟器是严格 NMOS，一切 65C02 指令必须替换，由 64tass 重定位地址。
#  - stz/trb/tsb/ind_zp 等的 NMOS 等价序列会破坏 A/X/Y 或标志位；
#    默认用保寄存器形式（借助 $F002/$F003 暂存——模拟器无 IRQ 源，
#    不存在重入问题），标志位则做前向活性审计，只在可能被读取时
#    才用保标志的精确形式（省空间）。
#=========================================================================
SRCS = [f'src/{f}' for f in os.listdir(os.path.join(B, 'src')) if f.endswith('.s65')]

# 标志位读写表
NZ_W = {'lda','ldx','ldy','tax','tay','txa','tya','tsx','dex','dey','inx','iny',
        'adc','sbc','and','ora','eor','cmp','cpx','cpy','bit','asl','lsr','rol',
        'ror','inc','dec','pla','plp','rti'}
N_R = {'bpl','bmi'}
Z_R = {'beq','bne'}
NZ_R = N_R | Z_R
C_W = {'clc','sec','adc','sbc','cmp','cpx','cpy','asl','lsr','rol','ror','plp','rti'}
C_R = {'bcc','bcs','adc','sbc','rol','ror'}
V_W = {'clv','adc','sbc','bit','plp','rti'}
V_R = {'bvs','bvc'}
FLAG_RW = {'NZ': (NZ_W, NZ_R), 'N': (NZ_W, N_R), 'C': (C_W, C_R), 'V': (V_W, V_R)}
CTRL = {'jsr','jmp','rts','rti','brk'}

def flag_live(lines, i, flag, stop_at=(), jsr_live=True, window=24):
    """从第 i+1 行起前向扫描（最多 24 条有效指令），判断 flag 是否可能
    在重新写入前被读取。乐观策略：标签/伪指令透明；分支只按其所读
    标志判断；jmp/rts/rti 一律视为 live；jsr 由 jsr_live 决定；
    遇到 stop_at 中的指令（如配对的 plx）视为 dead。"""
    W, R = FLAG_RW[flag]
    j, n = i + 1, 0
    while j < len(lines) and n < window:
        t = lines[j].strip()
        if t == '' or t.startswith(';') or t.startswith('.'):
            j += 1
            continue
        m = re.match(r'^(?:[A-Za-z_][\w.]*:\s*)?([a-z]{3})\b', t)
        if not m:
            j += 1  # 纯标签行：透明
            continue
        op = m.group(1)
        if op in stop_at:
            return False
        if op in CTRL:
            if op == 'jsr' and not jsr_live:
                j += 1
                n += 1
                continue
            return True
        if op == 'php':
            return True
        if op == 'plp':
            return False
        if op in R:
            return True
        if op in W:
            return False
        j += 1
        n += 1
    return False

stats = {}
def bump(k, n=1):
    stats[k] = stats.get(k, 0) + n

def translate(path):
    lines = read(path).split('\n')
    out = []
    for i, ln in enumerate(lines):
        # 指令行：缩进 + 助记符。注释/标签行不碰。
        m = re.match(r'^(\s+)([a-z]{3})\b(.*?)(\s*;.*)?$', ln)
        if not m:
            out.append(ln)
            continue
        ind, op, rest, com = m.group(1), m.group(2), m.group(3), m.group(4) or ''
        operand = rest.strip()
        emit = None
        if op == 'bra':
            emit = [f'{ind}jmp {operand}{com}']
            bump('bra')
        elif op in ('phx', 'phy') and operand == '':
            if flag_live(lines, i, 'NZ', stop_at={'plx' if op=='phx' else 'ply'}, jsr_live=False):
                # 精确形式：A/P 全保留（借助 $F002/$F003）
                emit = [f'{ind}sta $f002{com}', f'{ind}php',
                        f'{ind}pla', f'{ind}sta $f003',
                        f'{ind}txa' if op=='phx' else f'{ind}tya',
                        f'{ind}pha', f'{ind}lda $f003',
                        f'{ind}pha', f'{ind}lda $f002',
                        f'{ind}plp']
                bump(op + '_exact')
            else:
                # 保 A 形式（末条 lda 破坏 NZ，该站点不读 NZ）
                emit = [f'{ind}sta $f002{com}',
                        f'{ind}txa' if op=='phx' else f'{ind}tya',
                        f'{ind}pha', f'{ind}lda $f002']
                bump(op + '_mid')
        elif op == 'plx' and operand == '':
            emit = [f'{ind}pla{com}', f'{ind}tax']
            bump('plx')
        elif op == 'ply' and operand == '':
            emit = [f'{ind}pla{com}', f'{ind}tay']
            bump('ply')
        elif op == 'stz':
            if flag_live(lines, i, 'NZ', jsr_live=False, window=12):
                # 精确形式：A/P 全保留
                emit = [f'{ind}sta $f002{com}', f'{ind}php',
                        f'{ind}lda #$00', f'{ind}sta {operand}',
                        f'{ind}lda $f002', f'{ind}plp']
                bump('stz_exact')
            else:
                # 保 A 形式（pla 会破坏 NZ，该站点不读 NZ）
                emit = [f'{ind}pha{com}', f'{ind}lda #$00',
                        f'{ind}sta {operand}', f'{ind}pla']
                bump('stz_mid')
        elif op in ('trb', 'tsb'):
            if flag_live(lines, i, 'NZ', jsr_live=False, window=8):
                # 精确形式：Z 来自 A AND M_old，A/P 全保留
                if op == 'trb':
                    mid = [f'{ind}eor #$ff', f'{ind}and {operand}']
                else:
                    mid = [f'{ind}ora {operand}']
                emit = [f'{ind}sta $f002{com}',
                        f'{ind}and {operand}',
                        f'{ind}php',
                        f'{ind}lda $f002'] + mid + [
                        f'{ind}sta {operand}',
                        f'{ind}lda $f002',
                        f'{ind}plp']
                bump(op + '_exact')
            else:
                # 简式：A 保留，NZ 不准确（该站点不读标志）
                if op == 'trb':
                    emit = [f'{ind}pha{com}', f'{ind}eor #$ff',
                            f'{ind}and {operand}', f'{ind}sta {operand}',
                            f'{ind}pla']
                else:
                    emit = [f'{ind}pha{com}', f'{ind}ora {operand}',
                            f'{ind}sta {operand}', f'{ind}pla']
                bump(op + '_short')
        elif op == 'bit':
            if operand.startswith('#'):
                if flag_live(lines, i, 'N', jsr_live=False):
                    # 精确形式：N/V 保持原值，Z 来自 A AND imm
                    emit = [f'{ind}sta $f002{com}', f'{ind}php',
                            f'{ind}and {operand}', f'{ind}php',
                            f'{ind}pla', f'{ind}and #$02',
                            f'{ind}sta $f003', f'{ind}pla',
                            f'{ind}and #$fd', f'{ind}ora $f003',
                            f'{ind}pha', f'{ind}lda $f002',
                            f'{ind}plp']
                    bump('bit_imm_exact')
                else:
                    # 简式：Z 精确，V 保持，N 不准（该站点不读 N）
                    emit = [f'{ind}sta $f002{com}', f'{ind}and {operand}',
                            f'{ind}php', f'{ind}lda $f002', f'{ind}plp']
                    bump('bit_imm_short')
            elif operand.endswith(',x'):
                # bit mem,x：N/V 来自内存、Z 来自 A AND M、A 保留（精确）
                base = operand[:-2]
                emit = [f'{ind}sta $f002{com}', f'{ind}lda {base},x',
                        f'{ind}sta $f003', f'{ind}lda $f002',
                        f'{ind}bit $f003']
                bump('bit_x')
        elif op == 'inc' and operand == 'a':
            # 内存形式：NZ 来自结果、C/V 保持、A 不变（精确，仅 7 字节）
            emit = [f'{ind}sta $f002{com}', f'{ind}inc $f002',
                    f'{ind}lda $f002']
            bump('inc_a')
        elif op == 'dec' and operand == 'a':
            emit = [f'{ind}sta $f002{com}', f'{ind}dec $f002',
                    f'{ind}lda $f002']
            bump('dec_a')
        elif op in ('lda', 'sta', 'ora', 'and', 'eor', 'adc', 'sbc', 'cmp'):
            mm = re.match(r'^\(([^),]+)\)$', operand)
            if mm:
                zp = mm.group(1)
                if not flag_live(lines, i, 'NZ', jsr_live=False):
                    # 保 Y 形式（末条 ldy 破坏 NZ，该站点不读 NZ）
                    emit = [f'{ind}sty $f002{com}', f'{ind}ldy #$00',
                            f'{ind}{op} ({zp}),y', f'{ind}ldy $f002']
                    bump('ind_zp_mid')
                else:
                    # 精确形式：Y 保留，NZ 与目标指令一致
                    emit = [f'{ind}sty $f002{com}', f'{ind}ldy #$00',
                            f'{ind}{op} ({zp}),y', f'{ind}php',
                            f'{ind}ldy $f002', f'{ind}plp']
                    bump('ind_zp_exact')
        elif op == 'jmp':
            mm = re.match(r'^\(([^),]+),\s*x\)$', operand)
            if mm:
                a = mm.group(1)
                emit = [f'{ind}php{com}', f'{ind}pha',
                        f'{ind}lda {a}+1,x', f'{ind}sta $f003',
                        f'{ind}lda {a},x', f'{ind}sta $f002',
                        f'{ind}pla', f'{ind}plp',
                        f'{ind}jmp ($f002)']
                bump('jmp_absx')
        if emit is None:
            out.append(ln)
        else:
            out.extend(emit)
    write(path, '\n'.join(out))

for p in SRCS:
    translate(p)
print('指令翻译:', stats)

#=========================================================================

PYEOF

#-------------------------------------------------------------------------
# 汇编（两遍：第一遍定位 $F000，第二遍打 UART 孔）
#-------------------------------------------------------------------------
cd "$BUILD"
TASSFLAGS="--m6502 --long-branch --nostart -Wall -q --case-sensitive --line-numbers --verbose-list"
"$TASS" $TASSFLAGS mos320nt.s65 -L mos320nt.full.lst \
    --output-section mos -o mos.rom --output-section utils -o utils.rom \
    -l pass1.lbl --dump-labels

python3 - << 'PYEOF'
import re

# 第一步：从 listing 找 mos 段里第一条触及 $F000+ 的指令地址
straddle = None
for ln in open('mos320nt.full.lst'):
    m = re.match(r'^\d+(?::\d+)?\t[.>]([0-9a-f]{4})\t+([0-9a-f]{2}(?: [0-9a-f]{2})*)\t', ln)
    if m:
        addr = int(m.group(1), 16)
        nbytes = len(m.group(2).split())
        if 0xC000 <= addr < 0xFF00 and nbytes > 0 and addr + nbytes > 0xF000:
            straddle = addr
            break
assert straddle is not None, '未找到 $F000 跨界点'

# 第二步：从 labels dump 找 mos 段里地址 <= straddle 的最近标签（含文件:行号）
best = None
for ln in open('pass1.lbl'):
    m = re.match(r'^(src/[\w.]+\.s65|mos320nt\.s65):(\d+):\d+: [\w.]+ = \$(\w+)$', ln)
    if m:
        a = int(m.group(3), 16)
        if 0xC000 <= a <= straddle and (best is None or a > best[2]):
            best = (m.group(1), int(m.group(2)), a)
assert best, '未找到孔位锚点标签'
fn, lineno, addr = best
print(f'UART 孔插入点: {fn}:{lineno} (标签地址 ${addr:04x}, 跨界地址 ${straddle:04x})')
lines = open(fn).read().split('\n')
hole = ['                ; EMU: UART 孔——$F000-$F003 不放代码（$F000/$F001 是模拟器串口寄存器，',
        '                ; $F002/$F003 留作 trb/tsb 翻译的暂存字节）',
        '                .cerror *>$f000,"UART 孔锚点位置错误"',
        '                *=$f004',
        '']
lines[lineno-1:lineno-1] = hole
open(fn, 'w').write('\n'.join(lines))
print('UART 孔已插入')
PYEOF

"$TASS" $TASSFLAGS mos320nt.s65 -L mos320nt.full.lst \
    --output-section mos -o mos.rom --output-section utils -o utils.rom

#-------------------------------------------------------------------------
# 生成 64KB 镜像
#-------------------------------------------------------------------------
python3 - << 'PYEOF'
mos = open('/tmp/acornmos_emu_build/mos.rom', 'rb').read()
utils = open('/tmp/acornmos_emu_build/utils.rom', 'rb').read()
assert len(mos) == 16384, f'mos.rom 大小异常: {len(mos)}'
assert len(utils) <= 16384, f'utils.rom 超出 16KB: {len(utils)}'
img = bytearray(0x10000)
img[0x8000:0x8000+len(utils)] = utils
img[0xC000:0x10000] = mos
# $F000-$F003 空洞字节清 0（$F000/$F001 反正被模拟器拦截，$F002/$F003 是暂存）
for a in range(0xF000, 0xF004):
    img[a] = 0
out = '/home/abc/6502/OS/acornmos/ACORNMOS_EMU.bin'
open(out, 'wb').write(img)
print(f'镜像: {out}')
print(f'  utils @ $8000-$BFFF, mos @ $C000-$FFFF')
print(f'  复位向量: ${img[0xFFFD]:02x}{img[0xFFFC]:02x}')
PYEOF

echo "运行: /home/abc/6502/build/6502 /home/abc/6502/OS/acornmos/ACORNMOS_EMU.bin"
