#include "CentralProcessingUnit.hpp"
void CentralProcessingUnit::SetFlagsN(bool set)
{
    if (set)
    {
        RegisterP |= 0x80;
    }
    else
    {
        RegisterP &= ~0x80;
    }
}
void CentralProcessingUnit::SetFlagsZ(bool set)
{
    if (set)
    {
        RegisterP |= 0x02;
    }
    else
    {
        RegisterP &= ~0x02;
    }
}
void CentralProcessingUnit::SetFlagsC(bool set)
{
    if (set)
    {
        RegisterP |= 0x01;
    }
    else
    {
        RegisterP &= ~0x01;
    }
}
void CentralProcessingUnit::SetFlagsV(bool set)
{
    if (set)
    {
        RegisterP |= 0x40;
    }
    else
    {
        RegisterP &= ~0x40;
    }
}
std::uint8_t CentralProcessingUnit::GetRegisterA() const
{
    return RegisterA;
}
std::uint8_t CentralProcessingUnit::GetRegisterX() const
{
    return RegisterX;
}
std::uint8_t CentralProcessingUnit::GetRegisterY() const
{
    return RegisterY;
}
std::uint8_t CentralProcessingUnit::GetRegisterS() const
{
    return RegisterS;
}
std::uint16_t CentralProcessingUnit::GetRegisterPC() const
{
    return RegisterPC;
}
std::uint8_t CentralProcessingUnit::GetRegisterP() const
{
    return RegisterP;
}
bool CentralProcessingUnit::IsHalted() const
{
    return halted;
}
CentralProcessingUnit::CentralProcessingUnit(memory &Memory)
    : Memory{Memory}
{
    RegisterS = 0xFD;
    RegisterP = 0x20;
    halted = false;
    RegisterA = 0;
    RegisterX = 0;
    RegisterY = 0;
    RegisterPC = 0;
}
std::uint16_t CentralProcessingUnit::ResolveAddress(mode Mode, const operand &Operand)
{
    switch (Mode)
    {
    case mode::ZeroPage:
    {
        return Operand.GetValue() & 0xFF;
    }
    case mode::ZeroPageX:
    {
        return (Operand.GetValue() + RegisterX) & 0xFF;
    }
    case mode::ZeroPageY:
    {
        return (Operand.GetValue() + RegisterY) & 0xFF;
    }
    case mode::Absolute:
    {
        return Operand.GetValue();
    }
    case mode::AbsoluteX:
    {
        return Operand.GetValue() + RegisterX;
    }
    case mode::AbsoluteY:
    {
        return Operand.GetValue() + RegisterY;
    }
    case mode::Indirect:
    {
        auto pointer{Operand.GetValue()};
        auto LowByte{Memory.read(pointer)};
        auto HighByte{Memory.read(pointer + 1)};
        return LowByte | (HighByte << 8);
    }
    case mode::IndexedIndirect:
    {
        auto pointer{static_cast<std::uint8_t>((Operand.GetValue() + RegisterX) & 0xFF)};
        auto LowByte{Memory.read(pointer)};
        auto HighByte{Memory.read(static_cast<std::uint8_t>(pointer + 1))};
        return LowByte | (HighByte << 8);
    }
    case mode::IndirectIndexed:
    {
        auto pointer{static_cast<std::uint8_t>(Operand.GetValue() & 0xFF)};
        auto base{Memory.read(pointer) | (Memory.read(static_cast<std::uint8_t>(pointer + 1)) << 8)};
        return base + RegisterY;
    }
    case mode::Relative:
    {
        return Operand.GetValue();
    }
    case mode::Implied:
    case mode::Immediate:
    case mode::Accumulator:
    case mode::UNKNOWN:
    default:
    {
        return 0;
    }
    }
}
operand CentralProcessingUnit::FetchOperand(const instruction &Instruction)
{
    switch (Instruction.GetMode())
    {
    case mode::Immediate:
    {
        auto value{Memory.read(RegisterPC)};
        RegisterPC++;
        return operand{kind::Immediate, value};
    }
    case mode::Implied:
    case mode::Accumulator:
    {
        return operand{kind::None, 0};
    }
    case mode::ZeroPage:
    case mode::ZeroPageX:
    case mode::ZeroPageY:
    case mode::IndexedIndirect:
    case mode::Relative:
    {
        auto address{static_cast<std::uint16_t>(Memory.read(RegisterPC))};
        RegisterPC++;
        operand raw{kind::Address, address};
        return operand{kind::Address, ResolveAddress(Instruction.GetMode(), raw)};
    }
    case mode::Absolute:
    case mode::AbsoluteX:
    case mode::AbsoluteY:
    case mode::Indirect:
    case mode::IndirectIndexed:
    {
        auto address{static_cast<std::uint16_t>(Memory.read(RegisterPC))};
        address |= static_cast<std::uint16_t>(Memory.read(RegisterPC + 1)) << 8;
        RegisterPC += 2;
        operand raw{kind::Address, address};
        return operand{kind::Address, ResolveAddress(Instruction.GetMode(), raw)};
    }
    case mode::UNKNOWN:
    default:
    {
        return operand{kind::UNKNOWN, 0};
    }
    }
}
void CentralProcessingUnit::push(std::uint8_t value)
{
    Memory.write(static_cast<std::uint16_t>(0x0100 + RegisterS), value);
    RegisterS--;
}
std::uint8_t CentralProcessingUnit::pop()
{
    RegisterS++;
    return Memory.read(0x0100 + RegisterS);
}
void CentralProcessingUnit::reset()
{
    RegisterA = 0;
    RegisterX = 0;
    RegisterY = 0;
    RegisterS = 0xFD;
    RegisterP = 0x20;
    halted = false;
    auto LowByte{Memory.read(0xFFFC)};
    auto HighByte{Memory.read(0xFFFD)};
    RegisterPC = static_cast<std::uint16_t>(LowByte | (HighByte << 8)); // 从复位向量装PC
}
void CentralProcessingUnit::step()
{
    if (halted)
    {
        return;
    }
    auto Opcode{Decoder.decode(Memory.read(RegisterPC))};
    RegisterPC++; // 跳过操作码
    auto Operand{FetchOperand(Opcode)};
    auto Address{Operand.GetValue()};
    // 立即数直接用，地址去内存读，累加器模式取A
    auto read_value{[&]() -> std::uint8_t
                    {
                        if (Operand.GetKind() == kind::Immediate)
                        {
                            return static_cast<std::uint8_t>(Operand.GetValue());
                        }
                        if (Operand.GetKind() == kind::Address)
                        {
                            return Memory.read(Operand.GetValue());
                        }
                        return RegisterA;
                    }};
    switch (Opcode.GetOpcode())
    {
    case opcode::LDA:
    {
        RegisterA = read_value();
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::LDX:
    {
        RegisterX = read_value();
        SetFlagsN(RegisterX & 0x80);
        SetFlagsZ(RegisterX == 0);
        break;
    }
    case opcode::LDY:
    {
        RegisterY = read_value();
        SetFlagsN(RegisterY & 0x80);
        SetFlagsZ(RegisterY == 0);
        break;
    }
    case opcode::STA:
    {
        Memory.write(Operand.GetValue(), RegisterA);
        break;
    }
    case opcode::STX:
    {
        Memory.write(Operand.GetValue(), RegisterX);
        break;
    }
    case opcode::STY:
    {
        Memory.write(Operand.GetValue(), RegisterY);
        break;
    }
    case opcode::ADC:
    {
        auto value{read_value()};
        auto result{RegisterA + value + (RegisterP & 0x01)};
        SetFlagsC(result > 0xFF);
        SetFlagsV((~(RegisterA ^ value) & (RegisterA ^ result) & 0x80) != 0);
        RegisterA = static_cast<std::uint8_t>(result);
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::SBC:
    {
        auto value{read_value()};
        auto Complement{static_cast<std::uint8_t>(~value)};
        auto result{RegisterA + Complement + (RegisterP & 0x01)};
        SetFlagsC(result > 0xFF);
        SetFlagsV((~(RegisterA ^ Complement) & (RegisterA ^ result) & 0x80) != 0);
        RegisterA = static_cast<std::uint8_t>(result);
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::AND:
    {
        RegisterA &= read_value();
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::ORA:
    {
        RegisterA |= read_value();
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::EOR:
    {
        RegisterA ^= read_value();
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::CMP:
    {
        auto value{read_value()};
        auto result{RegisterA - value};
        SetFlagsC(RegisterA >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::CPX:
    {
        auto value{read_value()};
        auto result{RegisterX - value};
        SetFlagsC(RegisterX >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::CPY:
    {
        auto value{read_value()};
        auto result{RegisterY - value};
        SetFlagsC(RegisterY >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::BIT:
    {
        auto value{Memory.read(Operand.GetValue())};
        SetFlagsN(value & 0x80);
        SetFlagsV(value & 0x40);
        SetFlagsZ((RegisterA & value) == 0);
        break;
    }
    case opcode::INC:
    {
        auto value{static_cast<std::uint8_t>(Memory.read(Operand.GetValue()) + 1)};
        Memory.write(Operand.GetValue(), value);
        SetFlagsN(value & 0x80);
        SetFlagsZ(value == 0);
        break;
    }
    case opcode::DEC:
    {
        auto value{static_cast<std::uint8_t>(Memory.read(Operand.GetValue()) - 1)};
        Memory.write(Operand.GetValue(), value);
        SetFlagsN(value & 0x80);
        SetFlagsZ(value == 0);
        break;
    }
    case opcode::INX:
    {
        RegisterX++;
        SetFlagsN(RegisterX & 0x80);
        SetFlagsZ(RegisterX == 0);
        break;
    }
    case opcode::INY:
    {
        RegisterY++;
        SetFlagsN(RegisterY & 0x80);
        SetFlagsZ(RegisterY == 0);
        break;
    }
    case opcode::DEX:
    {
        RegisterX--;
        SetFlagsN(RegisterX & 0x80);
        SetFlagsZ(RegisterX == 0);
        break;
    }
    case opcode::DEY:
    {
        RegisterY--;
        SetFlagsN(RegisterY & 0x80);
        SetFlagsZ(RegisterY == 0);
        break;
    }
    case opcode::ASL:
    {
        auto value{read_value()};
        SetFlagsC(value & 0x80);
        auto result{static_cast<std::uint8_t>(value << 1)};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            RegisterA = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::LSR:
    {
        auto value{read_value()};
        SetFlagsC(value & 0x01);
        auto result{static_cast<std::uint8_t>(value >> 1)};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            RegisterA = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::ROL:
    {
        auto value{read_value()};
        SetFlagsC(value & 0x80);
        auto result{static_cast<std::uint8_t>((value << 1) | (RegisterP & 0x01))};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            RegisterA = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::ROR:
    {
        auto value{read_value()};
        SetFlagsC(value & 0x01);
        auto result{static_cast<std::uint8_t>((value >> 1) | ((RegisterP & 0x01) << 7))};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            RegisterA = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::JMP:
    {
        RegisterPC = Operand.GetValue();
        break;
    }
    case opcode::JSR:
    {
        auto ReturnAddress{static_cast<std::uint16_t>(RegisterPC - 1)};
        push(static_cast<std::uint8_t>(ReturnAddress >> 8));
        push(static_cast<std::uint8_t>(ReturnAddress & 0xFF));
        RegisterPC = Operand.GetValue();
        break;
    }
    case opcode::RTS:
    {
        auto LowByte{pop()};
        auto HighByte{pop()};
        RegisterPC = static_cast<std::uint16_t>((HighByte << 8) | LowByte);
        RegisterPC++;
        break;
    }
    case opcode::BRK:
    {
        push(static_cast<std::uint8_t>(RegisterPC >> 8));
        push(static_cast<std::uint8_t>(RegisterPC & 0xFF));
        push(static_cast<std::uint8_t>(RegisterP | 0x10)); // B标志置1后压栈
        RegisterP |= 0x04;                                 // 置I标志
        auto LowByte{Memory.read(0xFFFE)};
        auto HighByte{Memory.read(0xFFFF)};
        RegisterPC = static_cast<std::uint16_t>(LowByte | (HighByte << 8));
        halted = true; // 中断序列完成后停机，前面因为没有这个，直接卡死了，退不出来
        break;
    }
    case opcode::RTI:
    {
        RegisterP = pop();
        auto LowByte{pop()};
        auto HighByte{pop()};
        RegisterPC = static_cast<std::uint16_t>((HighByte << 8) | LowByte);
        break;
    }
    case opcode::BCC:
    {
        if ((RegisterP & 0x01) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BCS:
    {
        if ((RegisterP & 0x01) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BEQ:
    {
        if ((RegisterP & 0x02) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BNE:
    {
        if ((RegisterP & 0x02) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BMI:
    {
        if ((RegisterP & 0x80) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BPL:
    {
        if ((RegisterP & 0x80) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BVC:
    {
        if ((RegisterP & 0x40) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BVS:
    {
        if ((RegisterP & 0x40) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::CLC:
    {
        SetFlagsC(false);
        break;
    }
    case opcode::SEC:
    {
        SetFlagsC(true);
        break;
    }
    case opcode::CLI:
    {
        RegisterP &= ~0x04;
        break;
    }
    case opcode::SEI:
    {
        RegisterP |= 0x04;
        break;
    }
    case opcode::CLV:
    {
        SetFlagsV(false);
        break;
    }
    case opcode::CLD:
    {
        RegisterP &= ~0x08;
        break;
    }
    case opcode::SED:
    {
        RegisterP |= 0x08;
        break;
    }
    case opcode::NOP:
    {
        break;
    }
    case opcode::TAX:
    {
        RegisterX = RegisterA;
        SetFlagsN(RegisterX & 0x80);
        SetFlagsZ(RegisterX == 0);
        break;
    }
    case opcode::TAY:
    {
        RegisterY = RegisterA;
        SetFlagsN(RegisterY & 0x80);
        SetFlagsZ(RegisterY == 0);
        break;
    }
    case opcode::TXA:
    {
        RegisterA = RegisterX;
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::TYA:
    {
        RegisterA = RegisterY;
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::TSX:
    {
        RegisterX = RegisterS;
        SetFlagsN(RegisterX & 0x80);
        SetFlagsZ(RegisterX == 0);
        break;
    }
    case opcode::TXS:
    {
        RegisterS = RegisterX;
        break;
    }
    case opcode::PHA:
    {
        push(RegisterA);
        break;
    }
    case opcode::PLA:
    {
        RegisterA = pop();
        SetFlagsN(RegisterA & 0x80);
        SetFlagsZ(RegisterA == 0);
        break;
    }
    case opcode::PHP:
    {
        push(static_cast<std::uint8_t>(RegisterP | 0x10));
        break;
    }
    case opcode::PLP:
    {
        RegisterP = pop();
        break;
    }
    case opcode::UNKNOWN:
    default:
    {
        halted = true; // 未知操作码直接停机
        break;
    }
    }
}