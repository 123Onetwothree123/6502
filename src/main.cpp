#include <print>
#include "memory.hpp"
#include "ProgramLoader.hpp"
#include "CentralProcessingUnit.hpp"
int main(int argc, char const *argv[])
{
    if (argc < 2)
    {
        std::println("检测到无参数模式运行，进入SDB模式");
        std::println("目前简易的基础设施还没设计出来，所以SDB还用不了");
        std::println("用法: ./6502 <镜像文件.bin/.hex>");
        return 1;
    }
    memory MemoryObject;
    ProgramLoader ProgramLoaderObject;
    if (auto result = ProgramLoaderObject.load(argv[1], MemoryObject))
    {
        std::println("镜像加载成功: {}", argv[1]);
    }
    else
    {
        std::println("加载失败: {}", result.error());
        return 1;
    }
    CentralProcessingUnit CPU(MemoryObject);
    CPU.reset();
    std::size_t steps{0};
    while (!CPU.IsHalted())
    {
        CPU.step();
        ++steps;
    }
    std::println("模拟结束，共执行{}条指令", steps);
    // 特意手动对齐的
    std::println("PC = 0x{:04x}", CPU.GetRegisterPC());
    std::println("A  = 0x{:02x}", CPU.GetRegisterA());
    std::println("X  = 0x{:02x}", CPU.GetRegisterX());
    std::println("Y  = 0x{:02x}", CPU.GetRegisterY());
    std::println("S  = 0x{:02x}", CPU.GetRegisterS());
    std::println("P  = 0x{:02x}", CPU.GetRegisterP());
    return 0;
}
