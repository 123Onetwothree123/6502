#ifndef UART_HPP
#define UART_HPP
#include <cstdint>
#include <deque>

class uart
{
private:
    static constexpr std::uint16_t StatusAddress = 0xF000; // 读: 0=无输入 1=有输入
    static constexpr std::uint16_t DataAddress = 0xF001;   // 读: 取字符 写: 输出字符
    mutable std::deque<std::uint8_t> RxQueue;
    mutable bool RxEof{false};

    // 非阻塞地把 stdin 里已到达的字节搬进 RxQueue
    void PollStdin() const;

public:
    uart() = default;
    ~uart() = default;
    static bool InRange(std::uint16_t address);
    void write(std::uint16_t address, std::uint8_t value);
    std::uint8_t read(std::uint16_t address) const;
    // 把 stdin 切到非规范无回显模式（管道/重定向时自动跳过），退出或收到信号时恢复
    static void SetupStdin();
};
#endif
