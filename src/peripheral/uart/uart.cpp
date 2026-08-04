#include "uart.hpp"
#include <cstdio>

bool uart::InRange(std::uint16_t address)
{
    return address == RegisterAddress;
}
void uart::write([[maybe_unused]] std::uint16_t address, std::uint8_t value)
{
    std::putchar(value);
    std::fflush(stdout);
}
std::uint8_t uart::read([[maybe_unused]] std::uint16_t address) const
{
    return 0;
}
