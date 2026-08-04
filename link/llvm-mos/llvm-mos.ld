/* llvm-mos 链接脚本 —— 6502 模拟器（64KiB 纯 RAM + $F001 UART + $FFFC 复位向量）
 *
 * 参考 llvm-mos-sdk 的 mos-platform/sim/link.ld。
 * 注意：这里不用 sim 平台的 OUTPUT_FORMAT（那是 sim65 专用格式），
 * 而是输出普通 ELF，再用 llvm-objcopy 转成 ProgramLoader 认识的格式。
 *
 * 用法（假设已安装 llvm-mos 工具链）：
 *   clang --target=mos-none-elf -std=gnu99 -O2 \
 *         -nostdlib -ffreestanding \
 *         -T link/llvm-mos/llvm-mos.ld -L link/llvm-mos/ldscripts \
 *         main.c -o out.elf
 *   llvm-objcopy -O ihex out.elf out.hex    # 推荐：Intel HEX 带绝对地址，base=0 直接加载
 *   llvm-objcopy -O binary out.elf out.bin  # 备用：bin 从 $0200 起，需 ProgramLoader base=0x0200
 *   ./build/6502 out.hex
 *
 * 内存布局（与 src/memory.cpp 一致）：
 *   $0000-$00FF  零页（imag-regs 占用 $00-$1F，其余给 C 程序）
 *   $0100-$01FF  硬件栈（S 寄存器索引，复位后 S=$FD）
 *   $0200-$EFFF  代码/数据（$F001 是 UART 寄存器，因此 RAM 止于 $F000）
 *   $FFFA-$FFFF  向量区：NMI $FFFA / RESET $FFFC / IRQ $FFFE
 */

/* 零页伪寄存器（llvm-mos 约定 $00-$1F），c.ld 依赖 */
__rc0 = 0x00;
INCLUDE imag-regs.ld
ASSERT(__rc31 == 0x001f, "Inconsistent zero page map.")

MEMORY {
    zp : ORIGIN = __rc31 + 1, LENGTH = 0x100 - (__rc31 + 1)
    ram (rw) : ORIGIN = 0x0200, LENGTH = 0xF000 - 0x0200
    vec (rw) : ORIGIN = 0xFFFA, LENGTH = 0x0006
}

REGION_ALIAS("c_readonly", ram)
REGION_ALIAS("c_writeable", ram)

SECTIONS {
    INCLUDE c.ld

    /* 向量区：_start 由 llvm-mos 编译器驱动自动生成 */
    .vectors 0xFFFA : {
        SHORT(0)
        SHORT(_start)
        SHORT(0)
    } > vec
}

/* 硬件栈顶：SP 初始化到 $01FF（栈占 $0100-$01FF） */
__stack = 0x01FF;
