#include <format>
#include "cpu6502_evaluation_context.hpp"
#include "expressions/ExpressionError.hpp"

CPU6502EvaluationContext::CPU6502EvaluationContext(CentralProcessingUnit &InputCPU, memory &InputMemory)
    : CPU{InputCPU}, Memory{InputMemory}
{
}
std::uint32_t CPU6502EvaluationContext::ReadRegister(std::string_view name) const
{
    if (name == "$pc" || name == "pc")
    {
        return CPU.GetRegisterPC();
    }
    if (name == "$a" || name == "a")
    {
        return CPU.GetRegister(A);
    }
    if (name == "$x" || name == "x")
    {
        return CPU.GetRegister(X);
    }
    if (name == "$y" || name == "y")
    {
        return CPU.GetRegister(Y);
    }
    if (name == "$s" || name == "s")
    {
        return CPU.GetRegister(S);
    }
    if (name == "$p" || name == "p")
    {
        return CPU.GetRegister(P);
    }
    throw ExpressionError(std::format("{}是无效的寄存器名字", std::string(name)));
}
std::uint32_t CPU6502EvaluationContext::ReadMemory(std::uint32_t address) const
{
    return Memory.read(static_cast<std::uint16_t>(address & 0xFFFF));
}
std::uint32_t CPU6502EvaluationContext::GetPC() const
{
    return CPU.GetRegisterPC();
}
