/* llvm-mos 链接脚本 —— 6502 模拟器（64KiB 纯 RAM + $F001 UART + $FFFC 复位向量）
 *
 * 参考 llvm-mos-sdk 的 mos-platform/sim/link.ld。
 * 注意：这里不用 sim 平台的 OUTPUT_FORMAT（那是 sim65 专用格式），
 * 而是输出普通 ELF，再用 llvm-objcopy 转成 ProgramLoader 认识的格式。
 *
 * 用法（已用 llvm-mos 23.0.0git 实测，AUR: llvm-mos-bin，装在 /opt/llvm-mos）：
 * 一、构建 SDK libc（printf 需要，AUR 没有 SDK 包，只能自建）：
 *   git clone https://github.com/llvm-mos/llvm-mos-sdk
 *   cmake -B sdk-build -S llvm-mos-sdk \
 *         -DLLVM_MOS_C_COMPILER=/opt/llvm-mos/bin/clang \
 *         -DLLVM_MOS_CXX_COMPILER=/opt/llvm-mos/bin/clang++ \
 *         -DLLVM_MOS_ASM_COMPILER=/opt/llvm-mos/bin/clang \
 *         -DLLVM_MOS_BOOTSTRAP_COMPILER=OFF -DLLVM_MOS_BUILD_EXAMPLES=OFF
 *   cmake --build sdk-build --target mos-platform
 *   产物：sdk-build/mos-platform/build/install/mos-platform/{common,sim}/lib/
 * 二、编译链接（LIB 指向上面 common/lib，INC 指向 common/include）：
 *   export PATH=/opt/llvm-mos/bin:$PATH
 *   clang --target=mos-none-elf -std=gnu99 -O2 -nostdlib -ffreestanding -I $INC \
 *         -c link/llvm-mos/crt0.S -o crt0.o
 *   clang --target=mos-none-elf -std=gnu99 -O2 -nostdlib -ffreestanding -I $INC \
 *         -c link/llvm-mos/write.c -o write.o
 *   clang --target=mos-none-elf -std=gnu99 -O2 -nostdlib -ffreestanding -I $INC \
 *         -c main.c -o main.o
 *   clang --target=mos-none-elf -fuse-ld=lld -nostdlib \
 *         -T link/llvm-mos/llvm-mos.ld -L link/llvm-mos/ldscripts -L $LIB \
 *         -Wl,--allow-multiple-definition \
 *         crt0.o write.o main.o -lc -lcrt -o out.elf
 *   llvm-objcopy -O ihex out.elf out.hex    # Intel HEX 带绝对地址，base=0 直接加载
 *   ./build/6502 out.hex
 *
 * 注意：
 *   - _start 由 llvm-mos 编译器驱动自动生成，按 .init.100 → .init.200 →
 *     .init.300 → .call_main 顺序执行（无 jsr 包装）；平台 crt0 见 crt0.S
 *   - printf 来自 SDK 的 common/lib/libc.a（printf.cc），其 putc 是 weak
 *     引用，由 write.c 提供 strong 的 putc/fputc/putchar 直写 $F001 UART
 *     （无缓冲，因此 crt0 结束直接 _Exit/BRK 即可，无需 flush）
 *   - --allow-multiple-definition：屏蔽 libc.a 里 sim 平台的 _Exit（它依赖
 *     sim65 寄存器接口），用 crt0.S 的 BRK 版
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
