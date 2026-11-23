#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace pshere {

constexpr std::uint64_t kDefaultRamBudget = 6ULL * 1024ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kPageSize = 4096ULL;
constexpr std::uint64_t kDefaultStackTop = 0x00007FFF00000000ULL;

enum Register : std::size_t {
    RAX = 0, RCX, RDX, RBX, RSP, RBP, RSI, RDI,
    R8, R9, R10, R11, R12, R13, R14, R15
};

enum RFlags : std::uint64_t {
    FlagCarry = 1ULL << 0,
    FlagParity = 1ULL << 2,
    FlagAuxiliary = 1ULL << 4,
    FlagZero = 1ULL << 6,
    FlagSign = 1ULL << 7,
    FlagTrap = 1ULL << 8,
    FlagInterrupt = 1ULL << 9,
    FlagDirection = 1ULL << 10,
    FlagOverflow = 1ULL << 11
};

class GuestMemory {
public:
    explicit GuestMemory(std::uint64_t budgetBytes = kDefaultRamBudget);
    bool write(std::uint64_t address, const void* source, std::size_t length);
    bool read(std::uint64_t address, void* destination, std::size_t length) const;
    std::uint64_t budget() const;
    std::uint64_t committed() const;
    std::size_t pageCount() const;
    bool releasePage(std::uint64_t pageAlignedAddress);
private:
    using Page = std::vector<std::uint8_t>;
    std::uint64_t budgetBytes_;
    std::unordered_map<std::uint64_t, Page> pages_;
};

struct CpuState {
    std::uint64_t registers[16]{};
    std::uint64_t rip = 0;
    std::uint64_t rflags = FlagInterrupt | 0x2;
    bool halted = false;
    std::uint64_t instructionsExecuted = 0;

    CpuState();
    bool flag(std::uint64_t mask) const;
    void setFlag(std::uint64_t mask, bool enabled);
};

enum class StepResult {
    Executed,
    Halted,
    UnsupportedInstruction,
    MemoryFault
};

class VirtualAddressSpace;

class X64Interpreter {
public:
    explicit X64Interpreter(GuestMemory& memory);
    explicit X64Interpreter(VirtualAddressSpace& addressSpace);
    StepResult step(CpuState& state);
    static const char* resultName(StepResult result);
private:
    GuestMemory* memory_ = nullptr;
    VirtualAddressSpace* addressSpace_ = nullptr;
};

struct SelfTestResult {
    bool passed = false;
    std::uint64_t rax = 0;
    std::uint64_t instructions = 0;
    std::string message;
};

SelfTestResult runSelfTest();

} // namespace pshere
