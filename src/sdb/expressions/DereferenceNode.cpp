#include <format>
#include "DereferenceNode.hpp"

DereferenceNode::DereferenceNode(std::unique_ptr<ASTNode> address)
{
    this->address = std::move(address);
}
std::uint32_t DereferenceNode::Evaluate(const EvaluationContext &context) const
{
    auto Address{address->Evaluate(context)};
    return context.ReadMemory(Address);
}
std::string DereferenceNode::ToString() const
{
    return std::format("read8({0})", address->ToString());
}
