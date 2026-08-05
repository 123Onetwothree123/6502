#include "uart.hpp"
#include <cstdio>
#include <cstdlib>
#include <csignal>
#include <termios.h>
#include <unistd.h>
#include <sys/select.h>

bool uart::InRange(std::uint16_t address)
{
    return address == StatusAddress || address == DataAddress;
}
void uart::write(std::uint16_t address, std::uint8_t value)
{
    if (address != DataAddress)
    {
        return; // 状态寄存器只读，写入忽略
    }
    std::putchar(value);
    std::fflush(stdout);
}
std::uint8_t uart::read(std::uint16_t address) const
{
    PollStdin();
    if (address == StatusAddress)
    {
        return RxQueue.empty() ? 0 : 1;
    }
    if (RxQueue.empty())
    {
        return 0;
    }
    const auto value{RxQueue.front()};
    RxQueue.pop_front();
    return value;
}
void uart::PollStdin() const
{
    while (!RxEof)
    {
        fd_set Fds;
        FD_ZERO(&Fds);
        FD_SET(STDIN_FILENO, &Fds);
        timeval Timeout{0, 0};
        if (::select(STDIN_FILENO + 1, &Fds, nullptr, nullptr, &Timeout) <= 0)
        {
            break;
        }
        std::uint8_t Buffer[64];
        const auto Count{::read(STDIN_FILENO, Buffer, sizeof(Buffer))};
        if (Count < 0)
        {
            break;
        }
        if (Count == 0)
        {
            RxEof = true; // 管道关闭后不再轮询
            break;
        }
        for (ssize_t i = 0; i < Count; ++i)
        {
            RxQueue.push_back(Buffer[i]);
        }
    }
}

static termios OriginalTermios{};
static bool TermiosSaved{false};
static void RestoreStdin()
{
    if (TermiosSaved)
    {
        tcsetattr(STDIN_FILENO, TCSANOW, &OriginalTermios);
        TermiosSaved = false;
    }
}
static void HandleSignal(int SignalNumber)
{
    RestoreStdin();
    std::signal(SignalNumber, SIG_DFL);
    std::raise(SignalNumber); // 恢复终端后按原信号自杀，退出码不变
}
void uart::SetupStdin()
{
    if (!::isatty(STDIN_FILENO))
    {
        return; // 管道/重定向：本来就能非阻塞轮询，不动 termios
    }
    if (::tcgetattr(STDIN_FILENO, &OriginalTermios) != 0)
    {
        return;
    }
    TermiosSaved = true;
    std::atexit(RestoreStdin);
    std::signal(SIGINT, HandleSignal);
    std::signal(SIGTERM, HandleSignal);
    std::signal(SIGHUP, HandleSignal);
    std::signal(SIGQUIT, HandleSignal);
    termios Raw{OriginalTermios};
    Raw.c_lflag &= ~(ICANON | ECHO); // 逐字符立即送达 + 不回显（guest 自己回显）
    Raw.c_cc[VMIN] = 0;              // read 立即返回
    Raw.c_cc[VTIME] = 0;
    ::tcsetattr(STDIN_FILENO, TCSANOW, &Raw);
}
