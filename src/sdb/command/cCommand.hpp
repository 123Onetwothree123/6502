#ifndef C_COMMAND_HPP
#define C_COMMAND_HPP
#include "../sdb_command.hpp"

class cCommand final : public SDBCommand
{
public:
    ~cCommand() override = default;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
