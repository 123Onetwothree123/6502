#ifndef INFO_COMMAND_HPP
#define INFO_COMMAND_HPP
#include "../sdb_command.hpp"

class infoCommand final : public SDBCommand
{
public:
    ~infoCommand() override = default;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
