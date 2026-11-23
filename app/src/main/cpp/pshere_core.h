#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace pshere {

constexpr std::uint64_t kDefaultRamBudget = 6ULL * 1024ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kPageSize = 4096ULL;

class GuestMemory {
public:
    explicit GuestMemory(std::uint64_t budgetBytes = kDefaultRamBudget);

    bool write(std::uint64_t address, const void* source, std::size_t length);
    bool read(std::uint64_t address, void* destination, std::size_t length) const;
    std::uint64_t budget() const;
    std::uint64_t committed() const;
    std::size_t pageCount() const;

private:
    using Page = std::vector<std::uint8_t>;
    std::uint64_t budgetBytes_;
    std::unordered_map<std::uint64_t, Page> pages_;
};

struct CpuState {
    std::uint64_t registers[16]{};
    std::uint64_t rip = 0;
    bool halted = false;
    std::uint64_t instructionsExecuted = 0;
};

enum class StepResult {
    Executed,
    Halted,
    UnsupportedInstruction,
    MemoryFault
};

class X64Interpreter {
public:
    explicit X64Interpreter(GuestMemory& memory);
    StepResult step(CpuState& state);
    static const char* resultName(StepResult result);

private:
    GuestMemory& memory_;
};

struct SelfTestResult {
    bool passed = false;
    std::uint64_t rax = 0;
    std::uint64_t instructions = 0;
    std::string message;
};

SelfTestResult runSelfTest();

} // namespace pshere
