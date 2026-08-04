/* 6502 模拟器平台层：stdio 输出
 * 提供 strong 的 putc/fputc/putchar，SDK 的 printf.cc 用 weak 引用解析到
 * 这里，直接写 $F001 UART（无缓冲，无需 stdio-full 那套平台钩子） */
#include <stdio.h>
#include <unistd.h>

static void uart_putchar(unsigned char c)
{
    *(volatile unsigned char *)0xF001 = c;
}

int putc(int c, FILE *stream)
{
    (void)stream;
    uart_putchar((unsigned char)c);
    return c;
}

int fputc(int c, FILE *stream)
{
    return putc(c, stream);
}

int putchar(int c)
{
    return putc(c, stdout);
}

int write(int fd, const void *buf, unsigned count)
{
    const unsigned char *p = buf;
    unsigned i;
    if (fd != STDOUT_FILENO)
    {
        return -1; /* 本机没有文件系统，只支持 stdout */
    }
    for (i = 0; i < count; ++i)
    {
        uart_putchar(p[i]);
    }
    return count;
}
