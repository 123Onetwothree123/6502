#ifndef HELP_COMMAND_HPP
#define HELP_COMMAND_HPP
#include "../sdb_command.hpp"
#include "../sdb_command_registry.hpp"

class helpCommand final : public SDBCommand
{
private:
    const SDBCommandRegistry &Registry;

public:
    ~helpCommand() override = default;
    explicit helpCommand(const SDBCommandRegistry &Registry);
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
