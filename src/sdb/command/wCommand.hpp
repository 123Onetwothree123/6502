#ifndef W_COMMAND_HPP
#define W_COMMAND_HPP
#include "../sdb_command.hpp"

class wCommand final : public SDBCommand
{
public:
    ~wCommand() override = default;
    [[nodiscard]] std::string_view name() const noexcept override;
    [[nodiscard]] SDBCommandUsageList usage() const noexcept override;
    SDBCommandResult execute(SDBCommandContext &context, std::string_view args) override;
};
#endif
