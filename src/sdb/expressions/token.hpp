#ifndef TOKEN_HPP
#define TOKEN_HPP
#include <cstdint>
#include <string_view>

class token
{
private:
    enum class Kind
    {
        EndOfInput,
        Number,
        Register,
        Plus,
        Minus,
        Star,
        Slash,
        Equal,
        NotEqual,
        LessEqual,
        LogicalAnd,
        LeftParen,
        RightParen,
        ReadMemory8,
    };
    token(Kind kind, std::string_view text, std::uint32_t value, std::size_t position);
    Kind kind{Kind::EndOfInput};
    std::string_view text;
    std::uint32_t value{0};
    std::size_t position{0};

public:
    token() = default;
    ~token() = default;
    static token MakeNumber(std::string_view text, std::uint32_t value, std::size_t position);
    static token MakeRegister(std::string_view text, std::uint32_t RegisterIndex, std::size_t position);
    static token MakePlus(std::string_view text, std::size_t position);
    static token MakeMinus(std::string_view text, std::size_t position);
    static token MakeStar(std::size_t position);
    static token MakeSlash(std::size_t position);
    static token MakeEqual(std::size_t position);
    static token MakeNotEqual(std::size_t position);
    static token MakeLessEqual(std::size_t position);
    static token MakeLogicalAnd(std::size_t position);
    static token MakeLeftParen(std::size_t position);
    static token MakeRightParen(std::size_t position);
    static token MakeEnd(std::size_t position);
    static token MakeReadMemory8(std::size_t position);
    [[nodiscard]] bool IsEndOfInput() const noexcept;
    [[nodiscard]] bool IsNumber() const noexcept;
    [[nodiscard]] bool IsRegister() const noexcept;
    [[nodiscard]] bool IsPlus() const noexcept;
    [[nodiscard]] bool IsMinus() const noexcept;
    [[nodiscard]] bool IsStar() const noexcept;
    [[nodiscard]] bool IsSlash() const noexcept;
    [[nodiscard]] bool IsEqual() const noexcept;
    [[nodiscard]] bool IsNotEqual() const noexcept;
    [[nodiscard]] bool IsLessEqual() const noexcept;
    [[nodiscard]] bool IsLogicalAnd() const noexcept;
    [[nodiscard]] bool IsLeftParen() const noexcept;
    [[nodiscard]] bool IsRightParen() const noexcept;
    [[nodiscard]] bool IsReadMemory8() const noexcept;
    [[nodiscard]] bool IsBinaryOperator() const noexcept;
    [[nodiscard]] bool IsUnaryOperator() const noexcept;
    [[nodiscard]] bool IsOperator() const noexcept;
    [[nodiscard]] bool IsParenthesis() const noexcept;
    [[nodiscard]] int GetPrecedence() const noexcept;
    [[nodiscard]] bool IsRightAssociative() const noexcept;
    [[nodiscard]] std::string_view GetText() const noexcept;
    [[nodiscard]] std::uint32_t GetValue() const noexcept;
    [[nodiscard]] std::size_t GetPosition() const noexcept;
};
#endif
