#include "builtin_image.hpp"
#include <print>
const std::array<std::uint8_t, 7> builtin_image::DefaultImage{
    0xA9,
    0x00, // LDA #$00
    0x85,
    0x10, // STA $10
    0xA5,
    0x10, // LDA $10
    0x00, // BRK
};
void builtin_image::Load(memory &Memory)
{
    // 抄NEMU init_isa()的memcpy(guest_to_host(CONFIG_MBASE), img, sizeof(img))
    for (std::size_t i{0}; i < DefaultImage.size(); ++i)
    {
        Memory.write(static_cast<std::uint16_t>(i), DefaultImage[i]);
    }
    Memory.write(0xFFFC, 0x00); // 复位向量0x0000
    Memory.write(0xFFFD, 0x00);
}
void builtin_image::PrintTrapResult(const CentralProcessingUnit &CPU) const
{
    // 对应NEMU的nemu_trap检查：A == 0
    if (CPU.GetRegister(A) == 0)
    {
        std::println("HIT GOOD TRAP");
    }
    else
    {
        std::println("HIT BAD TRAP");
    }
}
