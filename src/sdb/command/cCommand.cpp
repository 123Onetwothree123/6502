#include <format>
#include <print>
#include "cCommand.hpp"
#ifdef CONFIG_WATCHPOINT
#include "../cpu6502_evaluation_context.hpp"
#include "../watchpoint_pool.hpp"
#endif

std::string_view cCommand::name() const noexcept
{
    return "c";
}
SDBCommandUsageList cCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"", "继续运行直到结束"},
    };
    return {entries, entries + 1};
}
SDBCommandResult cCommand::execute(SDBCommandContext &context, std::string_view args)
{
    static_cast<void>(args);
    auto &CPU{context.GetCPU()};
#ifdef CONFIG_WATCHPOINT
    CPU6502EvaluationContext EvalContext{CPU, context.GetMemory()};
#endif
    while (!CPU.IsHalted())
    {
        CPU.step();
#ifdef CONFIG_WATCHPOINT
        if (GetGlobalWatchpointPool().CheckAll(EvalContext))
        {
            std::println("因为监视点变化，程序停止");
            break;
        }
#endif
    }
    return SDBCommandResult::Continue;
}
