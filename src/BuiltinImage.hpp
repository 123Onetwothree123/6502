#ifndef BUILTIN_IMAGE_HPP
#define BUILTIN_IMAGE_HPP
#include <array>
#include <cstdint>
#include "memory.hpp"
#include "CentralProcessingUnit.hpp"

class BuiltinImage
{
private:
    static const std::array<std::uint8_t, 7> DefaultImage;

public:
    BuiltinImage() = default;
    ~BuiltinImage() = default;
    void Load(memory &Memory);
    void PrintTrapResult(const CentralProcessingUnit &CPU) const;
};
#endif
