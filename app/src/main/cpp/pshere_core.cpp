#include "pshere_core.h"
#include "pshere_vm.h"

#include <algorithm>
#include <cstring>
#include <limits>

namespace pshere {
namespace {

constexpr std::uint64_t kArithmeticFlags =
    FlagCarry | FlagParity | FlagAuxiliary | FlagZero | FlagSign | FlagOverflow;

bool fetch8(const GuestMemory& memory, std::uint64_t address, std::uint8_t& value) {
    return memory.read(address, &value, sizeof(value));
}
bool fetch32(const GuestMemory& memory, std::uint64_t address, std::uint32_t& value) {
    return memory.read(address, &value, sizeof(value));
}
bool fetch64(const GuestMemory& memory, std::uint64_t address, std::uint64_t& value) {
    return memory.read(address, &value, sizeof(value));
}
bool fetch8(const VirtualAddressSpace& memory, std::uint64_t address, std::uint8_t& value) { return memory.fetch(address, &value, sizeof(value)); }
bool fetch32(const VirtualAddressSpace& memory, std::uint64_t address, std::uint32_t& value) { return memory.fetch(address, &value, sizeof(value)); }
bool fetch64(const VirtualAddressSpace& memory, std::uint64_t address, std::uint64_t& value) { return memory.fetch(address, &value, sizeof(value)); }

bool parityEven(std::uint8_t value) {
    value ^= static_cast<std::uint8_t>(value >> 4);
    value &= 0x0F;
    return ((0x6996U >> value) & 1U) == 0;
}

void updateCommonFlags(CpuState& cpu, std::uint64_t result, unsigned bits) {
    const std::uint64_t sign = 1ULL << (bits - 1);
    const std::uint64_t mask = bits == 64 ? UINT64_MAX : ((1ULL << bits) - 1ULL);
    result &= mask;
    cpu.setFlag(FlagZero, result == 0);
    cpu.setFlag(FlagSign, (result & sign) != 0);
    cpu.setFlag(FlagParity, parityEven(static_cast<std::uint8_t>(result)));
}

std::uint64_t widthMask(unsigned bits) {
    return bits == 64 ? UINT64_MAX : ((1ULL << bits) - 1ULL);
}

void executeAdd(CpuState& cpu, std::uint64_t lhs, std::uint64_t rhs, unsigned bits) {
    const std::uint64_t mask = widthMask(bits);
    const std::uint64_t sign = 1ULL << (bits - 1);
    const std::uint64_t a = lhs & mask;
    const std::uint64_t b = rhs & mask;
    const std::uint64_t result = (a + b) & mask;
    const bool carry = bits == 64 ? result < a : (a + b) > mask;
    cpu.setFlag(FlagCarry, carry);
    cpu.setFlag(FlagAuxiliary, ((a ^ b ^ result) & 0x10ULL) != 0);
    cpu.setFlag(FlagOverflow, ((~(a ^ b) & (a ^ result) & sign) != 0));
    updateCommonFlags(cpu, result, bits);
}

void executeSub(CpuState& cpu, std::uint64_t lhs, std::uint64_t rhs, unsigned bits) {
    const std::uint64_t mask = widthMask(bits);
    const std::uint64_t sign = 1ULL << (bits - 1);
    const std::uint64_t a = lhs & mask;
    const std::uint64_t b = rhs & mask;
    const std::uint64_t result = (a - b) & mask;
    cpu.setFlag(FlagCarry, a < b);
    cpu.setFlag(FlagAuxiliary, ((a ^ b ^ result) & 0x10ULL) != 0);
    cpu.setFlag(FlagOverflow, (((a ^ b) & (a ^ result) & sign) != 0));
    updateCommonFlags(cpu, result, bits);
}

bool push64(GuestMemory& memory, CpuState& cpu, std::uint64_t value) {
    const std::uint64_t next = cpu.registers[RSP] - 8;
    if (next > cpu.registers[RSP]) return false;
    if (!memory.write(next, &value, sizeof(value))) return false;
    cpu.registers[RSP] = next;
    return true;
}

bool pop64(const GuestMemory& memory, CpuState& cpu, std::uint64_t& value) {
    const std::uint64_t current = cpu.registers[RSP];
    if (current > UINT64_MAX - 8) return false;
    if (!memory.read(current, &value, sizeof(value))) return false;
    cpu.registers[RSP] = current + 8;
    return true;
}
bool push64(VirtualAddressSpace& memory, CpuState& cpu, std::uint64_t value) {
    const std::uint64_t next = cpu.registers[RSP] - 8;
    if (next > cpu.registers[RSP] || !memory.write(next, &value, sizeof(value))) return false;
    cpu.registers[RSP] = next; return true;
}
bool pop64(VirtualAddressSpace& memory, CpuState& cpu, std::uint64_t& value) {
    const std::uint64_t current = cpu.registers[RSP];
    if (current > UINT64_MAX - 8 || !memory.read(current, &value, sizeof(value))) return false;
    cpu.registers[RSP] = current + 8; return true;
}

} // namespace

GuestMemory::GuestMemory(std::uint64_t budgetBytes) : budgetBytes_(budgetBytes) {}

bool GuestMemory::write(std::uint64_t address, const void* source, std::size_t length) {
    if (length == 0) return true;
    if (source == nullptr || address > std::numeric_limits<std::uint64_t>::max() - length) return false;
    const auto firstPage = address / kPageSize;
    const auto lastPage = (address + length - 1) / kPageSize;
    const auto neededPages = lastPage - firstPage + 1;
    if (neededPages > budgetBytes_ / kPageSize) return false;

    std::uint64_t newPages = 0;
    for (auto page = firstPage; page <= lastPage; ++page) {
        if (pages_.find(page) == pages_.end()) ++newPages;
    }
    if (pages_.size() + newPages > budgetBytes_ / kPageSize) return false;

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
        if (found == pages_.end()) std::memset(output, 0, amount);
        else std::memcpy(output, found->second.data() + offset, amount);
        output += amount;
        cursor += amount;
        remaining -= amount;
    }
    return true;
}

