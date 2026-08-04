#include <format>
#include <print>
#include "watchpoint_pool.hpp"
#include "expressions/expressions.hpp"

WatchpointPool &GetGlobalWatchpointPool()
{
    static WatchpointPool GlobalWatchpointPool{32};
    return GlobalWatchpointPool;
}

WatchpointPool::WatchpointPool(std::size_t InputMaxWatchpoints)
    : watchpoints(InputMaxWatchpoints)
{
    for (std::size_t i{InputMaxWatchpoints}; i > 0; --i)
    {
        const auto NO{i - 1};
        watchpoints[NO].SetNO(NO);
        FreeWatchpointIndices.push_back(NO);
    }
}
Watchpoint *WatchpointPool::GetWatchpoint(std::size_t NO)
{
    if (NO >= watchpoints.size())
    {
        return nullptr;
    }
    return &watchpoints[NO];
}
const std::vector<Watchpoint> &WatchpointPool::GetAllWatchpoints() const noexcept
{
    return watchpoints;
}
std::size_t WatchpointPool::GetMaxWatchpoints() const noexcept
{
    return watchpoints.size();
}
Watchpoint *WatchpointPool::CreateWatchpoint(const std::string &expression, std::size_t InitialValue)
{
    if (FreeWatchpointIndices.empty())
    {
        return nullptr;
    }
    auto NO{FreeWatchpointIndices.back()};
    Watchpoint &wp{watchpoints[NO]};
    wp.SetNO(NO);
    wp.SetExpression(expression);
    wp.SetOldValue(InitialValue);
    wp.SetPC(0);
    wp.SetHasPC(false);
    wp.SetEnabled(true);
    FreeWatchpointIndices.pop_back();
    UsedWatchpointIndices.push_back(NO);
    return &wp;
}
bool WatchpointPool::DeleteWatchpoint(std::size_t NO)
{
    if (NO >= watchpoints.size())
    {
        return false;
    }
    if (!watchpoints[NO].IsEnabled())
    {
        return false;
    }
    watchpoints[NO].SetEnabled(false);
    watchpoints[NO].SetExpression("");
    watchpoints[NO].SetOldValue(0);
    watchpoints[NO].SetPC(0);
    watchpoints[NO].SetHasPC(false);
    auto it{std::ranges::find(UsedWatchpointIndices, NO)};
    if (it != UsedWatchpointIndices.end())
    {
        UsedWatchpointIndices.erase(it);
    }
    FreeWatchpointIndices.push_back(NO);
    return true;
}
bool WatchpointPool::CheckAll(const EvaluationContext &context)
{
    expressions expression;
    auto CurrentPC{context.GetPC()};
    bool triggered{false};
    for (std::size_t NO : UsedWatchpointIndices)
    {
        auto &wp{watchpoints[NO]};
        if (!wp.IsEnabled())
        {
            continue;
        }
        auto result{expression.evaluate(wp.GetExpression(), context)};
        if (!result)
        {
            std::println("监视点{}表达式求值失败：{}", NO, result.error());
            continue;
        }
        auto newValue{*result};
        if (newValue != static_cast<std::uint32_t>(wp.GetOldValue()))
        {
            std::println("监视点{}触发：{} = 0x{:04x}（旧值 0x{:04x}）", NO, wp.GetExpression(), newValue, static_cast<std::uint32_t>(wp.GetOldValue()));
            wp.SetOldValue(newValue);
            wp.SetPC(CurrentPC);
            wp.SetHasPC(true);
            triggered = true;
        }
    }
    return triggered;
}
void WatchpointPool::PrintAllWatchpoints(const EvaluationContext &context) const
{
    expressions expression;
    std::println("监视点列表：");
    for (const auto &wp : watchpoints)
    {
        if (wp.IsEnabled())
        {
            auto value{expression.evaluate(wp.GetExpression(), context)};
            std::println("  编号{}: {} （当前值 0x{:04x}）", wp.GetNO(), wp.GetExpression(), value ? *value : 0);
        }
    }
}
