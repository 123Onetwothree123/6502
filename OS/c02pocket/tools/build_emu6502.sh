#!/bin/bash
# 构建 6502 模拟器版 C02 Pocket SBC BIOS+Monitor（floobydust/C02-Pocket-SBC，C02Monitor-2.04）
# 依赖: vasm（vasm6502_oldstyle）
#
# 适配点概要：
#   1. 上游用 WDC 汇编器（PL/PW/CHIP/PASS1，.EQU/.DB/.DW/.DBYTE/.ORG/.END），
#      转成 vasm oldstyle 语法；Monitor 与 BIOS 两个文件合并为单一编译单元
#      （剔除互相冲突的 .EQU 块：BIOS 里的 M_*=$Exxx、Monitor 里的 B_*=$FFxx、
#      以及重复的 PGZERO_ST/INDEXL/INDEXH）。
#   2. Monitor 原 .ORG $E000 会与模拟器 I/O（$F000/$F001）重叠（Monitor 实际
#      延伸到约 $F3FC），整体下移到 $C000；BIOS 通过 VEC_TABLE 里的标签引用
#      Monitor 入口，重汇编后自动指向新地址。
#   3. SCC2691 UART 不存在：CHRIN/CHRIN_NW/CHROUT 换成模拟器控制台
#      （写 $F001 输出；读 $F000 自旋 + 读 $F001 阻塞取字符）。
#      8251 初始化/IRQ 收发代码保留但永不执行（对 $FE80+ 的读写是无害 RAM 访问）。
#   4. 无 2691 定时器：INTERUPT0 改成直接 JMP UART_RTC，配合模拟器环境变量
#      IRQ_INTERVAL=<指令数> 提供 jiffy clock，RTC/延时/基准计时/Uptime 可用
#      （如 IRQ_INTERVAL=12000 约等于 10ms）。不设置 IRQ_INTERVAL 时延时类
#      命令会死等（已知限制）。
#   5. 严格 NMOS：所有 65C02 指令逐处转换——BRA→JMP；STZ→LDA #0+STA；
#      PHX/PHY→TXA/TYA+PHA（A 活跃处先 STA SPARE_B0）；PLX/PLY→PLA+TAX/TAY
#      （A 活跃处先 STA SPARE_B0 缓存）；RMB7/SMB7→AND #$7F/ORA #$80；
#      RMB6/SMB6→AND #$BF/ORA #$40；BBR7/BBS7→BIT+BPL/BMI；BBR6/BBS6→BIT+
#      BVC/BVS（BIT 的 N/V 正好映射 bit7/bit6）；BBR4→LDA #$10+BIT+BEQ；
#      BBS0/1→LDA+AND+BNE；SMB0（A 活跃）→PHA+LDA+ORA+STA+PLA；
#      INC A→CLC+ADC #$01；DEC A→SEC+SBC #$01；LDA/STA/CMP (zp)→LDY #0+
#      OP (zp),Y（Y 活跃处先 STY SPARE_B0）；JMP (abs,X)→经 SPARE_B0/B1
#      构造指针后 JMP (zp)；BIT #imm→AND #imm（仅在永不执行的 UART IRQ 死代码中）。
#      数字开头的标签改名：10MS_CNT→MS10_CNT、2691_INT→INIT2691_L、2BYTSPC→BYT2SPC。
#   6. 暂存器用 BIOS 零页 SPARE_B0($FD)/SPARE_B1($FE)，均为文档化的备用字节；
#      JMP ($00FD) 低字节非 $FF，不触发 NMOS 间接跳转页回绕 bug。
set -e
cd "$(dirname "$0")/.."

BUILD=/tmp/c02pocket_emu_build
rm -rf "$BUILD"
mkdir -p "$BUILD"
cp C02Monitor-2.04/C02Monitor2b.asm C02Monitor-2.04/C02BIOS2b.asm "$BUILD/"

python3 - << 'PYEOF'
import re, sys

BUILD = '/tmp/c02pocket_emu_build'

