#ifndef CPU6502_EVALUATION_CONTEXT_HPP
#define CPU6502_EVALUATION_CONTEXT_HPP
#include "../CentralProcessingUnit.hpp"
#include "../memory.hpp"
#include "evaluation_context.hpp"

class CPU6502EvaluationContext final : public EvaluationContext
{
private:
    CentralProcessingUnit &CPU;
    memory &Memory;

public:
    CPU6502EvaluationContext() = delete;
    ~CPU6502EvaluationContext() override = default;
    CPU6502EvaluationContext(CentralProcessingUnit &InputCPU, memory &InputMemory);
    std::uint32_t ReadRegister(std::string_view name) const override;
    std::uint32_t ReadMemory(std::uint32_t address) const override;
    std::uint32_t GetPC() const override;
};
#endif
