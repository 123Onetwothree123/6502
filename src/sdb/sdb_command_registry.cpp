#include <iostream>
#include <print>
#include "sdb_command_registry.hpp"
#include "sdb_command_utils.hpp"
#include "command/siCommand.hpp"
#include "command/cCommand.hpp"
#include "command/infoCommand.hpp"
#include "command/xCommand.hpp"
#include "command/pCommand.hpp"
#include "command/wCommand.hpp"
#include "command/dCommand.hpp"
#include "command/helpCommand.hpp"
#include "command/qCommand.hpp"

SDBCommandRegistry::SDBCommandRegistry(CentralProcessingUnit &CPU, memory &Memory)
    : Context(CPU, Memory)
{
    RegisterBuiltins();
}
SDBCommandResult SDBCommandRegistry::Execute(std::string_view line)
{
    const auto [Name, Args]{SDBSplitCommandLine(line)};
    if (Name.empty())
    {
        return SDBCommandResult::Continue;
    }
    const auto CommandIt{std::ranges::find_if(Commands, [Name](const std::unique_ptr<SDBCommand> &Command)
                                              { return Command->name() == Name; })};
    if (CommandIt == Commands.end())
    {
        std::println(std::cerr, "未知命令: {}", line);
        return SDBCommandResult::Continue;
    }
    return (*CommandIt)->execute(Context, Args);
}
void SDBCommandRegistry::RegisterCommand(std::unique_ptr<SDBCommand> command)
{
    Commands.push_back(std::move(command));
}
const SDBCommand *SDBCommandRegistry::FindCommand(std::string_view name) const
{
    const auto CommandIt{std::ranges::find_if(Commands, [name](const std::unique_ptr<SDBCommand> &Command)
                                              { return Command->name() == name; })};
    if (CommandIt == Commands.end())
    {
        return nullptr;
    }
    return CommandIt->get();
}
void SDBCommandRegistry::PrintHelp() const
{
    std::println("可用命令：");
    for (const auto &Command : Commands)
    {
        for (const auto &Usage : Command->usage())
        {
            std::println("  {} {}  {}", Command->name(), Usage.GetArguments(), Usage.GetDescription());
        }
    }
}
void SDBCommandRegistry::PrintHelp(const SDBCommand &command) const
{
    for (const auto &Usage : command.usage())
    {
        std::println("  {} {}  {}", command.name(), Usage.GetArguments(), Usage.GetDescription());
    }
}
void SDBCommandRegistry::RegisterBuiltins()
{
    RegisterCommand(std::make_unique<siCommand>());
    RegisterCommand(std::make_unique<cCommand>());
    RegisterCommand(std::make_unique<infoCommand>());
    RegisterCommand(std::make_unique<xCommand>());
    RegisterCommand(std::make_unique<pCommand>());
    RegisterCommand(std::make_unique<wCommand>());
    RegisterCommand(std::make_unique<dCommand>());
    RegisterCommand(std::make_unique<helpCommand>(*this));
    RegisterCommand(std::make_unique<qCommand>());
}
