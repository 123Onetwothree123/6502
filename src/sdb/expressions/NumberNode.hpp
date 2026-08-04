#ifndef NUMBER_NODE_HPP
#define NUMBER_NODE_HPP
#include <cstdint>
#include "ASTNode.hpp"

class NumberNode final : public ASTNode
{
private:
    std::uint32_t value;

public:
    NumberNode() = default;
    ~NumberNode() = default;
    explicit NumberNode(std::uint32_t value);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
