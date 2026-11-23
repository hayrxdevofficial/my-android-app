#pragma once

#include "pshere_core.h"

#include <cstdint>
#include <unordered_map>

namespace pshere {

enum MemoryPermission : std::uint8_t { MemRead = 1U, MemWrite = 2U, MemExecute = 4U };

class VirtualAddressSpace {
public:
    explicit VirtualAddressSpace(GuestMemory& backing);
    bool map(std::uint64_t address, std::uint64_t size, std::uint8_t permissions);
    bool unmap(std::uint64_t address, std::uint64_t size);
    bool protect(std::uint64_t address, std::uint64_t size, std::uint8_t permissions);
    bool read(std::uint64_t address, void* destination, std::size_t length) const;
    bool write(std::uint64_t address, const void* source, std::size_t length);
    bool fetch(std::uint64_t address, void* destination, std::size_t length) const;
    bool isMapped(std::uint64_t address) const;
    bool hasPermission(std::uint64_t address, std::uint8_t permission) const;
    std::size_t mappedPageCount() const;
private:
    struct Mapping { std::uint64_t backingAddress = 0; std::uint8_t permissions = 0; };
    bool transfer(std::uint64_t address, void* buffer, std::size_t length,
                  std::uint8_t requiredPermission, bool writeAccess) const;
    GuestMemory& backing_;
    std::unordered_map<std::uint64_t, Mapping> pages_;
    std::uint64_t nextBackingPage_ = 1;
};

struct ElfLoadResult {
    bool success = false;
    std::uint64_t entryPoint = 0;
    std::uint64_t stackPointer = 0;
    std::uint64_t imageBase = 0;
    std::size_t loadedSegments = 0;
    std::string message;
};

class Elf64Loader {
public:
    static ElfLoadResult loadStaticExecutable(VirtualAddressSpace& addressSpace,
                                              const std::uint8_t* data,
                                              std::size_t size);
};

bool runVirtualMemorySelfTest(std::string& message);
bool runElfLoaderSelfTest(std::string& message);

} // namespace pshere
