#ifndef WATCHPOINT_POOL_HPP
#define WATCHPOINT_POOL_HPP
#include <cstdint>
#include <string>
#include <vector>
#include "watchpoint.hpp"
#include "evaluation_context.hpp"

class WatchpointPool
{
private:
    std::vector<Watchpoint> watchpoints;
    std::vector<std::size_t> FreeWatchpointIndices;
    std::vector<std::size_t> UsedWatchpointIndices;

public:
    WatchpointPool() = delete;
    ~WatchpointPool() = default;
    explicit WatchpointPool(std::size_t InputMaxWatchpoints);
    bool DeleteWatchpoint(std::size_t NO);
    Watchpoint *CreateWatchpoint(const std::string &expression, std::size_t InitialValue);
    Watchpoint *GetWatchpoint(std::size_t NO);
    [[nodiscard]] const std::vector<Watchpoint> &GetAllWatchpoints() const noexcept;
    [[nodiscard]] std::size_t GetMaxWatchpoints() const noexcept;
    bool CheckAll(const EvaluationContext &context);
    void PrintAllWatchpoints(const EvaluationContext &context) const;
};

WatchpointPool &GetGlobalWatchpointPool();
#endif
