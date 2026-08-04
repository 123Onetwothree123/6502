#ifndef SDB_COMMAND_UTILS_HPP
#define SDB_COMMAND_UTILS_HPP
#include <string_view>
#include <utility>

[[nodiscard]] std::string_view SDBTrimLeft(std::string_view text);
[[nodiscard]] std::string_view SDBTrimRight(std::string_view text);
[[nodiscard]] std::pair<std::string_view, std::string_view> SDBSplitCommandLine(std::string_view line);
[[nodiscard]] bool SDBValidateExpressionSyntax(std::string_view expression);
#endif
