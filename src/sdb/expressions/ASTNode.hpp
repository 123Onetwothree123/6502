#ifndef AST_NODE_HPP
#define AST_NODE_HPP
#include <cstdint>
#include <string>
#include "../evaluation_context.hpp"

class ASTNode
{
public:
    virtual ~ASTNode() = default;
    [[nodiscard]] virtual std::uint32_t Evaluate(const EvaluationContext &context) const = 0;
    [[nodiscard]] virtual std::string ToString() const = 0;
};
#endif
