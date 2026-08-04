#ifndef UART_HPP
#define UART_HPP
#include <cstdint>

class uart
{
private:
    static constexpr std::uint16_t RegisterAddress = 0xF001;

public:
    uart() = default;
    ~uart() = default;
    static bool InRange(std::uint16_t address);
    void write(std::uint16_t address, std::uint8_t value);
    std::uint8_t read(std::uint16_t address) const;
};
#endif
