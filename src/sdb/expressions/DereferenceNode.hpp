#ifndef DEREFERENCE_NODE_HPP
#define DEREFERENCE_NODE_HPP
#include <memory>
#include "ASTNode.hpp"

class DereferenceNode final : public ASTNode
{
private:
    std::unique_ptr<ASTNode> address;

public:
    DereferenceNode() = default;
    ~DereferenceNode() override = default;
    explicit DereferenceNode(std::unique_ptr<ASTNode> address);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
