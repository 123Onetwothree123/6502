#include "memory.hpp"
std::size_t memory::size() const
{
    return data.size();
}
std::uint8_t memory::read(std::uint16_t address) const
{
    return data[address];
}
void memory::write(std::uint16_t address, std::uint8_t value)
{
    data[address] = value;
}
