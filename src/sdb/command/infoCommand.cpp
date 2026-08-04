#include <format>
#include <print>
#include "infoCommand.hpp"
#ifdef CONFIG_WATCHPOINT
#include "../cpu6502_evaluation_context.hpp"
#include "../watchpoint_pool.hpp"
#endif

namespace
{
    void PrintRegisters(CentralProcessingUnit &CPU)
    {
        std::println("寄存器状态：");
        std::println("  PC = 0x{:04x}", CPU.GetRegisterPC());
        std::println("  A  = 0x{:02x}", CPU.GetRegister(A));
        std::println("  X  = 0x{:02x}", CPU.GetRegister(X));
        std::println("  Y  = 0x{:02x}", CPU.GetRegister(Y));
        std::println("  S  = 0x{:02x}", CPU.GetRegister(S));
        std::println("  P  = 0x{:02x}（N={} V={} D={} I={} Z={} C={}）",
                     CPU.GetRegister(P),
                     (CPU.GetRegister(P) & 0x80) ? 1 : 0,
                     (CPU.GetRegister(P) & 0x40) ? 1 : 0,
                     (CPU.GetRegister(P) & 0x08) ? 1 : 0,
                     (CPU.GetRegister(P) & 0x04) ? 1 : 0,
                     (CPU.GetRegister(P) & 0x02) ? 1 : 0,
                     (CPU.GetRegister(P) & 0x01) ? 1 : 0);
    }
}

std::string_view infoCommand::name() const noexcept
{
    return "info";
}
SDBCommandUsageList infoCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"r", "打印寄存器"},
#ifdef CONFIG_WATCHPOINT
        {"w", "打印监视点状态"},
#endif
    };
    return {entries, entries + std::size(entries)};
}
SDBCommandResult infoCommand::execute(SDBCommandContext &context, std::string_view args)
{
    if (args == "r")
    {
        PrintRegisters(context.GetCPU());
        return SDBCommandResult::Continue;
    }
#ifdef CONFIG_WATCHPOINT
    if (args == "w")
    {
        CPU6502EvaluationContext EvalContext{context.GetCPU(), context.GetMemory()};
        GetGlobalWatchpointPool().PrintAllWatchpoints(EvalContext);
        return SDBCommandResult::Continue;
    }
#endif
    std::println("用法：info r 或 info w");
    return SDBCommandResult::Continue;
}
