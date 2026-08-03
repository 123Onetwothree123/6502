#ifndef MODE_HPP
#define MODE_HPP
enum class mode // 寻址模式
{
    Implied,
    Immediate,
    Accumulator,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    Indirect,
    IndexedIndirect,
    IndirectIndexed,
    Relative,
    UNKNOWN
};
#endif