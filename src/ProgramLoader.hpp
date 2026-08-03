#ifndef PROGRAM_LOADER_HPP
#define PROGRAM_LOADER_HPP
#include <cstdint>
#include <filesystem>
#include <expected>
#include <string>
#include "memory.hpp"
class ProgramLoader
{
private:
    std::expected<void, std::string> load_bin(const std::filesystem::path &path, memory &Memory, std::uint16_t base);
    std::expected<void, std::string> load_hex(const std::filesystem::path &path, memory &Memory, std::uint16_t base);

public:
    ProgramLoader() = default;
    ~ProgramLoader() = default;
    std::expected<void, std::string> load(const std::filesystem::path &path, memory &Memory, std::uint16_t base = 0);
};
#endif