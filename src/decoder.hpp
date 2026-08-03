#ifndef DECODER_HPP
#define DECODER_HPP
#include <cstdint>
#include <array>
#include "instruction.hpp"
class decoder
{
private:
    static const std::array<instruction, 256> table;

public:
    decoder() = default;
    ~decoder() = default;
    instruction decode(std::uint8_t opcode) const;
};
#endif