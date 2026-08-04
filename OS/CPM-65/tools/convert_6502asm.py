#!/usr/bin/env python3
"""CPM-65 源码转换器：6502MASM 语法 -> xa 语法 + 6502 模拟器移植补丁
用法: python3 tools/convert_6502asm.py"""
import re

MAP = {'ORG': 'org', 'DB': 'byt', 'DW': 'word', 'DD': 'big', 'DS': 'dsb'}
FILES = ['System/BIOS.ASM', 'System/BDOS.ASM', 'System/CCP.ASM', 'System/BOOT.ASM']


def conv(f):
    dst = f.replace('.ASM', '.xa.asm')
    s = open(f).read()
    out = []
    for line in s.split('\n'):
        m = re.match(r'^(\s*)(LSR|ASL|ROL|ROR)\s+A(\s*;.*)?$', line)
        if m:
            out.append(m.group(1) + m.group(2).lower() + (m.group(3) or ''))
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+(LSR|ASL|ROL|ROR)\s+A(\s*;.*)?$', line)
        if m:
            out.append(m.group(1) + ':')
            out.append('        ' + m.group(2).lower() + (m.group(3) or ''))
            continue
        m = re.match(r'^(\s*)(ORG|DB|DW|DD|DS)(\s+.*)$', line)
        if m:
            ind, op, rest = m.groups()
            if op == 'DD':
                expr = rest.split(';')[0].strip()
                out.append(f"{ind}.byt >{expr}, <{expr} ;大端表项")
            else:
                out.append(ind + '.' + MAP[op] + rest)
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+(ORG|DB|DW|DD|DS)\s+(\S.*)$', line)
        if m:
            label, op, rest = m.groups()
            out.append(label + ':')
            if op == 'DD':
                expr = rest.split(';')[0].strip()
                out.append('.byt >' + expr + ', <' + expr + ' ;大端表项')
            else:
                out.append('.' + MAP[op] + ' ' + rest)
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+EQU\s+(.*)$', line)
        if m:
            out.append(m.group(1) + ' = ' + m.group(2))
            continue
        out.append(line)
    txt = '\n'.join(out)
    # --- 通用移植修正 ---
    txt = txt.replace('.byt 128*32-32/8-1/8 ;BATSIZ', '.word (128*32-32/8-1)/8 ;BATSIZ')
    txt = txt.replace('.byt BATSIZ', '.word BATSIZ')
    txt = re.sub(r'LDA #CCP$', 'LDA #<CCP', txt, flags=re.M)
    txt = re.sub(r'LDX #DPH([AE])\b', r'LDX #<DPH\1', txt)
    txt = txt.replace('LDY #0-6', 'LDY #<-6').replace('LDY #0-4', 'LDY #<-4')
    txt = re.sub(r"#'(.)", r"#'\1'", txt)
    txt = re.sub(r'(LDA|LDX|LDY) #([A-Za-z_][A-Za-z0-9_]*)', r'\1 #<\2', txt)
    open(dst, 'w').write(txt)
    print('转换', f)


def patch_bios():
    b = 'System/BIOS.xa.asm'
    s = open(b).read()
    emu_console = '''
; --- 6502 模拟器控制台：$F001 UART 输出，无输入 ---
EMU_CONST:
	LDA #0			;无输入
	RTS
EMU_CONIN:
	LDA #0			;无输入，返回 0
	RTS
EMU_CONOUT:
	STA $F001		;输出到模拟器 UART
	RTS
'''
    s = s.replace('''FBIOS	JMP BOOT		; 00
	JMP WBOOT		; 01
	JMP ROM_CONST		; 02
	JMP ROM_CONIN		; 03
	JMP ROM_CONOUT		; 04
	JMP ROM_LIST		; 05''', '''FBIOS	JMP BOOT		; 00
	JMP WBOOT		; 01
	JMP EMU_CONST		; 02
	JMP EMU_CONIN		; 03
	JMP EMU_CONOUT		; 04
	JMP ROM_LIST		; 05''')
    start = s.find('BOOT\tLDA #$4C')
    end = s.find('WBOOT\tLDA DRIVE')
    new_boot = 'BOOT\tLDA #$4C\t\t;SET JMP BDOS\n' + \
               '\tSTA JPBDOS\n' + \
               '\tLDA #<CCP\n' + \
               '\tSTA JPBDOS+1\n' + \
               '\tLDA #>CCP\n' + \
               '\tSTA JPBDOS+2\n' + \
               '\tJMP $D803\t\t;模拟器：直接启动 CCP 入口（无磁盘）\n\n'
    s = s[:start] + emu_console + new_boot + s[end:]
    s = re.sub(r'WBOOT\tLDA DRIVE.*?RTS\n',
               'WBOOT\tJMP $D803\t\t;模拟器：无磁盘，回 CCP 入口\n\n', s, flags=re.S)
    s += '''
; --- 6502 模拟器移植：无 I2C/SCSI/SD 硬件，stub ---
ROM_I2CRBYTE:
        sec
        rts
I2CERROR = 0
'''
    open(b, 'w').write(s)
    print('BIOS 移植补丁完成')


if __name__ == '__main__':
    for f in FILES:
        conv(f)
    patch_bios()
