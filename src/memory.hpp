#ifndef MEMORY_HPP
#define MEMORY_HPP
#include <array>
#include <cstdint>
#include <vector>
#include <generated/autoconf.h>
#ifdef CONFIG_UART
#include "peripheral/uart/uart.hpp"
#endif
class memory
{
private:
    std::array<std::uint8_t, CONFIG_MEMORY_SIZE> data{};
#ifdef CONFIG_UART
    uart UART;
#endif

public:
    memory() = default;
    ~memory() = default;
    std::uint8_t read(std::uint16_t address) const;
    void write(std::uint16_t address, std::uint8_t value);
    void write(const std::vector<std::uint8_t> &image, std::uint16_t base);
    std::size_t size() const;
};
#endif