def load(name):
    return open(f'{BUILD}/{name}', encoding='latin-1').read()

mon = load('C02Monitor2b.asm')
bio = load('C02BIOS2b.asm')

def sub1(text, old, new, tag):
    assert text.count(old) == 1, f'{tag}: 期望 1 处匹配, 实际 {text.count(old)}'
    return text.replace(old, new, 1)

# ============================================================
# 第一部分：定点替换（必须在通用规则之前执行）
# ============================================================

# ---- BIOS: 控制台 I/O 换成模拟器 $F000/$F001 ----
old = '''CHRIN_NW       CLC                      ;Clear Carry flag for no character
               LDA      ICNT            ;Get buffer count
               BNE      GET_CH          ;Branch if buffer is not empty
               RTS                      ;or return to caller
;
CHRIN          LDA      ICNT            ;Get character count
               BEQ      CHRIN           ;If zero (no character, loop back)
;
GET_CH         PHY                      ;Save Y Reg
               LDY      IHEAD           ;Get the buffer head pointer
               LDA      IBUF,Y          ;Get the character from the buffer
               INC      IHEAD           ;Increment head pointer
               RMB7     IHEAD           ;Strip off bit 7, 128 bytes only
               DEC      ICNT            ;Decrement the buffer count
;
               PLY                      ;Restore Y Reg
               SEC                      ;Set Carry flag for character available
               RTS                      ;Return to caller with character in A Reg'''
new = '''CHRIN_NW       LDA      $F000          ;EMULATOR: console input status
               BEQ      NO_CH           ;no character waiting
               LDA      $F001           ;get the character
               SEC                      ;character available
               RTS
NO_CH          CLC                      ;no character
               RTS
;
CHRIN          LDA      $F000          ;EMULATOR: wait for console input
               BEQ      CHRIN
GET_CH         LDA      $F001           ;get the character
               SEC
               RTS'''
bio = sub1(bio, old, new, 'CHRIN/CHRIN_NW')

old = '''CHROUT         PHY                      ;save Y Reg
OUTCH          LDY      OCNT            ;get character output count in buffer
               BMI      OUTCH           ;check against limit, loop back if full
;
               LDY      OTAIL           ;Get the buffer tail pointer
               STA      OBUF,Y          ;Place character in the buffer
               INC      OTAIL           ;Increment Tail pointer
               RMB7     OTAIL           ;Strip off bit 7, 128 bytes only
               INC      OCNT            ;Increment character count
;
               LDY      #%00000100      ;Get mask for xmit on
               STY      UART_COMMAND    ;Turn on xmit
;
               PLY                      ;Restore Y Reg
               RTS                      ;Return to caller'''
new = '''CHROUT         STA      $F001          ;EMULATOR: console output
               RTS                      ;(A preserved, X/Y untouched)'''
bio = sub1(bio, old, new, 'CHROUT')

# ---- BIOS: IRQ 入口直接当 jiffy clock（需 IRQ_INTERVAL 环境变量）----
old = '''INTERUPT0      LDA      UART_ISR        ;Get the UART Interrupt Status Register (4)
               CMP      #%00100000      ;Check for no active IRQ source (2)
               BEQ      REGEXT0         ;If no bits are set, exit handler (2/3)'''
new = '''INTERUPT0      JMP      UART_RTC       ;EMULATOR: periodic IRQ is the jiffy clock
               NOP                      ;(UART ISR register does not exist)
               NOP'''
bio = sub1(bio, old, new, 'INTERUPT0')

# ---- BIOS: EXE_LGDLY 的 PHX/PHY/PLX/PLY（必须保护 A）----
old = '''EXE_LGDLY      PHX                      ;Save X Reg
               PHY                      ;Save Y Reg'''
new = '''EXE_LGDLY      STA      SPARE_B0       ;Save A Reg
               TXA                      ;Save X Reg
               PHA
               TYA                      ;Save Y Reg
               PHA
               LDA      SPARE_B0        ;Restore A Reg'''
