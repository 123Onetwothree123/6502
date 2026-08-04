#ifndef SDB_COMMAND_USAGE_HPP
#define SDB_COMMAND_USAGE_HPP
#include <string_view>
#include <vector>

class SDBCommandUsage
{
private:
    std::string_view arguments;
    std::string_view description;

public:
    SDBCommandUsage() = default;
    ~SDBCommandUsage() = default;
    SDBCommandUsage(std::string_view arguments, std::string_view description);
    [[nodiscard]] std::string_view GetArguments() const noexcept;
    [[nodiscard]] std::string_view GetDescription() const noexcept;
};

using SDBCommandUsageList = std::vector<SDBCommandUsage>;
#endif
