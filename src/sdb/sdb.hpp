#ifndef SDB_HPP
#define SDB_HPP
#include "../CentralProcessingUnit.hpp"
#include "../memory.hpp"

class SDB
{
public:
    SDB() = delete;
    ~SDB() = default;
    static void MainLoop(CentralProcessingUnit &CPU, memory &Memory);
};
#endif