bio = sub1(bio, old, new, 'EXE_LGDLY head')
old = '''               PLY                      ;Restore Y Reg
               PLX                      ;Restore X Reg
               RTS                      ;Return to caller'''
new = '''               STA      SPARE_B0        ;Save A Reg
               PLA                      ;Restore Y Reg
               TAY
               PLA                      ;Restore X Reg
               TAX
               LDA      SPARE_B0        ;Restore A Reg
               RTS                      ;Return to caller'''
bio = sub1(bio, old, new, 'EXE_LGDLY tail')

# ---- BIOS: BRKINSTR0 入口 PLY/PLX/PLA ----
old = '''BRKINSTR0      PLY                      ;Restore Y Reg (4)
               PLX                      ;Restore X Reg (4)
               PLA                      ;Restore A Reg (4)'''
new = '''BRKINSTR0      PLA                      ;Restore Y Reg (4)
               TAY
               PLA                      ;Restore X Reg (4)
               TAX
               PLA                      ;Restore A Reg (4)'''
bio = sub1(bio, old, new, 'BRKINSTR0 head')

# ---- BIOS: BRKINSTR0 取返回地址 ----
old = '''               PLX                      ;Pull Low RETURN address from STACK then save it (4)
               STX      PCL             ;Store program counter Low byte (3)
               STX      INDEXL          ;Seed Indexl for DIS_LINE (3)
               PLY                      ;Pull High RETURN address from STACK then save it (4)
               STY      PCH             ;Store program counter High byte (3)
               STY      INDEXH          ;Seed Indexh for DIS_LINE (3)'''
new = '''               PLA                      ;Pull Low RETURN address from STACK then save it (4)
               STA      PCL             ;Store program counter Low byte (3)
               STA      INDEXL          ;Seed Indexl for DIS_LINE (3)
               PLA                      ;Pull High RETURN address from STACK then save it (4)
               STA      PCH             ;Store program counter High byte (3)
               STA      INDEXH          ;Seed Indexh for DIS_LINE (3)'''
bio = sub1(bio, old, new, 'BRKINSTR0 PC pull')

# ---- BIOS: BBR4 PREG,DO_NULL ----
old = '''               BBR4     PREG,DO_NULL    ;Check for BRK bit set (5)'''
new = '''               LDA      #$10            ;Check for BRK bit set
               BIT      PREG
               BEQ      DO_NULL'''
bio = sub1(bio, old, new, 'BBR4 PREG')

# ---- BIOS: STZ ITAIL/IHEAD/ICNT（此处 A 已为零）----
old = '''               STZ      ITAIL           ;Clear input buffer pointers (3)
               STZ      IHEAD           ; (3)
               STZ      ICNT            ; (3)'''
new = '''               STA      ITAIL           ;Clear input buffer pointers (A=0 here)
               STA      IHEAD           ;
               STA      ICNT            ;'''
bio = sub1(bio, old, new, 'STZ input ptrs')

# ---- BIOS: IRQ_VECTOR PHX/PHY（A 已入栈, 可破坏）----
old = '''               PHX                      ;Save X Reg (3)
               PHY                      ;Save Y Reg (3)'''
new = '''               TXA                      ;Save X Reg (3)
               PHA
               TYA                      ;Save Y Reg (3)
               PHA'''
bio = sub1(bio, old, new, 'IRQ_VECTOR')

# ---- BIOS: IRQ_EXIT0 PLY/PLX/PLA ----
old = '''IRQ_EXIT0      PLY                      ;Restore Y Reg (4)
               PLX                      ;Restore X Reg (4)
               PLA                      ;Restore A Reg (4)'''
new = '''IRQ_EXIT0      PLA                      ;Restore Y Reg (4)
               TAY
               PLA                      ;Restore X Reg (4)
               TAX
               PLA                      ;Restore A Reg (4)'''
bio = sub1(bio, old, new, 'IRQ_EXIT0')

# ---- BIOS: 剔除与 Monitor 重复的 M_* .EQU 块和 PGZERO_ST/INDEXL/INDEXH ----
m = re.search(r'^M_COLD_MON     \.EQU     \$E000.*?^M_CONTINUE     \.EQU     \$E05D   ;Call 31\n',
              bio, flags=re.M | re.S)
