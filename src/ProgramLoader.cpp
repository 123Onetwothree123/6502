#include "ProgramLoader.hpp"
#include <expected>
#include <format>
#include <fstream>
#include <vector>
// 把两个十六进制字符变成字节
static std::uint8_t hex_to_byte(char high, char low)
{
    auto value{[](char c) -> int
               {
                   if (c >= '0' && c <= '9')
                   {
                       return c - '0'; // 0到9
                   }
                   if (c >= 'a' && c <= 'f')
                   {
                       return c - 'a' + 10; // a到f
                   }
                   if (c >= 'A' && c <= 'F')
                   {
                       return c - 'A' + 10; // A到F
                   }
                   return 0;
               }};
    return static_cast<std::uint8_t>((value(high) << 4) | value(low)); // 高4位 | 低4位
}
std::expected<void, std::string>
ProgramLoader::load(const std::filesystem::path &path, memory &Memory, std::uint16_t base)
{
    std::string extension{path.extension().string()};
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char c)
                   { return std::tolower(c); });
    if (extension == ".bin")
    {
        return load_bin(path, Memory, base);
    }
    if (extension == ".hex")
    {
        return load_hex(path, Memory, base);
    }
    return std::unexpected(std::format("ProgramLoader不支持这个文件格式：{}", extension));
}
std::expected<void, std::string> ProgramLoader::load_bin(const std::filesystem::path &path, memory &Memory, std::uint16_t base)
{
    std::ifstream file(path, std::ios::binary);
    if (!file)
    {
        return std::unexpected(std::format("ProgramLoader直接无法打开{}文件了", path.string()));
    }
    std::vector<std::uint8_t> buffer(std::istreambuf_iterator<char>(file), {});
    if (buffer.size() > static_cast<std::size_t>(0x10000) - base)
    {
        return std::unexpected("超出64KB地址空间了，爆内存了");
    }
    Memory.write(buffer, base);
    return {};
}
std::expected<void, std::string> ProgramLoader::load_hex(const std::filesystem::path &path, memory &Memory, std::uint16_t base)
{
    std::ifstream file(path);
    if (!file)
    {
        return std::unexpected(std::format("ProgramLoader直接无法打开{}文件了", path.string()));
    }
    std::string line;
    std::size_t line_no{0};
    while (std::getline(file, line))
    {
        ++line_no;
        if (line.empty())
        {
            continue; // 空行直接跳
        }
        if (line[0] != ':')
        {
            return std::unexpected(std::format("这个文件解析不了，第{}行不是HEX记录", line_no));
        }
        auto count{hex_to_byte(line[1], line[2])}; // 本行数据字节数
        // 逆天6502居然是大端序
        auto address{static_cast<std::uint16_t>((hex_to_byte(line[3], line[4]) << 8) | hex_to_byte(line[5], line[6]))};
        auto type{hex_to_byte(line[7], line[8])};
        std::vector<std::uint8_t> data(count);
        for (std::size_t i{0}; i < count; ++i)
        {
            data[i] = hex_to_byte(line[9 + i * 2], line[9 + i * 2 + 1]);
        }
        // 校验和，低8bit为0
        auto sum{count};
        sum += static_cast<std::uint8_t>(address >> 8);   // 地址高字节
        sum += static_cast<std::uint8_t>(address & 0xFF); // 地址低字节
        sum += type;
        for (auto b : data)
        {
            sum += b;
        }
        sum += hex_to_byte(line[9 + count * 2], line[9 + count * 2 + 1]); // 最后的checksum
        if (sum != 0)
        {
            return std::unexpected(std::format("文件的第{}行校验和错误", line_no));
        }
        if (type == 0)
        {
            const auto StartAddress{static_cast<std::uint16_t>(base + address)};
            Memory.write(data, StartAddress);
        }
        else if (type == 1) // 文件结束记录
        {
            return {};
        }
    }
    return {};
}