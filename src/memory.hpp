#ifndef MEMORY_HPP
#define MEMORY_HPP
#include <array>
#include <cstdint>
#include <generated/autoconf.h>
class memory
{
private:
    std::array<std::uint8_t, CONFIG_MEMORY_SIZE> data{};

public:
    memory() = default;
    ~memory() = default;
    std::uint8_t read(std::uint16_t address) const;
    void write(std::uint16_t address, std::uint8_t value);
    std::size_t size() const;
};
#endif
