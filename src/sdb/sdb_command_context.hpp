#ifndef SDB_COMMAND_CONTEXT_HPP
#define SDB_COMMAND_CONTEXT_HPP
#include "../CentralProcessingUnit.hpp"
#include "../memory.hpp"

class SDBCommandContext
{
private:
    CentralProcessingUnit &CPU;
    memory &Memory;

public:
    SDBCommandContext() = delete;
    ~SDBCommandContext() = default;
    SDBCommandContext(CentralProcessingUnit &InputCPU, memory &InputMemory);
    [[nodiscard]] CentralProcessingUnit &GetCPU() const noexcept;
    [[nodiscard]] memory &GetMemory() const noexcept;
};
#endif
