#ifndef SDB_COMMAND_REGISTRY_HPP
#define SDB_COMMAND_REGISTRY_HPP
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include "sdb_command.hpp"
#include "sdb_command_context.hpp"
#include "sdb_command_result.hpp"

class SDBCommandRegistry
{
private:
    SDBCommandContext Context;
    std::vector<std::unique_ptr<SDBCommand>> Commands{};
    void RegisterBuiltins();

public:
    SDBCommandRegistry() = delete;
    ~SDBCommandRegistry() = default;
    explicit SDBCommandRegistry(CentralProcessingUnit &CPU, memory &Memory);
    SDBCommandResult Execute(std::string_view line);
    void RegisterCommand(std::unique_ptr<SDBCommand> command);
    [[nodiscard]] const SDBCommand *FindCommand(std::string_view name) const;
    void PrintHelp() const;
    void PrintHelp(const SDBCommand &command) const;
};
#endif
