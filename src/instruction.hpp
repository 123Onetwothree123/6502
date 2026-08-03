#ifndef INSTRUCTION_HPP
#define INSTRUCTION_HPP
#include "opcode.hpp"
#include "mode.hpp"
#include <cstdint>
class instruction
{
private:
    opcode OP;
    mode MODE;
    std::uint8_t bytes;
    std::uint8_t cycles;

public:
    instruction() = default;
    ~instruction() = default;
    opcode GetOpcode() const;
    mode GetMode() const;
    std::uint8_t GetBytes() const;
    std::uint8_t GetCycles() const;
    instruction(opcode InputOpcode, mode InputMode, std::uint8_t InputBytes, std::uint8_t InputCycles);
};
#endif