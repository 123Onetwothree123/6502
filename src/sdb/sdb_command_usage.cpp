#include "sdb_command_usage.hpp"

SDBCommandUsage::SDBCommandUsage(std::string_view arguments, std::string_view description)
{
    this->arguments = arguments;
    this->description = description;
}
std::string_view SDBCommandUsage::GetArguments() const noexcept
{
    return arguments;
}
std::string_view SDBCommandUsage::GetDescription() const noexcept
{
    return description;
}
