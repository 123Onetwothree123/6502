#ifndef BUILTIN_IMAGE_HPP
#define BUILTIN_IMAGE_HPP
#include <array>
#include <cstdint>
#include "memory.hpp"
#include "CentralProcessingUnit.hpp"

class builtin_image
{
private:
    static const std::array<std::uint8_t, 7> DefaultImage;

public:
    builtin_image() = default;
    ~builtin_image() = default;
    void Load(memory &Memory);
    void PrintTrapResult(const CentralProcessingUnit &CPU) const;
};
#endif
