#include <print>
#include "sdb.hpp"
#include <cstdlib>
#include <string>
#include "sdb_command_registry.hpp"
#include "sdb_command_result.hpp"

extern "C"
{
#include "linenoise.h"
}

void SDB::MainLoop(CentralProcessingUnit &CPU, memory &Memory)
{
    SDBCommandRegistry Commands{CPU, Memory};
    auto line{linenoise("(6502) ")};
    while (line != nullptr)
    {
        if (line[0] != '\0')
        {
            linenoiseHistoryAdd(line);
        }
        auto cmd{std::string{line}};
        free(line);
        if (Commands.Execute(cmd) == SDBCommandResult::Quit)
        {
            std::println("退出");
            break;
        }
        line = linenoise("(6502) ");
    }
}
