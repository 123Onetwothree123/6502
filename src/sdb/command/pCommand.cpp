#include <format>
#include <print>
#include "pCommand.hpp"
#include "../sdb_command_utils.hpp"
#include "../cpu6502_evaluation_context.hpp"
#include "../expressions/expressions.hpp"

std::string_view pCommand::name() const noexcept
{
    return "p";
}
SDBCommandUsageList pCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"EXPR", "计算表达式（支持$pc/$a/$x/$y/$s/$p、算术运算、read8内存读取）"},
    };
    return {entries, entries + 1};
}
SDBCommandResult pCommand::execute(SDBCommandContext &context, std::string_view args)
{
    args = SDBTrimLeft(args);
    if (args.empty())
    {
        std::println("参数是空的");
        return SDBCommandResult::Continue;
    }
    if (!SDBValidateExpressionSyntax(args))
    {
        std::println("表达式错误：括号不匹配");
        return SDBCommandResult::Continue;
    }
    expressions expression;
    CPU6502EvaluationContext EvalContext{context.GetCPU(), context.GetMemory()};
    auto result{expression.evaluate(args, EvalContext)};
    if (result)
    {
        auto UnsignedValue{*result};
        std::println("无符号（十进制）：{}", UnsignedValue);
        std::println("十六进制：        0x{:04x}", UnsignedValue);
    }
    else
    {
        std::println("表达式错误：{}", result.error());
    }
    return SDBCommandResult::Continue;
}
