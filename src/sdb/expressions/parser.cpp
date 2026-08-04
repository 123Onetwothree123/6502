#include <format>
#include "parser.hpp"
#include "BinaryOpNode.hpp"
#include "DereferenceNode.hpp"
#include "NumberNode.hpp"
#include "ParenthesizedNode.hpp"
#include "RegisterNode.hpp"
#include "UnaryMinusNode.hpp"

parser::parser(std::vector<token> InputTokens)
{
    tokens = std::move(InputTokens);
}
bool parser::IsAtEnd() const noexcept
{
    return Current().IsEndOfInput();
}
const token &parser::Current() const
{
    if (position < tokens.size())
    {
        return tokens[position];
    }
    return tokens.back();
}
const token &parser::Peek(std::size_t offset) const
{
    if (position + offset < tokens.size())
    {
        return tokens[position + offset];
    }
    return tokens.back();
}
const token &parser::Advance() noexcept
{
    auto &Token{Current()};
    if (!Token.IsEndOfInput())
    {
        ++position;
    }
    return Token;
}
int parser::GetCurrentPrecedence() const noexcept
{
    return Current().GetPrecedence();
}
bool parser::IsCurrentRightAssociative() const noexcept
{
    return Current().IsRightAssociative();
}
std::expected<std::unique_ptr<ASTNode>, std::string> parser::parse()
{
    auto expression{ParseExpression(0)};
    if (!expression)
    {
        return expression;
    }
    if (!Current().IsEndOfInput())
    {
        return std::unexpected(std::format("位置{0}处意外的'{1}'", Current().GetPosition(), Current().GetText()));
    }
    return expression;
}
std::expected<std::unique_ptr<ASTNode>, std::string> parser::ParseExpression(int MinPrecedence)
{
    auto LeftResult{ParseUnary()};
    if (!LeftResult)
    {
        return LeftResult;
    }
    auto left{std::move(*LeftResult)};
    while (true)
    {
        auto precedence{GetCurrentPrecedence()};
        if (precedence == 0 || precedence < MinPrecedence)
        {
            break;
        }
        token OperatorToken{Current()};
        Advance();
        auto NextMinimum{precedence + 1};
        auto RightResult{ParseExpression(NextMinimum)};
        if (!RightResult)
        {
            return RightResult;
        }
        left = std::make_unique<BinaryOpNode>(OperatorToken, std::move(left), std::move(*RightResult));
    }
    return left;
}
std::expected<std::unique_ptr<ASTNode>, std::string> parser::ParseUnary()
{
    auto &Token{Current()};
    if (Token.IsMinus())
    {
        Advance();
        auto operand{ParseUnary()};
        if (!operand)
        {
            return operand;
        }
        return std::make_unique<UnaryMinusNode>(std::move(*operand));
    }
    if (Token.IsStar())
    {
        Advance();
        auto address{ParseUnary()};
        if (!address)
        {
            return address;
        }
        return std::make_unique<DereferenceNode>(std::move(*address));
    }
    if (Token.IsReadMemory8())
    {
        Advance();
        if (!Current().IsLeftParen())
        {
            return std::unexpected(std::format("位置{0}处read8后缺少左括号", Current().GetPosition()));
        }
        Advance();
        auto address{ParseExpression(0)};
        if (!address)
        {
            return address;
        }
        if (!Current().IsRightParen())
        {
            return std::unexpected(std::format("位置{0}处read8缺少右括号", Current().GetPosition()));
        }
        Advance();
        return std::make_unique<DereferenceNode>(std::move(*address));
    }
    return ParsePrimary();
}
std::expected<std::unique_ptr<ASTNode>, std::string> parser::ParsePrimary()
{
    auto &Token{Current()};
    if (Token.IsNumber())
    {
        Advance();
        return std::make_unique<NumberNode>(Token.GetValue());
    }
    if (Token.IsRegister())
    {
        Advance();
        return std::make_unique<RegisterNode>(std::string(Token.GetText()));
    }
    if (Token.IsLeftParen())
    {
        Advance();
        auto inner{ParseExpression(0)};
        if (!inner)
        {
            return inner;
        }
        if (!Current().IsRightParen())
        {
            return std::unexpected(std::format("位置{0}处缺少右括号", Current().GetPosition()));
        }
        Advance();
        return std::make_unique<ParenthesizedNode>(std::move(*inner));
    }
    return std::unexpected(std::format("位置{0}处意外的'{1}'", Token.GetPosition(), Token.GetText()));
}
