#include "memory.hpp"
std::size_t memory::size() const
{
    return data.size();
}
std::uint8_t memory::read(std::uint16_t address) const
{
#ifdef CONFIG_UART
    if (uart::InRange(address))
    {
        return UART.read(address);
    }
#endif
    return data[address];
}
void memory::write(std::uint16_t address, std::uint8_t value)
{
#ifdef CONFIG_UART
    if (uart::InRange(address))
    {
        UART.write(address, value);
        return;
    }
#endif
    data[address] = value;
}
void memory::write(const std::vector<std::uint8_t> &image, std::uint16_t base)
{
    for (std::size_t i{0}; i < image.size() && base + i <= 0xFFFF; ++i)
    {
        const auto address{static_cast<std::uint16_t>(base + i)};
#ifdef CONFIG_UART
        if (uart::InRange(address))
        {
            continue; // 跳过I/O区，镜像不覆盖外设
        }
#endif
        data[address] = image[i];
    }
}
