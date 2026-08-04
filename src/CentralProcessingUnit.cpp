#include "CentralProcessingUnit.hpp"
void CentralProcessingUnit::SetFlagsN(bool set)
{
    if (set)
    {
        Registers[P] |= 0x80;
    }
    else
    {
        Registers[P] &= ~0x80;
    }
}
void CentralProcessingUnit::SetFlagsZ(bool set)
{
    if (set)
    {
        Registers[P] |= 0x02;
    }
    else
    {
        Registers[P] &= ~0x02;
    }
}
void CentralProcessingUnit::SetFlagsC(bool set)
{
    if (set)
    {
        Registers[P] |= 0x01;
    }
    else
    {
        Registers[P] &= ~0x01;
    }
}
void CentralProcessingUnit::SetFlagsV(bool set)
{
    if (set)
    {
        Registers[P] |= 0x40;
    }
    else
    {
        Registers[P] &= ~0x40;
    }
}
std::uint8_t CentralProcessingUnit::GetRegister(std::size_t index) const
{
    return Registers[index];
}
void CentralProcessingUnit::SetRegister(std::size_t index, std::uint8_t value)
{
    Registers[index] = value;
}
std::uint16_t CentralProcessingUnit::GetRegisterPC() const
{
    return RegisterPC;
}
bool CentralProcessingUnit::IsHalted() const
{
    return halted;
}
CentralProcessingUnit::CentralProcessingUnit(memory &Memory)
    : Memory{Memory}
{
    Registers[S] = 0xFD;
    Registers[P] = 0x20;
    halted = false;
    Registers[A] = 0;
    Registers[X] = 0;
    Registers[Y] = 0;
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
        return (Operand.GetValue() + Registers[X]) & 0xFF;
    }
    case mode::ZeroPageY:
    {
        return (Operand.GetValue() + Registers[Y]) & 0xFF;
    }
    case mode::Absolute:
    {
        return Operand.GetValue();
    }
    case mode::AbsoluteX:
    {
        return Operand.GetValue() + Registers[X];
    }
    case mode::AbsoluteY:
    {
        return Operand.GetValue() + Registers[Y];
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
        auto pointer{static_cast<std::uint8_t>((Operand.GetValue() + Registers[X]) & 0xFF)};
        auto LowByte{Memory.read(pointer)};
        auto HighByte{Memory.read(static_cast<std::uint8_t>(pointer + 1))};
        return LowByte | (HighByte << 8);
    }
    case mode::IndirectIndexed:
    {
        auto pointer{static_cast<std::uint8_t>(Operand.GetValue() & 0xFF)};
        auto base{Memory.read(pointer) | (Memory.read(static_cast<std::uint8_t>(pointer + 1)) << 8)};
        return base + Registers[Y];
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
    case mode::IndirectIndexed:
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
    Memory.write(static_cast<std::uint16_t>(CONFIG_STACK_BASE + Registers[S]), value);
    Registers[S]--;
}
std::uint8_t CentralProcessingUnit::pop()
{
    Registers[S]++;
    return Memory.read(static_cast<std::uint16_t>(CONFIG_STACK_BASE + Registers[S]));
}
void CentralProcessingUnit::reset()
{
    Registers[A] = 0;
    Registers[X] = 0;
    Registers[Y] = 0;
    Registers[S] = 0xFD;
    Registers[P] = 0x20;
    halted = false;
    auto LowByte{Memory.read(CONFIG_RESET_PC)};
    auto HighByte{Memory.read(CONFIG_RESET_PC + 1)};
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
                        return Registers[A];
                    }};
    switch (Opcode.GetOpcode())
    {
    case opcode::LDA:
    {
        Registers[A] = read_value();
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::LDX:
    {
        Registers[X] = read_value();
        SetFlagsN(Registers[X] & 0x80);
        SetFlagsZ(Registers[X] == 0);
        break;
    }
    case opcode::LDY:
    {
        Registers[Y] = read_value();
        SetFlagsN(Registers[Y] & 0x80);
        SetFlagsZ(Registers[Y] == 0);
        break;
    }
    case opcode::STA:
    {
        Memory.write(Operand.GetValue(), Registers[A]);
        break;
    }
    case opcode::STX:
    {
        Memory.write(Operand.GetValue(), Registers[X]);
        break;
    }
    case opcode::STY:
    {
        Memory.write(Operand.GetValue(), Registers[Y]);
        break;
    }
    case opcode::ADC:
    {
        auto value{read_value()};
        auto result{Registers[A] + value + (Registers[P] & 0x01)};
        SetFlagsC(result > 0xFF);
        SetFlagsV((~(Registers[A] ^ value) & (Registers[A] ^ result) & 0x80) != 0);
        Registers[A] = static_cast<std::uint8_t>(result);
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::SBC:
    {
        auto value{read_value()};
        auto Complement{static_cast<std::uint8_t>(~value)};
        auto result{Registers[A] + Complement + (Registers[P] & 0x01)};
        SetFlagsC(result > 0xFF);
        SetFlagsV((~(Registers[A] ^ Complement) & (Registers[A] ^ result) & 0x80) != 0);
        Registers[A] = static_cast<std::uint8_t>(result);
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::AND:
    {
        Registers[A] &= read_value();
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::ORA:
    {
        Registers[A] |= read_value();
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::EOR:
    {
        Registers[A] ^= read_value();
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::CMP:
    {
        auto value{read_value()};
        auto result{Registers[A] - value};
        SetFlagsC(Registers[A] >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::CPX:
    {
        auto value{read_value()};
        auto result{Registers[X] - value};
        SetFlagsC(Registers[X] >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::CPY:
    {
        auto value{read_value()};
        auto result{Registers[Y] - value};
        SetFlagsC(Registers[Y] >= value);
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::BIT:
    {
        auto value{Memory.read(Operand.GetValue())};
        SetFlagsN(value & 0x80);
        SetFlagsV(value & 0x40);
        SetFlagsZ((Registers[A] & value) == 0);
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
        Registers[X]++;
        SetFlagsN(Registers[X] & 0x80);
        SetFlagsZ(Registers[X] == 0);
        break;
    }
    case opcode::INY:
    {
        Registers[Y]++;
        SetFlagsN(Registers[Y] & 0x80);
        SetFlagsZ(Registers[Y] == 0);
        break;
    }
    case opcode::DEX:
    {
        Registers[X]--;
        SetFlagsN(Registers[X] & 0x80);
        SetFlagsZ(Registers[X] == 0);
        break;
    }
    case opcode::DEY:
    {
        Registers[Y]--;
        SetFlagsN(Registers[Y] & 0x80);
        SetFlagsZ(Registers[Y] == 0);
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
            Registers[A] = result;
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
            Registers[A] = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::ROL:
    {
        auto value{read_value()};
        auto OldCarry{Registers[P] & 0x01};      // 旧C先保存（移位结果要用）
        SetFlagsC(value & 0x80);                // 新C = 旧值最高位
        auto result{static_cast<std::uint8_t>((value << 1) | OldCarry)};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            Registers[A] = result;
        }
        SetFlagsN(result & 0x80);
        SetFlagsZ(result == 0);
        break;
    }
    case opcode::ROR:
    {
        auto value{read_value()};
        auto OldCarry{Registers[P] & 0x01};      // 旧C先保存（移位结果要用）
        SetFlagsC(value & 0x01);                // 新C = 旧值最低位
        auto result{static_cast<std::uint8_t>((value >> 1) | (OldCarry << 7))};
        if (Operand.GetKind() == kind::Address)
        {
            Memory.write(Operand.GetValue(), result);
        }
        else
        {
            Registers[A] = result;
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
        push(static_cast<std::uint8_t>(Registers[P] | 0x10)); // B标志置1后压栈
        Registers[P] |= 0x04;                                 // 置I标志
        auto LowByte{Memory.read(0xFFFE)};
        auto HighByte{Memory.read(0xFFFF)};
        RegisterPC = static_cast<std::uint16_t>(LowByte | (HighByte << 8));
        halted = true; // 中断序列完成后停机，前面因为没有这个，直接卡死了，退不出来
        break;
    }
    case opcode::RTI:
    {
        Registers[P] = pop();
        auto LowByte{pop()};
        auto HighByte{pop()};
        RegisterPC = static_cast<std::uint16_t>((HighByte << 8) | LowByte);
        break;
    }
    case opcode::BCC:
    {
        if ((Registers[P] & 0x01) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BCS:
    {
        if ((Registers[P] & 0x01) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BEQ:
    {
        if ((Registers[P] & 0x02) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BNE:
    {
        if ((Registers[P] & 0x02) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BMI:
    {
        if ((Registers[P] & 0x80) != 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BPL:
    {
        if ((Registers[P] & 0x80) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BVC:
    {
        if ((Registers[P] & 0x40) == 0)
        {
            RegisterPC = static_cast<std::uint16_t>(RegisterPC + static_cast<int8_t>(Operand.GetValue()));
        }
        break;
    }
    case opcode::BVS:
    {
        if ((Registers[P] & 0x40) != 0)
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
        Registers[P] &= ~0x04;
        break;
    }
    case opcode::SEI:
    {
        Registers[P] |= 0x04;
        break;
    }
    case opcode::CLV:
    {
        SetFlagsV(false);
        break;
    }
    case opcode::CLD:
    {
        Registers[P] &= ~0x08;
        break;
    }
    case opcode::SED:
    {
        Registers[P] |= 0x08;
        break;
    }
    case opcode::NOP:
    {
        break;
    }
    case opcode::TAX:
    {
        Registers[X] = Registers[A];
        SetFlagsN(Registers[X] & 0x80);
        SetFlagsZ(Registers[X] == 0);
        break;
    }
    case opcode::TAY:
    {
        Registers[Y] = Registers[A];
        SetFlagsN(Registers[Y] & 0x80);
        SetFlagsZ(Registers[Y] == 0);
        break;
    }
    case opcode::TXA:
    {
        Registers[A] = Registers[X];
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::TYA:
    {
        Registers[A] = Registers[Y];
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::TSX:
    {
        Registers[X] = Registers[S];
        SetFlagsN(Registers[X] & 0x80);
        SetFlagsZ(Registers[X] == 0);
        break;
    }
    case opcode::TXS:
    {
        Registers[S] = Registers[X];
        break;
    }
    case opcode::PHA:
    {
        push(Registers[A]);
        break;
    }
    case opcode::PLA:
    {
        Registers[A] = pop();
        SetFlagsN(Registers[A] & 0x80);
        SetFlagsZ(Registers[A] == 0);
        break;
    }
    case opcode::PHP:
    {
        push(static_cast<std::uint8_t>(Registers[P] | 0x10));
        break;
    }
    case opcode::PLP:
    {
        Registers[P] = pop();
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