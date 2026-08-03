#include "operand.hpp"
#include <cstdint>
operand::operand(kind InputKind, std::uint16_t InputValue)
{
    KIND = InputKind;
    this->value = InputValue;
}
kind operand::GetKind() const
{
    return KIND;
}
std::uint16_t operand::GetValue() const
{
    return value;
}