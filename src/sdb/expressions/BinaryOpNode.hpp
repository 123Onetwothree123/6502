#ifndef BINARY_OP_NODE_HPP
#define BINARY_OP_NODE_HPP
#include <memory>
#include "ASTNode.hpp"
#include "token.hpp"

class BinaryOpNode final : public ASTNode
{
private:
    token Token;
    std::unique_ptr<ASTNode> Left;
    std::unique_ptr<ASTNode> Right;

public:
    BinaryOpNode() = default;
    ~BinaryOpNode() override = default;
    BinaryOpNode(token Token, std::unique_ptr<ASTNode> Left, std::unique_ptr<ASTNode> Right);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