assert m, '未找到 BIOS M_* .EQU 块'
bio = bio.replace(m.group(0), '', 1)

# ---- Monitor: 剔除 BIOS_MSG 的硬编码 .EQU（以 BIOS 里的标签为准, 同为 $FFD0）----
mon = sub1(mon, 'BIOS_MSG        .EQU    $FFD0           ;BIOS Startup Message is hard-coded here\n', '', 'BIOS_MSG equ')

# ---- Monitor: 剔除与 BIOS 重复的 .EQU（保留 BIOS 侧定义；
#      注意 MATCH/SPARE_B0/SPARE_B1 两边偏移不同, Monitor 从不使用它们,
#      以 BIOS 的定义为准: MATCH=$FF, SPARE_B0=$FD, SPARE_B1=$FE）----
bio_equs = set(re.findall(r'^([A-Za-z0-9_]+)\s+\.EQU\b', bio, flags=re.M))
kept, removed = [], set()
for ln in mon.split('\n'):
    m = re.match(r'^([A-Za-z0-9_]+)\s+\.EQU\b', ln)
    if m and m.group(1) in bio_equs:
        removed.add(m.group(1))
        continue
    kept.append(ln)
mon = '\n'.join(kept)
assert len(removed) == 54, f'重复 equ 数量异常: {len(removed)}: {sorted(removed)}'

# ---- Monitor: 下移到 $C000，避开模拟器 I/O $F000/$F001 ----
mon = sub1(mon,
           '        .ORG $E000    ;6KB reserved for Monitor ($E000 through $F7FF)',
           '        .ORG $C000    ;EMULATOR: relocated from $E000 to avoid I/O at $F000/$F001',
           'Monitor ORG')

# ---- Monitor: 剔除与 BIOS 标签冲突的 B_* .EQU 块 ----
m = re.search(r'^B_Reserve00     \.EQU    \$FF00.*?^B_COLDSTRT      \.EQU    \$FF5D           ;Call 31\n',
              mon, flags=re.M | re.S)
assert m, '未找到 Monitor B_* .EQU 块'
mon = mon.replace(m.group(0), '', 1)

# ---- Monitor: DOCMD 的 JMP (MONTAB,X) ----
old = '''DOCMD           JMP     (MONTAB,X)      ;Execute command from Table'''
new = '''DOCMD           LDA     MONTAB,X        ;Get command handler address low
                STA     SPARE_B0        ;(EMULATOR: NMOS has no JMP (abs,X))
                LDA     MONTAB+1,X      ;Get command handler address high
                STA     SPARE_B1
                JMP     (SPARE_B0)      ;Execute command from Table'''
mon = sub1(mon, old, new, 'DOCMD')

# ---- Monitor: DODISL 的 JMP (HDLR_TAB,X) ----
old = '''DODISL          JMP     (HDLR_TAB,X)    ;Execute address mode handler'''
new = '''DODISL          LDA     HDLR_TAB,X      ;Get handler address low
                STA     SPARE_B0        ;(EMULATOR: NMOS has no JMP (abs,X))
                LDA     HDLR_TAB+1,X    ;Get handler address high
                STA     SPARE_B1
                JMP     (SPARE_B0)      ;Execute address mode handler'''
mon = sub1(mon, old, new, 'DODISL')

# ---- Monitor: PRBYTE/PRWORD 的 PHY（A 活跃: 65C02 PHY 不破坏 A, 转换后需显式保护）----
old = '''PRBYTE          PHA                     ;Save A register
                PHY                     ;Save Y register
PRBYT2          JSR     BIN2ASC         ;Convert A reg to 2 ASCII Hex characters'''
new = '''PRBYTE          STA     SPARE_B1        ;Save byte to convert
                PHA                     ;Save A register
                TYA                     ;Save Y register
                PHA
                LDA     SPARE_B1        ;Restore byte for conversion
PRBYT2          JSR     BIN2ASC         ;Convert A reg to 2 ASCII Hex characters'''
mon = sub1(mon, old, new, 'PRBYTE PHY')
old = '''PRWORD          PHA                     ;Save A register
                PHY                     ;Save Y register
                JSR     PRBYTE          ;Convert and print one HEX character (00-FF)'''
