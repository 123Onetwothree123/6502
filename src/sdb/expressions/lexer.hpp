#ifndef LEXER_HPP
#define LEXER_HPP
#include <cstdint>
#include <expected>
#include <string>
#include <string_view>
#include <vector>
#include "token.hpp"

class lexer
{
private:
    std::string_view input;
    std::size_t position{0};
    std::string error;
    void SkipWhitespace();
    bool IsAtEnd() const noexcept;
    char Peek() const noexcept;
    char Advance() noexcept;
    bool Match(char expected) noexcept;
    token ScanNumber();
    token ScanHexNumber();
    token ScanRegister();
    token ScanOperator();

public:
    lexer() = default;
    ~lexer() = default;
    [[nodiscard]] bool HasError() const noexcept;
    [[nodiscard]] std::string GetError() const noexcept;
    explicit lexer(std::string_view input);
    [[nodiscard]] std::expected<token, std::string> scan();
    [[nodiscard]] std::expected<std::vector<token>, std::string> ScanAll();
    token next();
};
#endif
