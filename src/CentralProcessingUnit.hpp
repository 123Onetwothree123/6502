#ifndef CENTRALPROCESSINGUNIT_HPP
#define CENTRALPROCESSINGUNIT_HPP
#include <array>
#include <cstdint>
#include "memory.hpp"
#include "decoder.hpp"
#include "instruction.hpp"
#include "operand.hpp"
#include "RegisterIndex.hpp"
class CentralProcessingUnit
{
private:
    std::array<std::uint8_t, RegisterCount> Registers{};
    std::uint16_t RegisterPC;
    bool halted;
    bool IrqLine{false};
    std::size_t IrqCounter{0};
    std::size_t IrqInterval{0};
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
    void HandleIrq();

public:
    ~CentralProcessingUnit() = default;
    CentralProcessingUnit(memory &Memory);
    std::uint8_t GetRegister(std::size_t index) const;
    void SetRegister(std::size_t index, std::uint8_t value);
    std::uint16_t GetRegisterPC() const;
    bool IsHalted() const;
    void reset();
    void step();
    void SetIrqLine(bool asserted);
    void SetIrqInterval(std::size_t instructions);
};
#endif
