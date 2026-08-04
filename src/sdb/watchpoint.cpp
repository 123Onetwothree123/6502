#include "watchpoint.hpp"

std::size_t Watchpoint::GetNO() const noexcept { return NO; }
bool Watchpoint::IsEnabled() const noexcept { return enabled; }
std::size_t Watchpoint::GetPC() const noexcept { return PC; }
bool Watchpoint::HasValidPC() const noexcept { return HasPC; }
void Watchpoint::SetNO(std::size_t InputNO) noexcept { NO = InputNO; }
void Watchpoint::SetEnabled(bool InputEnabled) noexcept { enabled = InputEnabled; }
void Watchpoint::SetPC(std::size_t InputPC) noexcept { PC = InputPC; }
void Watchpoint::SetHasPC(bool InputHasPC) noexcept { HasPC = InputHasPC; }
const std::string &Watchpoint::GetExpression() const noexcept { return expression; }
void Watchpoint::SetExpression(const std::string &InputExpression) noexcept { expression = InputExpression; }
std::size_t Watchpoint::GetOldValue() const noexcept { return OldValue; }
void Watchpoint::SetOldValue(std::size_t InputOldValue) noexcept { OldValue = InputOldValue; }
