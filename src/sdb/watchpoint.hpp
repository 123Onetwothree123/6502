#ifndef WATCHPOINT_HPP
#define WATCHPOINT_HPP
#include <cstdint>
#include <string>

class Watchpoint
{
private:
    std::size_t NO{0};
    bool enabled{false};
    std::size_t PC{0};
    bool HasPC{false};
    std::string expression;
    std::size_t OldValue{0};

public:
    Watchpoint() = default;
    ~Watchpoint() = default;
    [[nodiscard]] std::size_t GetNO() const noexcept;
    [[nodiscard]] bool IsEnabled() const noexcept;
    [[nodiscard]] std::size_t GetPC() const noexcept;
    [[nodiscard]] bool HasValidPC() const noexcept;
    void SetNO(std::size_t InputNO) noexcept;
    void SetEnabled(bool InputEnabled) noexcept;
    void SetPC(std::size_t InputPC) noexcept;
    void SetHasPC(bool InputHasPC) noexcept;
    [[nodiscard]] const std::string &GetExpression() const noexcept;
    void SetExpression(const std::string &InputExpression) noexcept;
    [[nodiscard]] std::size_t GetOldValue() const noexcept;
    void SetOldValue(std::size_t InputOldValue) noexcept;
};
#endif
