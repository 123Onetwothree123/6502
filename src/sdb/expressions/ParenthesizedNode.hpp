#ifndef PARENTHESIZED_NODE_HPP
#define PARENTHESIZED_NODE_HPP
#include <memory>
#include "ASTNode.hpp"

class ParenthesizedNode final : public ASTNode
{
private:
    std::unique_ptr<ASTNode> inner;

public:
    ParenthesizedNode() = default;
    ~ParenthesizedNode() override = default;
    explicit ParenthesizedNode(std::unique_ptr<ASTNode> inner);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
