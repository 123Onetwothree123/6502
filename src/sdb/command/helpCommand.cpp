#include <format>
#include <print>
#include "helpCommand.hpp"
#include "../sdb_command_utils.hpp"

helpCommand::helpCommand(const SDBCommandRegistry &Registry)
    : Registry{Registry}
{
}
std::string_view helpCommand::name() const noexcept
{
    return "help";
}
SDBCommandUsageList helpCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"[命令名]", "打印所有命令的帮助，或指定命令的帮助"},
    };
    return {entries, entries + 1};
}
SDBCommandResult helpCommand::execute(SDBCommandContext &context, std::string_view args)
{
    static_cast<void>(context);
    args = SDBTrimLeft(args);
    if (args.empty())
    {
        Registry.PrintHelp();
        return SDBCommandResult::Continue;
    }
    const auto *Command{Registry.FindCommand(args)};
    if (Command == nullptr)
    {
        std::println("未知命令：{}", args);
        return SDBCommandResult::Continue;
    }
    Registry.PrintHelp(*Command);
    return SDBCommandResult::Continue;
}
