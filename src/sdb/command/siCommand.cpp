#include <format>
#include <print>
#include "siCommand.hpp"
#include <charconv>
#include "../sdb_command_utils.hpp"
#ifdef CONFIG_WATCHPOINT
#include "../cpu6502_evaluation_context.hpp"
#include "../watchpoint_pool.hpp"
#endif

std::string_view siCommand::name() const noexcept
{
    return "si";
}
SDBCommandUsageList siCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"[N]", "单步执行 N 条指令，默认 1 条"},
    };
    return {entries, entries + 1};
}
SDBCommandResult siCommand::execute(SDBCommandContext &context, std::string_view args)
{
    auto count{std::size_t{1}};
    args = SDBTrimLeft(args);
    if (!args.empty())
    {
        auto parsed{static_cast<std::ptrdiff_t>(0)};
        const auto result{std::from_chars(args.data(), args.data() + args.size(), parsed, 10)};
        if (result.ec != std::errc())
        {
            std::println("参数{}用from_chars解析失败了", args);
            return SDBCommandResult::Continue;
        }
        if (parsed <= 0)
        {
            std::println("步数必须得是正整数，结果现在得到的是 {}", parsed);
            return SDBCommandResult::Continue;
        }
        auto remainder{std::string_view{result.ptr, static_cast<std::size_t>(args.data() + args.size() - result.ptr)}};
        remainder = SDBTrimLeft(remainder);
        if (!remainder.empty())
        {
            std::println("参数尾部有多余的内容'{}'", remainder);
            return SDBCommandResult::Continue;
        }
        count = static_cast<std::size_t>(parsed);
    }
    auto &CPU{context.GetCPU()};
    if (CPU.IsHalted())
    {
        std::println("CPU已经停止运行了");
        return SDBCommandResult::Continue;
    }
#ifdef CONFIG_WATCHPOINT
    CPU6502EvaluationContext EvalContext{CPU, context.GetMemory()};
#endif
    for (std::size_t index{0}; index < count && !CPU.IsHalted(); ++index)
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
