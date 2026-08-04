#include <stdio.h>
#include <unistd.h>

/* 6502 模拟器 UART：向 $F001 写一个字符，模拟器输出到终端 */
static void uart_putchar(unsigned char c)
{
    *(volatile unsigned char *)0xF001 = c;
}

/* cc65 的 putchar 是 __fastcall__（参数走 A 寄存器），覆盖库实现让 printf 走 UART */
int __fastcall__ putchar(int c)
{
    uart_putchar((unsigned char)c);
    return c;
}

/* 注意：_write 不能用 C 实现（栈清理约定冲突），由 link/cc65/uart.s 提供 */

int main(void)
{
    printf("Hello World\n");
    return 0;
}