new = '''PRWORD          STA     SPARE_B1        ;Save high byte
                PHA                     ;Save A register
                TYA                     ;Save Y register
                PHA
                LDA     SPARE_B1        ;Get high byte
                JSR     PRBYTE          ;Convert and print one HEX character (00-FF)'''
mon = sub1(mon, old, new, 'PRWORD PHY')

# ---- Monitor: ASCLOOP PHY/PLY（PLY 时 A 活跃）----
old = '''ASCLOOP         PHY                     ;Save it to stack'''
new = '''ASCLOOP         TYA                     ;Save it to stack
                PHA'''
mon = sub1(mon, old, new, 'ASCLOOP PHY')
old = '''                PLY                     ;Get index from stack
                STA     HEXDATAH-1,Y    ;Write byte to indexed buffer location'''
new = '''                STA     SPARE_B0        ;Save converted byte
                PLA                     ;Get index from stack
                TAY
                LDA     SPARE_B0        ;Restore converted byte
                STA     HEXDATAH-1,Y    ;Write byte to indexed buffer location'''
mon = sub1(mon, old, new, 'ASCLOOP PLY')

# ---- Monitor: REG_UPT 的 PLX（A 活跃）----
old = '''                PLX                     ;Get MSG # from stack
                STA     PREG-$0E,X      ;Write register (A,X,Y,S,P) preset/result'''
new = '''                STA     SPARE_B0        ;Save entered value
                PLA                     ;Get MSG # from stack
                TAX
                LDA     SPARE_B0        ;Restore entered value
                STA     PREG-$0E,X      ;Write register (A,X,Y,S,P) preset/result'''
mon = sub1(mon, old, new, 'REG_UPT PLX')

# ---- Monitor: DO16TIME 的 PHX（A 活跃）----
old = '''DO16TIME        PHX                     ;Push message number to stack'''
new = '''DO16TIME        STA     SPARE_B0        ;Save value low byte
                TXA                     ;Push message number to stack
                PHA
                LDA     SPARE_B0        ;Restore value low byte'''
mon = sub1(mon, old, new, 'DO16TIME PHX')

# ---- Monitor: SR_CMPLP PHY/PLY（PLY 时 A 活跃）----
old = '''SR_CMPLP        PHY                     ;Save Y reg index'''
new = '''SR_CMPLP        TYA                     ;Save Y reg index
                PHA'''
mon = sub1(mon, old, new, 'SR_CMPLP PHY')
old = '''                PLY                     ;Restore Y reg index
                STA     SRBUFF,Y        ;Store in SRBUFF starting at front'''
new = '''                STA     SPARE_B0        ;Save converted byte
                PLA                     ;Restore Y reg index
                TAY
                LDA     SPARE_B0        ;Restore converted byte
                STA     SRBUFF,Y        ;Store in SRBUFF starting at front'''
mon = sub1(mon, old, new, 'SR_CMPLP PLY')

# ---- Monitor: SENGBYT 的 LDA (INDEXL)（Y 活跃, 调用方用 Y 做行内索引）----
old = '''SENRTBYT        LDA     (INDEXL)        ;Else Get byte from current pointer'''
new = '''SENRTBYT        STY     SPARE_B0        ;Save Y index
                LDY     #$00            ;Else Get byte from current pointer
                LDA     (INDEXL),Y
                LDY     SPARE_B0        ;Restore Y index'''
mon = sub1(mon, old, new, 'SENRTBYT')

# ---- Monitor: INCNDX 的 LDA (INDEXL)（保险起见保护 Y）----
old = '''INCNDX          JSR     INCINDEX        ;Increment working address pointer
                LDA     (INDEXL)        ;Read from working memory address'''