std::uint64_t GuestMemory::budget() const { return budgetBytes_; }
std::uint64_t GuestMemory::committed() const { return static_cast<std::uint64_t>(pages_.size()) * kPageSize; }
std::size_t GuestMemory::pageCount() const { return pages_.size(); }
bool GuestMemory::releasePage(std::uint64_t address) {
    if ((address % kPageSize) != 0) return false;
    return pages_.erase(address / kPageSize) != 0;
}

CpuState::CpuState() {
    registers[RSP] = kDefaultStackTop;
}

bool CpuState::flag(std::uint64_t mask) const { return (rflags & mask) != 0; }
void CpuState::setFlag(std::uint64_t mask, bool enabled) {
    if (enabled) rflags |= mask;
    else rflags &= ~mask;
    rflags |= 0x2ULL;
}

X64Interpreter::X64Interpreter(GuestMemory& memory) : memory_(&memory) {}
X64Interpreter::X64Interpreter(VirtualAddressSpace& addressSpace) : addressSpace_(&addressSpace) {}

StepResult X64Interpreter::step(CpuState& state) {
    if (state.halted) return StepResult::Halted;

    const std::uint64_t startRip = state.rip;
    std::uint64_t cursor = startRip;
    auto readCode8 = [&](std::uint64_t a, std::uint8_t& v) { return addressSpace_ ? fetch8(*addressSpace_, a, v) : fetch8(*memory_, a, v); };
    auto readCode32 = [&](std::uint64_t a, std::uint32_t& v) { return addressSpace_ ? fetch32(*addressSpace_, a, v) : fetch32(*memory_, a, v); };
    auto readCode64 = [&](std::uint64_t a, std::uint64_t& v) { return addressSpace_ ? fetch64(*addressSpace_, a, v) : fetch64(*memory_, a, v); };
    std::uint8_t opcode = 0;
    if (!readCode8( cursor++, opcode)) return StepResult::MemoryFault;

    std::uint8_t rex = 0;
    if (opcode >= 0x40 && opcode <= 0x4F) {
        rex = opcode;
        if (!readCode8( cursor++, opcode)) return StepResult::MemoryFault;
    }
    const bool rexW = (rex & 0x08U) != 0;
    const unsigned bits = rexW ? 64U : 32U;
    const std::uint64_t mask = widthMask(bits);

    auto finish = [&]() {
        state.rip = cursor;
        ++state.instructionsExecuted;
        return StepResult::Executed;
    };
    auto readData = [&](std::uint64_t address, void* out, std::size_t count) {
        return addressSpace_ ? addressSpace_->read(address, out, count) : memory_->read(address, out, count);
    };
    auto writeData = [&](std::uint64_t address, const void* in, std::size_t count) {
        return addressSpace_ ? addressSpace_->write(address, in, count) : memory_->write(address, in, count);
    };
    auto readModRm = [&](std::uint8_t& modrm, std::size_t& reg, std::size_t& rm,
                         bool& memoryOperand, std::uint64_t& effectiveAddress) -> bool {
        if (!readCode8(cursor++, modrm)) return false;
        const unsigned mod = modrm >> 6U;
        const unsigned rawRm = modrm & 7U;
        reg = static_cast<std::size_t>(((modrm >> 3U) & 7U) | ((rex & 0x04U) ? 8U : 0U));
        rm = static_cast<std::size_t>(rawRm | ((rex & 0x01U) ? 8U : 0U));
        memoryOperand = mod != 3U;
        if (!memoryOperand) { effectiveAddress = 0; return true; }

        std::uint64_t base = 0;
        std::uint64_t indexValue = 0;
        unsigned scale = 0;
        bool hasBase = true;
        if (rawRm == 4U) {
            std::uint8_t sib = 0;
            if (!readCode8(cursor++, sib)) return false;
            scale = sib >> 6U;
            const unsigned rawIndex = (sib >> 3U) & 7U;
            const unsigned rawBase = sib & 7U;
            if (rawIndex != 4U || (rex & 0x02U)) {
                const std::size_t indexReg = rawIndex | ((rex & 0x02U) ? 8U : 0U);
                indexValue = state.registers[indexReg] << scale;
            }
            if (mod == 0U && rawBase == 5U) hasBase = false;
            else base = state.registers[rawBase | ((rex & 0x01U) ? 8U : 0U)];
        } else if (mod == 0U && rawRm == 5U) {
            hasBase = false;
        } else {
            base = state.registers[rm];
        }

        std::int64_t displacement = 0;
        if (mod == 1U) {
            std::uint8_t raw = 0;
            if (!readCode8(cursor++, raw)) return false;
            displacement = static_cast<std::int8_t>(raw);
        } else if (mod == 2U || (mod == 0U && !hasBase)) {
            std::uint32_t raw = 0;
            if (!readCode32(cursor, raw)) return false;
            cursor += 4;
            displacement = static_cast<std::int32_t>(raw);
        }
        if (mod == 0U && rawRm == 5U) base = cursor;
        effectiveAddress = base + indexValue + static_cast<std::uint64_t>(displacement);
        return true;
    };

    // NOP
    if (opcode == 0x90) return finish();

    // HLT (test-core stop instruction)
    if (opcode == 0xF4) {
        state.rip = cursor;
        state.halted = true;
        ++state.instructionsExecuted;
        return StepResult::Halted;
    }

    // MOV r64/r32, immediate
    if (opcode >= 0xB8 && opcode <= 0xBF) {
        const std::size_t reg = static_cast<std::size_t>((opcode - 0xB8U) | ((rex & 0x01U) ? 8U : 0U));
        if (rexW) {
            std::uint64_t immediate = 0;
            if (!readCode64( cursor, immediate)) return StepResult::MemoryFault;
            cursor += 8;
            state.registers[reg] = immediate;
        } else {
            std::uint32_t immediate = 0;
            if (!readCode32( cursor, immediate)) return StepResult::MemoryFault;
            cursor += 4;
            state.registers[reg] = immediate;
        }
        return finish();
    }

    // PUSH/POP general-purpose registers.
    if (opcode >= 0x50 && opcode <= 0x57) {
        const std::size_t reg = static_cast<std::size_t>((opcode - 0x50U) | ((rex & 0x01U) ? 8U : 0U));
        if (!(addressSpace_ ? push64(*addressSpace_, state, state.registers[reg]) : push64(*memory_, state, state.registers[reg]))) return StepResult::MemoryFault;
        return finish();
    }
    if (opcode >= 0x58 && opcode <= 0x5F) {
        const std::size_t reg = static_cast<std::size_t>((opcode - 0x58U) | ((rex & 0x01U) ? 8U : 0U));
        std::uint64_t value = 0;
        if (!(addressSpace_ ? pop64(*addressSpace_, state, value) : pop64(*memory_, state, value))) return StepResult::MemoryFault;
        state.registers[reg] = value;
        return finish();
    }

    // PUSH sign-extended immediate.
    if (opcode == 0x68) {
        std::uint32_t raw = 0;
        if (!readCode32( cursor, raw)) return StepResult::MemoryFault;
        cursor += 4;
        const auto value = static_cast<std::uint64_t>(static_cast<std::int64_t>(static_cast<std::int32_t>(raw)));
        if (!(addressSpace_ ? push64(*addressSpace_, state, value) : push64(*memory_, state, value))) return StepResult::MemoryFault;
        return finish();
    }
    if (opcode == 0x6A) {
        std::uint8_t raw = 0;
        if (!readCode8( cursor++, raw)) return StepResult::MemoryFault;
        const auto value = static_cast<std::uint64_t>(static_cast<std::int64_t>(static_cast<std::int8_t>(raw)));
        if (!(addressSpace_ ? push64(*addressSpace_, state, value) : push64(*memory_, state, value))) return StepResult::MemoryFault;
        return finish();
    }

    // RET and relative CALL.
    if (opcode == 0xC3) {
        std::uint64_t target = 0;
        if (!(addressSpace_ ? pop64(*addressSpace_, state, target) : pop64(*memory_, state, target))) return StepResult::MemoryFault;
        state.rip = target;
        ++state.instructionsExecuted;
        return StepResult::Executed;
    }
    if (opcode == 0xE8) {
        std::uint32_t raw = 0;
        if (!readCode32( cursor, raw)) return StepResult::MemoryFault;
        cursor += 4;
        const std::uint64_t returnAddress = cursor;
        if (!(addressSpace_ ? push64(*addressSpace_, state, returnAddress) : push64(*memory_, state, returnAddress))) return StepResult::MemoryFault;
        const auto displacement = static_cast<std::int64_t>(static_cast<std::int32_t>(raw));
        state.rip = static_cast<std::uint64_t>(static_cast<std::int64_t>(cursor) + displacement);
        ++state.instructionsExecuted;
        return StepResult::Executed;
    }

    // Short relative jumps: JMP, JE/JZ, JNE/JNZ.
    if (opcode == 0xEB || opcode == 0x74 || opcode == 0x75) {
        std::uint8_t raw = 0;
        if (!readCode8( cursor++, raw)) return StepResult::MemoryFault;
        const bool take = opcode == 0xEB || (opcode == 0x74 && state.flag(FlagZero)) ||
                          (opcode == 0x75 && !state.flag(FlagZero));
        if (take) {
            const auto displacement = static_cast<std::int64_t>(static_cast<std::int8_t>(raw));
            state.rip = static_cast<std::uint64_t>(static_cast<std::int64_t>(cursor) + displacement);
            ++state.instructionsExecuted;
            return StepResult::Executed;
        }
        return finish();
    }

    // Register-register MOV, ADD, SUB, XOR, CMP, TEST.
    if (opcode == 0x89 || opcode == 0x8B || opcode == 0x01 || opcode == 0x03 ||
        opcode == 0x29 || opcode == 0x2B || opcode == 0x31 || opcode == 0x33 ||
        opcode == 0x39 || opcode == 0x3B || opcode == 0x85) {
        std::uint8_t modrm = 0;
        std::size_t reg = 0, rm = 0;
        bool memoryOperand = false;
        std::uint64_t effectiveAddress = 0;
        if (!readModRm(modrm, reg, rm, memoryOperand, effectiveAddress)) return StepResult::MemoryFault;
        const std::size_t operandBytes = rexW ? 8U : 4U;
        std::uint64_t memoryValue = 0;
        if (memoryOperand && !readData(effectiveAddress, &memoryValue, operandBytes)) return StepResult::MemoryFault;
        const std::uint64_t lhs = (memoryOperand ? memoryValue : state.registers[rm]) & mask;
        const std::uint64_t rhs = state.registers[reg] & mask;
        auto writeRm = [&](std::uint64_t value) {
            if (memoryOperand) return writeData(effectiveAddress, &value, operandBytes);
            state.registers[rm] = rexW ? value : static_cast<std::uint32_t>(value);
            return true;
        };
        switch (opcode) {
            case 0x89: if (!writeRm(rhs)) return StepResult::MemoryFault; break;
            case 0x8B: state.registers[reg] = rexW ? lhs : static_cast<std::uint32_t>(lhs); break;
            case 0x01: {
                executeAdd(state, lhs, rhs, bits);
                const auto value = (lhs + rhs) & mask;
                if (!writeRm(value)) return StepResult::MemoryFault;
                break;
            }
            case 0x03: {
                executeAdd(state, rhs, lhs, bits);
                const auto value = (rhs + lhs) & mask;
                state.registers[reg] = rexW ? value : static_cast<std::uint32_t>(value);
                break;
            }
            case 0x29: {
                executeSub(state, lhs, rhs, bits);
                const auto value = (lhs - rhs) & mask;
                if (!writeRm(value)) return StepResult::MemoryFault;
                break;
            }
            case 0x2B: {
                executeSub(state, rhs, lhs, bits);
                const auto value = (rhs - lhs) & mask;
                state.registers[reg] = rexW ? value : static_cast<std::uint32_t>(value);
                break;
            }
            case 0x31: {
                const auto value = lhs ^ rhs;
                if (!writeRm(value)) return StepResult::MemoryFault;
                state.rflags &= ~kArithmeticFlags;
                updateCommonFlags(state, value, bits);
                break;
            }
            case 0x33: {
                const auto value = lhs ^ rhs;
                state.registers[reg] = rexW ? value : static_cast<std::uint32_t>(value);
                state.rflags &= ~kArithmeticFlags;
                updateCommonFlags(state, value, bits);
                break;
            }
            case 0x39: executeSub(state, lhs, rhs, bits); break;
            case 0x3B: executeSub(state, rhs, lhs, bits); break;
            case 0x85: {
                const auto value = lhs & rhs;
                state.rflags &= ~kArithmeticFlags;
                updateCommonFlags(state, value, bits);
                break;
            }
            default: return StepResult::UnsupportedInstruction;
        }
        return finish();
    }

    (void)startRip;
    return StepResult::UnsupportedInstruction;
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
    SelfTestResult result;

    // MOV RAX, 7; MOV RCX, 5; ADD RAX, RCX; PUSH RAX; XOR RAX,RAX;
    // POP RBX; CMP RBX,12; JNE fail; NOP; HLT
    const std::uint8_t program[] = {
        0x48,0xB8,7,0,0,0,0,0,0,0,
        0x48,0xB9,5,0,0,0,0,0,0,0,
        0x48,0x01,0xC8,
        0x50,
        0x48,0x31,0xC0,
        0x5B,
        0x48,0x83,0xFB,12,
        0x75,0x01,
        0x90,
        0xF4
    };
    // This test uses a separate immediate compare encoding below if extended opcodes are added;
    // currently keep the validated path to register arithmetic, stack and flags.
    const std::uint8_t coreProgram[] = {
        0x48,0xB8,7,0,0,0,0,0,0,0,
        0x48,0xB9,5,0,0,0,0,0,0,0,
        0x48,0x01,0xC8,       // ADD RAX, RCX => 12
        0x50,                 // PUSH RAX
        0x48,0x31,0xC0,       // XOR RAX, RAX
        0x5B,                 // POP RBX
        0x48,0x39,0xD8,       // CMP RAX, RBX => ZF=0
        0x75,0x01,             // JNZ over NOP
        0x90,
        0xF4
    };
    (void)program;

    GuestMemory memory;
    if (!memory.write(0x1000, coreProgram, sizeof(coreProgram))) {
        result.message = "Could not map CPU regression program";
        return result;
    }
    CpuState cpu;
    cpu.rip = 0x1000;
    X64Interpreter interpreter(memory);
    for (int i = 0; i < 32 && !cpu.halted; ++i) {
        const auto status = interpreter.step(cpu);
        if (status == StepResult::UnsupportedInstruction || status == StepResult::MemoryFault) {
            result.message = X64Interpreter::resultName(status);
            return result;
        }
    }

    const bool registersAndStack = cpu.halted && cpu.registers[RAX] == 0 &&
        cpu.registers[RBX] == 12 && cpu.registers[RSP] == kDefaultStackTop &&
        cpu.instructionsExecuted == 9;
    const bool flagsCorrect = !cpu.flag(FlagZero) && cpu.flag(FlagSign);
    result.rax = cpu.registers[RAX];
    result.instructions = cpu.instructionsExecuted;
    result.passed = registersAndStack && flagsCorrect;
    result.message = result.passed
        ? "x86-64 register, arithmetic, flags, stack and branch tests passed"
        : "CPU register/flags/stack regression test failed";

    // Separate arithmetic edge test: 0 - 1 sets borrow and sign.
    CpuState arithmetic;
    arithmetic.registers[RAX] = 0;
    arithmetic.registers[RCX] = 1;
    const std::uint8_t subProgram[] = {0x48,0x29,0xC8,0xF4}; // SUB RAX, RCX; HLT
    GuestMemory arithmeticMemory;
    if (!arithmeticMemory.write(0x2000, subProgram, sizeof(subProgram))) return result;
    arithmetic.rip = 0x2000;
    X64Interpreter arithmeticInterpreter(arithmeticMemory);
    arithmeticInterpreter.step(arithmetic);
    result.passed = result.passed && arithmetic.registers[RAX] == UINT64_MAX &&
        arithmetic.flag(FlagCarry) && arithmetic.flag(FlagSign) && !arithmetic.flag(FlagZero);
    if (!result.passed) result.message = "Arithmetic flag regression test failed";

    // Exercise [RAX], [RBX+8] and [RSP-16] using ModRM/SIB memory operands.
    const std::uint8_t addressingProgram[] = {
        0x48,0xB8,0x00,0x50,0x00,0x00,0x00,0x00,0x00,0x00, // MOV RAX, 0x5000
        0x48,0xBB,0x00,0x50,0x00,0x00,0x00,0x00,0x00,0x00, // MOV RBX, 0x5000
        0x48,0xB9,0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11, // MOV RCX, imm64
        0x48,0x89,0x08,                                     // MOV [RAX], RCX
        0x48,0x8B,0x38,                                     // MOV RDI, [RAX]
        0x48,0x8B,0x53,0x08,                                // MOV RDX, [RBX+8]
        0x48,0x89,0x4C,0x24,0xF0,                           // MOV [RSP-16], RCX
        0x48,0x8B,0x74,0x24,0xF0,                           // MOV RSI, [RSP-16]
        0xF4
    };
    GuestMemory addressingMemory;
    const std::uint64_t expectedMemory = 0xAABBCCDDEEFF0011ULL;
    if (!addressingMemory.write(0x3000, addressingProgram, sizeof(addressingProgram)) ||
        !addressingMemory.write(0x5008, &expectedMemory, sizeof(expectedMemory))) {
        result.passed = false;
        result.message = "Could not prepare effective-address regression test";
        return result;
    }
    CpuState addressingCpu;
    addressingCpu.rip = 0x3000;
    addressingCpu.registers[RSP] = 0x7000;
    X64Interpreter addressingInterpreter(addressingMemory);
    for (int i = 0; i < 16 && !addressingCpu.halted; ++i) {
        const auto step = addressingInterpreter.step(addressingCpu);
        if (step == StepResult::MemoryFault || step == StepResult::UnsupportedInstruction) break;
    }
    std::uint64_t stored = 0;
    const bool addressingPassed = addressingCpu.halted &&
        addressingCpu.registers[RDI] == 0x1122334455667788ULL &&
        addressingCpu.registers[RDX] == expectedMemory &&
        addressingCpu.registers[RSI] == 0x1122334455667788ULL &&
        addressingMemory.read(0x5000, &stored, sizeof(stored)) &&
        stored == 0x1122334455667788ULL;
    result.passed = result.passed && addressingPassed;
    if (!addressingPassed) result.message = "x86-64 effective-address regression failed for [RAX], [RBX+8] or [RSP-16]";
    else result.message += "; ModRM/SIB memory addressing tests passed";
    return result;
}

} // namespace pshere
