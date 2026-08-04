#ifndef EXPRESSION_ERROR_HPP
#define EXPRESSION_ERROR_HPP
#include <exception>
#include <string>

class ExpressionError final : public std::exception
{
private:
    std::string message;

public:
    ExpressionError() = default;
    ~ExpressionError() override = default;
    explicit ExpressionError(std::string InputMessage);
    [[nodiscard]] const char *what() const noexcept override;
};
#endif
