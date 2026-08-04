#include <format>
#include <print>
#include "qCommand.hpp"

std::string_view qCommand::name() const noexcept
{
    return "q";
}
SDBCommandUsageList qCommand::usage() const noexcept
{
    static const SDBCommandUsage entries[]{
        {"", "退出调试器"},
    };
    return {entries, entries + 1};
}
SDBCommandResult qCommand::execute(SDBCommandContext &context, std::string_view args)
{
    static_cast<void>(context);
    static_cast<void>(args);
    return SDBCommandResult::Quit;
}
