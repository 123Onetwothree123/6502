#include <print>
#include "memory.hpp"
#include "ProgramLoader.hpp"
#include "CentralProcessingUnit.hpp"
#include "BuiltinImage.hpp"
#ifdef CONFIG_SDB
#include "sdb/sdb.hpp"
#endif

int main(int argc, char const *argv[])
{
#ifdef CONFIG_SDB
    if (argc < 2)
    {
        std::println("检测到无参数模式运行，进入SDB模式");
        memory MemoryObject;
        BuiltinImage BuiltinImage;
        BuiltinImage.Load(MemoryObject);
        CentralProcessingUnit CPU(MemoryObject);
        CPU.reset();
        SDB::MainLoop(CPU, MemoryObject);
        return 0;
    }
#endif
    memory MemoryObject;
    if (argc < 2)
    {
        std::println("无参数且SDB已禁用，运行内置镜像");
        BuiltinImage BuiltinImage;
        BuiltinImage.Load(MemoryObject);
    }
    else
    {
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
    BuiltinImage BuiltinImage;
    BuiltinImage.PrintTrapResult(CPU);
    // 特意手动对齐的
    std::println("PC = 0x{:04x}", CPU.GetRegisterPC());
    std::println("A  = 0x{:02x}", CPU.GetRegister(A));
    std::println("X  = 0x{:02x}", CPU.GetRegister(X));
    std::println("Y  = 0x{:02x}", CPU.GetRegister(Y));
    std::println("S  = 0x{:02x}", CPU.GetRegister(S));
    std::println("P  = 0x{:02x}", CPU.GetRegister(P));
    return 0;
}
