#ifndef D_COMMAND_HPP
#define D_COMMAND_HPP
#include "../sdb_command.hpp"

class dCommand final : public SDBCommand
{
public:
    ~dCommand() override = default;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