new = '''INCNDX          JSR     INCINDEX        ;Increment working address pointer
                STY     SPARE_B0        ;Save Y
                LDY     #$00            ;Read from working memory address
                LDA     (INDEXL),Y
                LDY     SPARE_B0        ;Restore Y'''
mon = sub1(mon, old, new, 'INCNDX')

# ---- Monitor: ZERO 循环（STZ $00 + DEC A + STA ($00)）----
old = '''                STZ     $00             ;Zero address low byte
                DEC     A               ;LDA #$00
ZEROLOOP        STA     ($00)           ;Write $00 to current address'''
new = '''                LDA     #$00            ;Zero address low byte
                STA     $00
                LDY     #$00            ;NMOS: index for indirect store
ZEROLOOP        STA     ($00),Y         ;Write $00 to current address'''
mon = sub1(mon, old, new, 'ZERO loop')

# ---- Monitor: COMPLP/MVNO_LP 的 BEQ QUITMV 在指令扩充后会超出相对分支范围 ----
old = '''COMPLP          LDA     LENL            ;Get low byte of length
                ORA     LENH            ;OR in High byte of length
                BEQ     QUITMV          ;If zero, nothing to compare/write'''
new = '''COMPLP          LDA     LENL            ;Get low byte of length
                ORA     LENH            ;OR in High byte of length
                BNE     CMP_START       ;If zero, nothing to compare/write
                JMP     QUITMV
CMP_START'''
mon = sub1(mon, old, new, 'COMPLP BEQ range')
old = '''MVNO_LP         LDA     LENL            ;Get length low byte
                ORA     LENH            ;OR in length high byte
                BEQ     QUITMV          ;Exit if zero bytes to move'''
new = '''MVNO_LP         LDA     LENL            ;Get length low byte
                ORA     LENH            ;OR in length high byte
                BNE     MV_START        ;Exit if zero bytes to move
                JMP     QUITMV
MV_START'''
mon = sub1(mon, old, new, 'MVNO_LP BEQ range')

# ---- Monitor: SMB0 CMDFLAG（A 里是消息号, 必须保护）----
old = '''                SMB0    CMDFLAG         ;Set bit0 of command flag'''
new = '''                PHA                     ;Save message number
                LDA     CMDFLAG         ;Set bit0 of command flag
                ORA     #$01
                STA     CMDFLAG
                PLA                     ;Restore message number'''
mon = sub1(mon, old, new, 'SMB0 CMDFLAG')

# ============================================================
# 第二部分：通用逐行规则（只作用于代码部分, 即 ';' 注释之前）
# ============================================================

