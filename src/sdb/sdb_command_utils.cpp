#include "sdb_command_utils.hpp"

std::string_view SDBTrimLeft(std::string_view text)
{
    auto first{text.find_first_not_of(" \t")};
    if (first == std::string_view::npos)
    {
        return {};
    }
    text.remove_prefix(first);
    return text;
}
std::string_view SDBTrimRight(std::string_view text)
{
    auto last{text.find_last_not_of(" \t")};
    if (last == std::string_view::npos)
    {
        return {};
    }
    text.remove_suffix(text.size() - last - 1);
    return text;
}
std::pair<std::string_view, std::string_view> SDBSplitCommandLine(std::string_view line)
{
    line = SDBTrimLeft(line);
    auto CommandEnd{line.find_first_of(" \t")};
    if (CommandEnd == std::string_view::npos)
    {
        return {line, {}};
    }
    const auto name{line.substr(0, CommandEnd)};
    line.remove_prefix(CommandEnd);
    return {name, SDBTrimRight(SDBTrimLeft(line))};
}
bool SDBValidateExpressionSyntax(std::string_view expression)
{
    if (expression.empty())
    {
        return false;
    }
    auto ParenCount{0};
    for (const char character : expression)
    {
        if (character == '(')
        {
            ++ParenCount;
        }
        else if (character == ')')
        {
            --ParenCount;
        }
        if (ParenCount < 0)
        {
            return false;
        }
    }
    return ParenCount == 0;
}
