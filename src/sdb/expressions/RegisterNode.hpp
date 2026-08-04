#ifndef REGISTER_NODE_HPP
#define REGISTER_NODE_HPP
#include <string>
#include "ASTNode.hpp"

class RegisterNode final : public ASTNode
{
private:
    std::string name;

public:
    RegisterNode() = default;
    ~RegisterNode() = default;
    explicit RegisterNode(std::string name);
    [[nodiscard]] std::uint32_t Evaluate(const EvaluationContext &context) const override;
    [[nodiscard]] std::string ToString() const override;
};
#endif
