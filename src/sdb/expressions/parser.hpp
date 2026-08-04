#ifndef PARSER_HPP
#define PARSER_HPP
#include <expected>
#include <memory>
#include <string>
#include <vector>
#include "token.hpp"
#include "ASTNode.hpp"

class parser
{
private:
    std::vector<token> tokens;
    std::size_t position{0};
    [[nodiscard]] bool IsAtEnd() const noexcept;
    [[nodiscard]] const token &Current() const;
    [[nodiscard]] const token &Peek(std::size_t offset) const;
    const token &Advance() noexcept;
    [[nodiscard]] int GetCurrentPrecedence() const noexcept;
    [[nodiscard]] bool IsCurrentRightAssociative() const noexcept;
    std::expected<std::unique_ptr<ASTNode>, std::string> ParseExpression(int MinPrecedence);
    std::expected<std::unique_ptr<ASTNode>, std::string> ParseUnary();
    std::expected<std::unique_ptr<ASTNode>, std::string> ParsePrimary();

public:
    parser() = default;
    ~parser() = default;
    explicit parser(std::vector<token> tokens);
    [[nodiscard]] std::expected<std::unique_ptr<ASTNode>, std::string> parse();
};
#endif
