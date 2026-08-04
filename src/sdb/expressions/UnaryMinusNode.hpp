#ifndef UNARY_MINUS_NODE_HPP
#define UNARY_MINUS_NODE_HPP
#include <memory>
#include "ASTNode.hpp"

class UnaryMinusNode final : public ASTNode
{
private:
    std::unique_ptr<ASTNode> child;

public:
    UnaryMinusNode() = default;
    ~UnaryMinusNode() override = default;
    explicit UnaryMinusNode(std::unique_ptr<ASTNode> child);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
