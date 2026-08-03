#ifndef OPERAND_HPP
#define OPERAND_HPP
#include "kind.hpp"
class operand
{
private:
    kind KIND;
    std::uint16_t value;

public:
    operand() = default;
    ~operand() = default;
    kind GetKind() const;
    std::uint16_t GetValue() const;
    operand(kind InputKind, std::uint16_t InputValue);
};
#endif