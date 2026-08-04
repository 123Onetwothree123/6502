#include "sdb_command_context.hpp"

SDBCommandContext::SDBCommandContext(CentralProcessingUnit &InputCPU, memory &InputMemory)
    : CPU{InputCPU}, Memory{InputMemory}
{
}
CentralProcessingUnit &SDBCommandContext::GetCPU() const noexcept
{
    return CPU;
}
memory &SDBCommandContext::GetMemory() const noexcept
{
    return Memory;
}