def xform(text, tag):
    out = []
    for ln in text.split('\n'):
        code, sep, comment = ln.partition(';')
        newcode = code

        # WDC 伪指令 -> vasm oldstyle
        if re.match(r'^\s+(PL|PW|CHIP|PASS1)\b', newcode):
            out.append(ln.replace(newcode, '', 1) if False else ';' + ln)
            continue
        newcode = re.sub(r'^(\s*[A-Za-z0-9_]+\s+)\.EQU\b', r'\1equ', newcode)
        newcode = re.sub(r'^(\s*[A-Za-z0-9_]+\s+)\.DBYTE\s+(\S+)',
                         r'\1db (\2)>>8, (\2)&$FF', newcode)
        newcode = re.sub(r'^(\s*[A-Za-z0-9_]+\s+)\.(DB|DW|ORG)\b', r'\1\2', newcode)
        newcode = re.sub(r'^(\s+)\.DBYTE\s+(\S+)', r'\1db (\2)>>8, (\2)&$FF', newcode)
        newcode = re.sub(r'^(\s+)\.(DB|DW|ORG)\b', r'\1\2', newcode)
        newcode = re.sub(r'^(\s*)\.END\b.*$', r'\1; (END stripped for concatenated build)', newcode)

        # 立即数里的字符/高低字节操作符
        newcode = re.sub(r'#"([^"])"', lambda m: '#$%02X' % ord(m.group(1)), newcode)
        newcode = re.sub(r'#<([A-Za-z_][A-Za-z0-9_]*)', r'#\1&$FF', newcode)
        newcode = re.sub(r'#>([A-Za-z_][A-Za-z0-9_]*)', r'#\1>>8', newcode)

        # 65C02 -> NMOS 指令级转换
        newcode = re.sub(r'\bBRA\s+(\S+)', r'JMP \1', newcode)
        newcode = re.sub(r'\bINC\s+A\b', 'CLC\n               ADC #$01', newcode)
        newcode = re.sub(r'\bDEC\s+A\b', 'SEC\n               SBC #$01', newcode)
        newcode = re.sub(r'\bPHX\b', 'TXA\n               PHA', newcode)
        newcode = re.sub(r'\bPHY\b', 'TYA\n               PHA', newcode)
        newcode = re.sub(r'\bPLX\b', 'PLA\n               TAX', newcode)
        newcode = re.sub(r'\bPLY\b', 'PLA\n               TAY', newcode)
        newcode = re.sub(r'\bSTZ\s+(\S+)', r'LDA #$00\n               STA \1', newcode)
        newcode = re.sub(r'\bRMB7\s+(\S+)', r'LDA \1\n               AND #$7F\n               STA \1', newcode)
        newcode = re.sub(r'\bSMB7\s+(\S+)', r'LDA \1\n               ORA #$80\n               STA \1', newcode)
        newcode = re.sub(r'\bRMB6\s+(\S+)', r'LDA \1\n               AND #$BF\n               STA \1', newcode)
        newcode = re.sub(r'\bSMB6\s+(\S+)', r'LDA \1\n               ORA #$40\n               STA \1', newcode)
        newcode = re.sub(r'\bSMB1\s+(\S+)', r'LDA \1\n               ORA #$02\n               STA \1', newcode)
        newcode = re.sub(r'\bBBS0\s+(\S+),(\S+)', r'LDA \1\n               AND #$01\n               BNE \2', newcode)
        newcode = re.sub(r'\bBBS1\s+(\S+),(\S+)', r'LDA \1\n               AND #$02\n               BNE \2', newcode)
        newcode = re.sub(r'\bBBR7\s+(\S+),(\S+)', r'BIT \1\n               BPL \2', newcode)
        newcode = re.sub(r'\bBBS7\s+(\S+),(\S+)', r'BIT \1\n               BMI \2', newcode)
        newcode = re.sub(r'\bBBR6\s+(\S+),(\S+)', r'BIT \1\n               BVC \2', newcode)
        newcode = re.sub(r'\bBBS6\s+(\S+),(\S+)', r'BIT \1\n               BVS \2', newcode)
        newcode = re.sub(r'\bBIT\s+#(\S+)', r'AND #\1', newcode)  # 仅在永不执行的 UART IRQ 死代码中

        # 65C02 零页间接 -> NMOS (zp),Y（Y 活跃处已在定点替换中处理）;
        # 只匹配代码末尾就是 ')' 的行（已带 ,Y 的不动）；标签保留在插入的 LDY 行
        m2 = re.match(r'^(\s*(?:[A-Za-z0-9_]+\s+)?)(LDA|STA|CMP|ORA|AND|ADC|SBC|EOR)\s+\(([A-Za-z_][A-Za-z0-9_]*)\)\s*$', newcode)
        if m2:
            newcode = f'{m2.group(1)}LDY #$00\n               {m2.group(2)} ({m2.group(3)}),Y'

        out.append(newcode + (sep + comment if sep else ''))
    return '\n'.join(out)

mon = xform(mon, 'monitor')
bio = xform(bio, 'bios')

# 数字开头的标签改名（vasm 不接受）; BINARY/ASCII/SPC/RESERVE 与 vasm 指令名冲突, 一并改名
for old, new in [('10MS_CNT', 'MS10_CNT'), ('2691_INT', 'INIT2691_L'),
                 ('2BYTSPC', 'BYT2SPC'), ('3BYTSPC', 'BYT3SPC')]:
    mon = re.sub(r'\b' + old + r'\b', new, mon)
    bio = re.sub(r'\b' + old + r'\b', new, bio)
