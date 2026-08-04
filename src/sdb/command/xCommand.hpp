#ifndef X_COMMAND_HPP
#define X_COMMAND_HPP
#include "../sdb_command.hpp"

class xCommand final : public SDBCommand
{
public:
    ~xCommand() override = default;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
