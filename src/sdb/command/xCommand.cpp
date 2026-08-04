#include <format>
#include <print>
#include "xCommand.hpp"
#include <charconv>
#include <limits>
#include "../sdb_command_utils.hpp"
#include "../cpu6502_evaluation_context.hpp"
#include "../expressions/expressions.hpp"

std::string_view xCommand::name() const noexcept
{
    return "x";
}
SDBCommandUsageList xCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"N EXPR", "从表达式地址开始看N个字节"},
    };
    return {entries, entries + 1};
}
SDBCommandResult xCommand::execute(SDBCommandContext &context, std::string_view args)
{
    args = SDBTrimLeft(args);
    if (args.empty())
    {
        std::println("用法：x N EXPR");
        return SDBCommandResult::Continue;
    }
    auto Count{std::size_t{0}};
    const auto CountResult{std::from_chars(args.data(), args.data() + args.size(), Count, 10)};
    if (CountResult.ec != std::errc() || Count == 0)
    {
        std::println("错误：缺少有效的扫描数量 N");
        std::println("用法：x N EXPR");
        return SDBCommandResult::Continue;
    }
    args.remove_prefix(static_cast<std::size_t>(CountResult.ptr - args.data()));
    args = SDBTrimLeft(args);
    if (args.empty())
    {
        std::println("错误：缺少地址表达式");
        std::println("用法：x N EXPR");
        return SDBCommandResult::Continue;
    }
    expressions ExpressionsEngine;
    CPU6502EvaluationContext EvalContext{context.GetCPU(), context.GetMemory()};
    const auto AddressResult{ExpressionsEngine.evaluate(args, EvalContext)};
    if (!AddressResult)
    {
        std::println("表达式错误：{}", AddressResult.error());
        return SDBCommandResult::Continue;
    }
    const auto StartAddress{AddressResult.value()};
    std::println("正在扫描 {} 个字节，从 0x{:04x} 开始：", Count, StartAddress & 0xFFFF);
    for (std::size_t Index{0}; Index < Count; ++Index)
    {
        const auto CurrentAddress{StartAddress + static_cast<std::uint32_t>(Index)};
        const auto Value{EvalContext.ReadMemory(CurrentAddress)};
        std::println("  0x{:04x}: 0x{:02x}", CurrentAddress & 0xFFFF, Value);
    }
    return SDBCommandResult::Continue;
}
