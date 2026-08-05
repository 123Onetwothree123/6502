#!/bin/bash
# 构建 6502 模拟器版 Tali Forth 2（scotws/TaliForth2，py65mon 平台）
# 依赖: Ophis（默认用 /tmp 下克隆的；可用 OPHIS= 覆盖）
#
# 适配要点：
#  1. Tali Forth 2 是 65C02 代码，模拟器是严格 NMOS —— 文本级翻译全部
#     CMOS 指令（bra/phx/phy/plx/ply/stz/trb/tsb/inc/dec/(zp) 间接/
#     jmp (abs,x)），并用前向活性审计决定是否需要保标志的精确形式，
#     然后交给 Ophis 重新汇编、自动重定位。
#  2. py65 平台的输入是读 $F004 —— 改成读 $F000 自旋 + $F001 取字符的
#     阻塞读；输出本来就是写 $F001，原生兼容。
#  3. py65 布局把内核放在 $F010+，$F000-$F001（模拟器 UART）天然落在
#     空隙里；构建时断言没有任何代码/数据覆盖这两个地址。
#  4. 翻译用的 $F002/$F003 暂存字节位于镜像填充区（不会被执行），
#     模拟器没有 IRQ 源，不存在重入问题。
set -e
cd "$(dirname "$0")/.."

OPHIS=${OPHIS:-/tmp/ophis-src/bin/ophis}
BUILD=/tmp/taliforth2_emu_build
rm -rf "$BUILD"
mkdir -p "$BUILD/platform"
cp *.asm forth_words.asc user_words.asc "$BUILD/"
cp platform/platform-py65mon.asm "$BUILD/platform/"

#-------------------------------------------------------------------------
# 文本补丁
#-------------------------------------------------------------------------
python3 - << 'PYEOF'
import re, os

B = '/tmp/taliforth2_emu_build'

def read(p):
    return open(os.path.join(B, p)).read()

def write(p, s):
    open(os.path.join(B, p), 'w').write(s)

#=========================================================================
# 1. 输入例程：py65 的 $F004 阻塞读 -> 模拟器 $F000 状态 + $F001 取字符
#=========================================================================
s = read('platform/platform-py65mon.asm')
old = '''_loop:
                lda $f004
                beq _loop
                rts'''
new = '''_loop:
                lda $f000       ; EMU: 输入状态（0=无字符，1=有字符）
                beq _loop
                lda $f001       ; EMU: 取出一个字符
                rts'''
assert old in s, '未找到 kernel_getc 补丁锚点'
s = s.replace(old, new, 1)
# 横幅注明模拟器版本
s = s.replace('Tali Forth 2 default kernel for py65mon (18. Feb 2018)',
              'Tali Forth 2 (emu6502 NMOS port)')
write('platform/platform-py65mon.asm', s)
print('输入例程补丁完成')

#=========================================================================
# 2. CMOS -> NMOS 指令翻译（所有 .asm）
#
# 简式翻译保 A/Y（借助 $F002/$F003 暂存），标志位做前向活性审计，
# 只在可能被读取时才用保标志的精确形式（省空间）。
#=========================================================================
SRCS = [f for f in os.listdir(B) if f.endswith('.asm')] + ['platform/platform-py65mon.asm']

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
    """从第 i+1 行起前向扫描（最多 window 条有效指令），判断 flag 是否
    可能在重新写入前被读取。乐观策略：标签/伪指令透明；分支只按其
    所读标志判断；jmp/rts/rti 一律视为 live；jsr 由 jsr_live 决定。"""
    W, R = FLAG_RW[flag]
    j, n = i + 1, 0
    while j < len(lines) and n < window:
        t = lines[j].strip()
        if t == '' or t.startswith(';') or t.startswith('.'):
            j += 1
            continue
        m = re.match(r'^(?:[A-Za-z_][\w.]*:\s*)?([a-z]{3})\b', t)
        if not m:
            j += 1
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
        # 指令行：缩进（或匿名标签 * 前缀）+ 助记符。注释/标签行不碰。
        m = re.match(r'^(\s+|\*\s+)([a-z]{3})\b(.*?)(\s*;.*)?$', ln)
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
                # 精确形式：A/P 全保留
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
                # 保 A 形式（pla 破坏 NZ，该站点不读 NZ）
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
        elif op in ('inc', 'dec') and operand in ('a', ''):
            # 累加器形式 -> 内存形式：NZ 来自结果、C/V 保持、A 不变（精确）
            emit = [f'{ind}sta $f002{com}', f'{ind}{op} $f002',
                    f'{ind}lda $f002']
            bump(op + '_a')
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
PYEOF

#-------------------------------------------------------------------------
# 汇编
#-------------------------------------------------------------------------
cd "$BUILD"
"$OPHIS" -l listing.txt -m labelmap.txt -o taliforth-emu.bin -c platform/platform-py65mon.asm

#-------------------------------------------------------------------------
# 生成 64KB 镜像 + 校验
#-------------------------------------------------------------------------
python3 - << 'PYEOF'
import re

code = open('/tmp/taliforth2_emu_build/taliforth-emu.bin', 'rb').read()
assert len(code) == 32768, f'输出大小异常: {len(code)}'

# 1. 确认 $F000/$F001 没有代码或数据（必须是填充 0）
assert code[0x7000] == 0 and code[0x7001] == 0, \
    f'$F000/$F001 被占用: {code[0x7000]:02x} {code[0x7001]:02x}'

# 2. 确认 listing 中 $F000-$F001 只有填充 0，没有代码/数据字节
for ln in open('/tmp/taliforth2_emu_build/listing.txt'):
    m = re.match(r'\s*([0-9A-Fa-f]{4})\s+((?:[0-9A-Fa-f]{2} )+)', ln)
    if m:
        a = int(m.group(1), 16)
        if a in (0xF000, 0xF001):
            assert set(m.group(2).split()) == {'00'}, f'$F000/$F001 有非零内容: {ln}'
print('$F000-$F001 孔洞校验通过')

# 3. 确认没有残留 65C02 指令（反汇编列）
bad = []
for ln in open('/tmp/taliforth2_emu_build/listing.txt'):
    m = re.search(r'\b(BRA|STZ|PHX|PHY|PLX|PLY|TRB|TSB)\b', ln)
    if m:
        bad.append(ln.strip())
assert not bad, f'残留 65C02 指令: {bad[:5]}'
print('65C02 指令清零校验通过')

img = bytearray(0x10000)
img[0x8000:0x10000] = code
out = '/home/abc/6502/OS/taliforth2/TALIFORTH2_EMU.bin'
open(out, 'wb').write(img)
print(f'镜像: {out}')
print(f'  复位向量: ${img[0xFFFD]:02x}{img[0xFFFC]:02x}')
PYEOF

echo "运行: /home/abc/6502/build/6502 /home/abc/6502/OS/taliforth2/TALIFORTH2_EMU.bin"
