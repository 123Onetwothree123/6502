#ifndef SDB_COMMAND_HPP
#define SDB_COMMAND_HPP
#include <string_view>
#include "sdb_command_result.hpp"
#include "sdb_command_usage.hpp"
#include "sdb_command_context.hpp"

class SDBCommand
{
public:
    SDBCommand() = default;
    virtual ~SDBCommand() = default;
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
    [[nodiscard]] virtual SDBCommandUsageList usage() const noexcept = 0;
    virtual SDBCommandResult execute(SDBCommandContext &context, std::string_view args) = 0;
};
#endif
