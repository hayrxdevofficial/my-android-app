#include "pshere_core.h"

#include <algorithm>
#include <cstring>
#include <limits>

namespace pshere {

GuestMemory::GuestMemory(std::uint64_t budgetBytes) : budgetBytes_(budgetBytes) {}

bool GuestMemory::write(std::uint64_t address, const void* source, std::size_t length) {
    if (length == 0) return true;
    if (source == nullptr || address > std::numeric_limits<std::uint64_t>::max() - length) return false;

    const auto firstPage = address / kPageSize;
    const auto lastPage = (address + length - 1) / kPageSize;
    const auto neededPages = lastPage - firstPage + 1;
    if (neededPages > budgetBytes_ / kPageSize) return false;

    const auto newPages = [&]() {
        std::uint64_t count = 0;
        for (auto page = firstPage; page <= lastPage; ++page) {
            if (pages_.find(page) == pages_.end()) ++count;
        }
        return count;
    }();
    if ((pages_.size() + newPages) > budgetBytes_ / kPageSize) return false;

    const auto* input = static_cast<const std::uint8_t*>(source);
    std::size_t remaining = length;
    std::uint64_t cursor = address;
    while (remaining > 0) {
        const auto pageIndex = cursor / kPageSize;
        const auto offset = static_cast<std::size_t>(cursor % kPageSize);
        const auto amount = std::min(remaining, static_cast<std::size_t>(kPageSize) - offset);
        auto& page = pages_[pageIndex];
        if (page.empty()) page.resize(static_cast<std::size_t>(kPageSize), 0);
        std::memcpy(page.data() + offset, input, amount);
        input += amount;
        cursor += amount;
        remaining -= amount;
    }
    return true;
}

bool GuestMemory::read(std::uint64_t address, void* destination, std::size_t length) const {
    if (length == 0) return true;
    if (destination == nullptr || address > std::numeric_limits<std::uint64_t>::max() - length) return false;

    auto* output = static_cast<std::uint8_t*>(destination);
    std::size_t remaining = length;
    std::uint64_t cursor = address;
    while (remaining > 0) {
        const auto pageIndex = cursor / kPageSize;
        const auto offset = static_cast<std::size_t>(cursor % kPageSize);
        const auto amount = std::min(remaining, static_cast<std::size_t>(kPageSize) - offset);
        const auto found = pages_.find(pageIndex);
        if (found == pages_.end()) {
            std::memset(output, 0, amount);
        } else {
            std::memcpy(output, found->second.data() + offset, amount);
        }
        output += amount;
        cursor += amount;
        remaining -= amount;
    }
    return true;
}

std::uint64_t GuestMemory::budget() const { return budgetBytes_; }
std::uint64_t GuestMemory::committed() const { return static_cast<std::uint64_t>(pages_.size()) * kPageSize; }
std::size_t GuestMemory::pageCount() const { return pages_.size(); }

X64Interpreter::X64Interpreter(GuestMemory& memory) : memory_(memory) {}

StepResult X64Interpreter::step(CpuState& state) {
    if (state.halted) return StepResult::Halted;

    std::uint8_t opcode = 0;
    if (!memory_.read(state.rip, &opcode, sizeof(opcode))) return StepResult::MemoryFault;

    if (opcode == 0x90) { // NOP
        ++state.rip;
    } else if (opcode == 0xF4) { // HLT
        ++state.rip;
        state.halted = true;
        ++state.instructionsExecuted;
        return StepResult::Halted;
    } else if (opcode == 0x48) { // REX.W + MOV r64, imm64 (B8+r)
        std::uint8_t operation = 0;
        std::uint64_t immediate = 0;
        if (!memory_.read(state.rip + 1, &operation, sizeof(operation))) return StepResult::MemoryFault;
        if (operation < 0xB8 || operation > 0xBF) return StepResult::UnsupportedInstruction;
        if (!memory_.read(state.rip + 2, &immediate, sizeof(immediate))) return StepResult::MemoryFault;
        state.registers[operation - 0xB8] = immediate;
        state.rip += 10;
    } else {
        return StepResult::UnsupportedInstruction;
    }

    ++state.instructionsExecuted;
    return StepResult::Executed;
}

const char* X64Interpreter::resultName(StepResult result) {
    switch (result) {
        case StepResult::Executed: return "executed";
        case StepResult::Halted: return "halted";
        case StepResult::UnsupportedInstruction: return "unsupported instruction";
        case StepResult::MemoryFault: return "guest memory fault";
    }
    return "unknown";
}

SelfTestResult runSelfTest() {
    GuestMemory memory;
    // MOV RAX, 42; NOP; HLT
    const std::uint8_t program[] = {0x48, 0xB8, 42, 0, 0, 0, 0, 0, 0, 0, 0x90, 0xF4};
    SelfTestResult result;
    if (!memory.write(0x1000, program, sizeof(program))) {
        result.message = "Could not map test program into guest memory";
        return result;
    }

    CpuState cpu;
    cpu.rip = 0x1000;
    X64Interpreter interpreter(memory);
    for (int step = 0; step < 4 && !cpu.halted; ++step) {
        const auto status = interpreter.step(cpu);
        if (status == StepResult::UnsupportedInstruction || status == StepResult::MemoryFault) {
            result.message = X64Interpreter::resultName(status);
            return result;
        }
    }

    const bool cpuPassed = cpu.halted && cpu.registers[0] == 42 &&
                           cpu.instructionsExecuted == 3 && cpu.rip == 0x100C;
    if (!cpuPassed) {
        result.message = "CPU state validation failed";
        return result;
    }

    // Verify cross-page reads/writes and enforce a two-page test budget.
    GuestMemory boundaryMemory(2 * kPageSize);
    const std::uint8_t boundaryInput[] = {0x11, 0x22, 0x33, 0x44};
    std::uint8_t boundaryOutput[sizeof(boundaryInput)]{};
    const bool crossPageWrite = boundaryMemory.write(kPageSize - 2, boundaryInput, sizeof(boundaryInput));
    const bool crossPageRead = boundaryMemory.read(kPageSize - 2, boundaryOutput, sizeof(boundaryOutput));
    const bool crossPageMatches = std::memcmp(boundaryInput, boundaryOutput, sizeof(boundaryInput)) == 0;
    const std::uint8_t overflowByte = 0x55;
    const bool budgetEnforced = !boundaryMemory.write(2 * kPageSize, &overflowByte, sizeof(overflowByte));

    result.rax = cpu.registers[0];
    result.instructions = cpu.instructionsExecuted;
    result.passed = crossPageWrite && crossPageRead && crossPageMatches && budgetEnforced &&
                    boundaryMemory.pageCount() == 2;
    result.message = result.passed
        ? "CPU smoke test and guest-memory boundary tests passed"
        : "Guest-memory boundary or budget test failed";
    return result;
}

} // namespace pshere
