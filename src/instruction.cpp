#include "instruction.hpp"
opcode instruction::GetOpcode() const
{
    return OP;
}
mode instruction::GetMode() const
{
    return MODE;
}
std::uint8_t instruction::GetBytes() const
{
    return bytes;
}
std::uint8_t instruction::GetCycles() const
{
    return cycles;
}
instruction::instruction(opcode InputOpcode, mode InputMode, std::uint8_t InputBytes, std::uint8_t InputCycles)
{
    OP = InputOpcode;
    MODE = InputMode;
    this->bytes = InputBytes;
    this->cycles = InputCycles;
}