for old, new in [('BINARY', 'HEXBIN'), ('ASCII', 'NIBASC'), ('SPC', 'SP1'), ('TEXT', 'TEXTIN')]:
    mon = re.sub(r'\b' + old + r'\b', new, mon)
bio = re.sub(r'\bRESERVE\b', 'RESVD', bio)

# vasm oldstyle 把 0 开头的数当八进制: 去掉前导零（跳过含字符串的行, 如日期 "30/09/2019"）
def dezero(text):
    out = []
    for ln in text.split('\n'):
        if '"' in ln:
            out.append(ln)
            continue
        code, sep, comment = ln.partition(';')
        code = re.sub(r'\b0([0-9]+)\b', r'\1', code)
        out.append(code + (sep + comment if sep else ''))
    return '\n'.join(out)
mon = dezero(mon)
bio = dezero(bio)

# DF_TICKS 的 .EQU #100 改成 equ 100（WDC 特色写法）
bio = re.sub(r'^(DF_TICKS\s+equ\s+)#100\b', r'\g<1>100', bio, flags=re.M)

# 残留 65C02 指令检查（代码部分）
bad = re.compile(r'\b(BRA|PHX|PHY|PLX|PLY|STZ|TRB|TSB|WAI|STP|BBR[0-7]|BBS[0-7]|RMB[0-7]|SMB[0-7])\b|(LDA|STA|CMP|ORA|AND|ADC|SBC|EOR)\s+\([A-Za-z_][A-Za-z0-9_]*\)\s*$|JMP\s*\([A-Za-z_][A-Za-z0-9_]*,X\)|\bBIT\s+#')
for name, text in [('monitor', mon), ('bios', bio)]:
    for i, ln in enumerate(text.split('\n')):
        code = ln.partition(';')[0]
        if bad.search(code):
            sys.exit(f'残留 65C02 指令 {name}:{i+1}: {ln.strip()}')

# 合并为单一编译单元（Monitor 在前, BIOS 在后）
src = mon + '\n' + bio + '\n'

# 重复符号检查
equs = re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)\s+equ\b', src, flags=re.M)
dups = {e for e in equs if equs.count(e) > 1}
assert not dups, f'重复 equ 定义: {dups}'

open(f'{BUILD}/c02_all.asm', 'w', encoding='latin-1').write(src)
print('文本补丁完成（WDC->vasm 语法 / 控制台 I/O / 65C02->NMOS / 重定位 $C000）')
PYEOF

vasm6502_oldstyle -Fbin -o "$BUILD/c02_raw.bin" "$BUILD/c02_all.asm"

python3 - << 'PYEOF'
raw = open('/tmp/c02pocket_emu_build/c02_raw.bin', 'rb').read()
BASE = 0xC000   # vasm -Fbin 从最低 org（Monitor $C000）开始
assert len(raw) == 0x10000 - BASE, 'raw 大小异常: %x' % len(raw)

img = bytearray(0x10000)
img[BASE:BASE+len(raw)] = raw

rst = img[0xFFFC] | (img[0xFFFD] << 8)
assert rst == 0xFF5D, '复位向量异常: %04x' % rst   # B_COLDSTRT
nmi = img[0xFFFA] | (img[0xFFFB] << 8)
irq = img[0xFFFE] | (img[0xFFFF] << 8)
print('复位向量: $%04X  NMI: $%04X  IRQ/BRK: $%04X' % (rst, nmi, irq))
# BIOS 标语应在 $FFD0
assert img[0xFFD2:0xFFD6] == b'C02B', 'BIOS_MSG 位置异常'

open('C02POCKET_EMU.bin', 'wb').write(img)
print('镜像: C02POCKET_EMU.bin')
PYEOF
echo "运行: /home/abc/6502/build/6502 C02POCKET_EMU.bin"
echo "（可选 jiffy clock: IRQ_INTERVAL=12000 /home/abc/6502/build/6502 C02POCKET_EMU.bin）"
