#ifndef CENTRALPROCESSINGUNIT_HPP
#define CENTRALPROCESSINGUNIT_HPP
#include <cstdint>
#include "memory.hpp"
#include "decoder.hpp"
#include "instruction.hpp"
#include "operand.hpp"
class CentralProcessingUnit
{
private:
    std::uint8_t RegisterA;
    std::uint8_t RegisterX;
    std::uint8_t RegisterY;
    std::uint8_t RegisterS;
    std::uint16_t RegisterPC;
    std::uint8_t RegisterP; // 这是状态寄存器
    bool halted;
    memory &Memory;
    decoder Decoder;
    std::uint16_t ResolveAddress(mode Mode, const operand &Operand);
    operand FetchOperand(const instruction &Instruction);
    void push(std::uint8_t value);
    std::uint8_t pop();
    void SetFlagsN(bool set);
    void SetFlagsZ(bool set);
    void SetFlagsC(bool set);
    void SetFlagsV(bool set);

public:
    ~CentralProcessingUnit() = default;
    CentralProcessingUnit(memory &Memory);
    std::uint8_t GetRegisterA() const;
    std::uint8_t GetRegisterX() const;
    std::uint8_t GetRegisterY() const;
    std::uint8_t GetRegisterS() const;
    std::uint16_t GetRegisterPC() const;
    std::uint8_t GetRegisterP() const;
    bool IsHalted() const;
    void reset();
    void step();
};
#endif