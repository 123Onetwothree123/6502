#include <format>
#include <print>
#include "wCommand.hpp"
#include "../sdb_command_utils.hpp"
#include "../cpu6502_evaluation_context.hpp"
#include "../watchpoint_pool.hpp"
#include "../expressions/expressions.hpp"

std::string_view wCommand::name() const noexcept
{
    return "w";
}
SDBCommandUsageList wCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"EXPR", "设置表达式监视点，当表达式的值变化时暂停执行"},
    };
    return {entries, entries + 1};
}
SDBCommandResult wCommand::execute(SDBCommandContext &context, std::string_view args)
{
    args = SDBTrimLeft(args);
    if (args.empty())
    {
        std::println("没写参数");
        return SDBCommandResult::Continue;
    }
    if (!SDBValidateExpressionSyntax(args))
    {
        std::println("括号不匹配");
        return SDBCommandResult::Continue;
    }
    expressions expression;
    CPU6502EvaluationContext EvalContext{context.GetCPU(), context.GetMemory()};
    auto result{expression.evaluate(args, EvalContext)};
    if (result)
    {
        auto *wp{GetGlobalWatchpointPool().CreateWatchpoint(std::string(args), *result)};
        if (wp)
        {
            std::println("监视点 {}: {}", wp->GetNO(), args);
        }
        else
        {
            std::println("监视点数量满了");
        }
    }
    else
    {
        std::println("表达式错误：{}", result.error());
    }
    return SDBCommandResult::Continue;
}
