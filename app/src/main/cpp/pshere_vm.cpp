#include "pshere_vm.h"

#include <algorithm>
#include <cstring>
#include <elf.h>
#include <limits>
#include <map>
#include <vector>

namespace pshere {
namespace {
constexpr std::uint64_t kUserAddressLimit = 0x0000800000000000ULL;
constexpr std::uint64_t kStackSize = 8ULL * 1024ULL * 1024ULL;
constexpr std::size_t kMaxElfBytes = 128ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kMaxLoadedBytes = 256ULL * 1024ULL * 1024ULL;

bool alignedRange(std::uint64_t address, std::uint64_t size) {
    return size != 0 && (address % kPageSize) == 0 &&
           (size % kPageSize) == 0 && address < kUserAddressLimit &&
           size <= kUserAddressLimit - address;
}
bool rangeEnd(std::uint64_t address, std::uint64_t size, std::uint64_t& end) {
    if (size == 0 || address >= kUserAddressLimit || size > kUserAddressLimit - address) return false;
    end = address + size;
    return true;
}
std::uint64_t pageDown(std::uint64_t value) { return value & ~(kPageSize - 1ULL); }
bool pageUp(std::uint64_t value, std::uint64_t& result) {
    if (value > UINT64_MAX - (kPageSize - 1ULL)) return false;
    result = (value + kPageSize - 1ULL) & ~(kPageSize - 1ULL);
    return true;
}
}

VirtualAddressSpace::VirtualAddressSpace(GuestMemory& backing) : backing_(backing) {}

bool VirtualAddressSpace::map(std::uint64_t address, std::uint64_t size, std::uint8_t permissions) {
    if (!alignedRange(address, size) || permissions == 0 || (permissions & ~7U) != 0) return false;
    const std::uint64_t count = size / kPageSize;
    if (count > (backing_.budget() - std::min(backing_.budget(), backing_.committed())) / kPageSize)
        return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize) {
        if (pages_.find((address + offset) / kPageSize) != pages_.end()) return false;
    }
    const std::uint8_t zero = 0;
    std::vector<std::uint64_t> inserted;
    inserted.reserve(static_cast<std::size_t>(count));
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize) {
        const std::uint64_t backingAddress = nextBackingPage_ * kPageSize;
        if (!backing_.write(backingAddress, &zero, 1)) {
            for (const auto page : inserted) pages_.erase(page);
            return false;
        }
        const std::uint64_t virtualPage = (address + offset) / kPageSize;
        pages_.emplace(virtualPage, Mapping{backingAddress, permissions});
        inserted.push_back(virtualPage);
        ++nextBackingPage_;
    }
    return true;
}

bool VirtualAddressSpace::unmap(std::uint64_t address, std::uint64_t size) {
    if (!alignedRange(address, size)) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        if (pages_.find((address + offset) / kPageSize) == pages_.end()) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        pages_.erase((address + offset) / kPageSize);
    return true;
}

bool VirtualAddressSpace::protect(std::uint64_t address, std::uint64_t size, std::uint8_t permissions) {
    if (!alignedRange(address, size) || permissions == 0 || (permissions & ~7U) != 0) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        if (pages_.find((address + offset) / kPageSize) == pages_.end()) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        pages_[(address + offset) / kPageSize].permissions = permissions;
    return true;
}

bool VirtualAddressSpace::transfer(std::uint64_t address, void* buffer, std::size_t length,
                                   std::uint8_t requiredPermission, bool writeAccess) const {
    if (length == 0) return true;
    std::uint64_t end = 0;
    if (buffer == nullptr || !rangeEnd(address, static_cast<std::uint64_t>(length), end)) return false;
    auto* bytes = static_cast<std::uint8_t*>(buffer);
    std::uint64_t cursor = address;
    std::size_t remaining = length;
    while (remaining > 0) {
        const auto pageIt = pages_.find(cursor / kPageSize);
        if (pageIt == pages_.end() || (pageIt->second.permissions & requiredPermission) == 0) return false;
        const std::size_t pageOffset = static_cast<std::size_t>(cursor % kPageSize);
        const std::size_t amount = std::min(remaining, static_cast<std::size_t>(kPageSize) - pageOffset);
        const std::uint64_t backingAddress = pageIt->second.backingAddress + pageOffset;
        const bool ok = writeAccess
            ? backing_.write(backingAddress, bytes, amount)
            : backing_.read(backingAddress, bytes, amount);
        if (!ok) return false;
        bytes += amount;
        cursor += amount;
        remaining -= amount;
    }
    (void)end;
    return true;
}

bool VirtualAddressSpace::read(std::uint64_t address, void* destination, std::size_t length) const {
    return transfer(address, destination, length, MemRead, false);
}
bool VirtualAddressSpace::write(std::uint64_t address, const void* source, std::size_t length) {
    return transfer(address, const_cast<void*>(source), length, MemWrite, true);
}
bool VirtualAddressSpace::fetch(std::uint64_t address, void* destination, std::size_t length) const {
    return transfer(address, destination, length, MemExecute, false);
}
bool VirtualAddressSpace::isMapped(std::uint64_t address) const {
    return pages_.find(address / kPageSize) != pages_.end();
}
bool VirtualAddressSpace::hasPermission(std::uint64_t address, std::uint8_t permission) const {
    const auto it = pages_.find(address / kPageSize);
    return it != pages_.end() && (it->second.permissions & permission) == permission;
}
std::size_t VirtualAddressSpace::mappedPageCount() const { return pages_.size(); }

ElfLoadResult Elf64Loader::loadStaticExecutable(VirtualAddressSpace& as,
                                                const std::uint8_t* data,
                                                std::size_t size) {
    ElfLoadResult result;
    if (data == nullptr || size < sizeof(Elf64_Ehdr) || size > kMaxElfBytes) {
        result.message = "ELF file size is invalid";
        return result;
    }
    Elf64_Ehdr header{};
    std::memcpy(&header, data, sizeof(header));
    if (std::memcmp(header.e_ident, ELFMAG, SELFMAG) != 0 ||
        header.e_ident[EI_CLASS] != ELFCLASS64 ||
        header.e_ident[EI_DATA] != ELFDATA2LSB ||
        header.e_ident[EI_VERSION] != EV_CURRENT ||
        header.e_machine != EM_X86_64 || header.e_version != EV_CURRENT) {
        result.message = "Expected a little-endian x86-64 ELF64 executable";
        return result;
    }
    if (header.e_type != ET_EXEC) {
        result.message = "Only static ET_EXEC images are supported in this loader milestone";
        return result;
    }
    if (header.e_ehsize != sizeof(Elf64_Ehdr) ||
        header.e_phentsize != sizeof(Elf64_Phdr) ||
        header.e_phnum == 0 || header.e_phnum > 128) {
        result.message = "ELF program-header layout is unsupported";
        return result;
    }
    const std::uint64_t phBytes = static_cast<std::uint64_t>(header.e_phnum) * sizeof(Elf64_Phdr);
    if (header.e_phoff > size || phBytes > size - header.e_phoff) {
        result.message = "ELF program-header table is outside the file";
        return result;
    }

    std::map<std::uint64_t, std::uint8_t> pagePermissions;
    std::uint64_t totalMemory = 0;
    for (std::uint16_t i = 0; i < header.e_phnum; ++i) {
        Elf64_Phdr ph{};
        std::memcpy(&ph, data + header.e_phoff + static_cast<std::uint64_t>(i) * sizeof(ph), sizeof(ph));
        if (ph.p_type == PT_INTERP) {
            result.message = "Dynamic ELF interpreters are not supported yet";
            return result;
        }
        if (ph.p_type != PT_LOAD) continue;
        if (ph.p_filesz > ph.p_memsz || ph.p_offset > size || ph.p_filesz > size - ph.p_offset ||
            ph.p_memsz == 0 || ph.p_memsz > kMaxLoadedBytes - totalMemory) {
            result.message = "ELF load segment has invalid bounds";
            return result;
        }
        if (ph.p_align > 1 && ((ph.p_align & (ph.p_align - 1)) != 0 ||
            (ph.p_vaddr % ph.p_align) != (ph.p_offset % ph.p_align))) {
            result.message = "ELF segment alignment is invalid";
            return result;
        }
        std::uint64_t segmentEnd = 0;
        if (!rangeEnd(ph.p_vaddr, ph.p_memsz, segmentEnd)) {
            result.message = "ELF segment uses a non-user or overflowing virtual address";
            return result;
        }
        const std::uint64_t firstPage = pageDown(ph.p_vaddr);
        std::uint64_t lastPage = 0;
        if (!pageUp(segmentEnd, lastPage)) {
            result.message = "ELF segment page alignment overflow";
            return result;
        }
        for (std::uint64_t page = firstPage; page < lastPage; page += kPageSize) {
            if (!as.isMapped(page) && !as.map(page, kPageSize, MemRead | MemWrite)) {
                result.message = "Could not allocate ELF virtual pages";
                return result;
            }
            std::uint8_t permissions = 0;
            if ((ph.p_flags & PF_R) != 0) permissions |= MemRead;
            if ((ph.p_flags & PF_W) != 0) permissions |= MemWrite;
            if ((ph.p_flags & PF_X) != 0) permissions |= MemExecute;
            pagePermissions[page] |= permissions;
        }
        if (ph.p_filesz > 0 && !as.write(ph.p_vaddr, data + ph.p_offset, static_cast<std::size_t>(ph.p_filesz))) {
            result.message = "Could not copy ELF segment bytes";
            return result;
        }
        std::vector<std::uint8_t> zeros(4096, 0);
        std::uint64_t bss = ph.p_memsz - ph.p_filesz;
        std::uint64_t bssAddress = ph.p_vaddr + ph.p_filesz;
        while (bss > 0) {
            const std::size_t amount = static_cast<std::size_t>(std::min<std::uint64_t>(bss, zeros.size()));
            if (!as.write(bssAddress, zeros.data(), amount)) {
                result.message = "Could not initialize ELF zero-filled segment tail";
                return result;
            }
            bssAddress += amount;
            bss -= amount;
        }
        totalMemory += ph.p_memsz;
        ++result.loadedSegments;
    }
    if (result.loadedSegments == 0) {
        result.message = "ELF contains no loadable segments";
        return result;
    }

    for (const auto& page : pagePermissions) {
        if (page.second == 0 || !as.protect(page.first, kPageSize, page.second)) {
            result.message = "Could not apply ELF segment memory permissions";
            return result;
        }
    }
    if (!as.hasPermission(header.e_entry, MemExecute)) {
        result.message = "ELF entry point is not inside an executable segment";
        return result;
    }

    const std::uint64_t stackTop = kDefaultStackTop;
    const std::uint64_t stackBase = stackTop - kStackSize;
    if (!as.map(stackBase, kStackSize, MemRead | MemWrite)) {
        result.message = "Could not allocate initial user stack";
        return result;
    }
    result.success = true;
    result.entryPoint = header.e_entry;
    result.stackPointer = stackTop;
    result.imageBase = 0;
    result.message = "Static x86-64 ELF loaded with segment permissions and an initial stack";
    return result;
}

bool runVirtualMemorySelfTest(std::string& message) {
    GuestMemory backing(2ULL * 1024ULL * 1024ULL);
    VirtualAddressSpace as(backing);
    const std::uint64_t base = 0x400000;
    const std::uint8_t bytes[] = {0x90, 0xF4, 0x42};
    std::uint8_t output[2]{};
    if (!as.map(base, kPageSize, MemRead | MemWrite) ||
        !as.write(base, bytes, sizeof(bytes)) ||
        !as.protect(base, kPageSize, MemRead | MemExecute) ||
        !as.fetch(base, output, sizeof(output)) ||
        std::memcmp(output, bytes, sizeof(output)) != 0 ||
        as.write(base, bytes, 1) ||
        as.fetch(base + kPageSize, output, 1) ||
        !as.unmap(base, kPageSize) || as.isMapped(base)) {
        message = "Virtual memory mapping/protection/fault test failed";
        return false;
    }
    message = "Virtual memory map, read/execute permissions, write protection and unmap tests passed";
    return true;
}

bool runElfLoaderSelfTest(std::string& message) {
    std::vector<std::uint8_t> file(0x1002, 0);
    Elf64_Ehdr header{};
    std::memcpy(header.e_ident, ELFMAG, SELFMAG);
    header.e_ident[EI_CLASS] = ELFCLASS64;
    header.e_ident[EI_DATA] = ELFDATA2LSB;
    header.e_ident[EI_VERSION] = EV_CURRENT;
    header.e_type = ET_EXEC;
    header.e_machine = EM_X86_64;
    header.e_version = EV_CURRENT;
    header.e_entry = 0x400000;
    header.e_phoff = sizeof(Elf64_Ehdr);
    header.e_ehsize = sizeof(Elf64_Ehdr);
    header.e_phentsize = sizeof(Elf64_Phdr);
    header.e_phnum = 1;
    Elf64_Phdr program{};
    program.p_type = PT_LOAD;
    program.p_flags = PF_R | PF_X;
    program.p_offset = 0x1000;
    program.p_vaddr = 0x400000;
    program.p_filesz = 2;
    program.p_memsz = 32;
    program.p_align = kPageSize;
    std::memcpy(file.data(), &header, sizeof(header));
    std::memcpy(file.data() + header.e_phoff, &program, sizeof(program));
    file[0x1000] = 0x90;
    file[0x1001] = 0xF4;

    GuestMemory backing;
    VirtualAddressSpace as(backing);
    const auto loaded = Elf64Loader::loadStaticExecutable(as, file.data(), file.size());
    std::uint8_t instructions[2]{};
    std::uint8_t bss[30]{};
    if (!loaded.success || loaded.entryPoint != 0x400000 ||
        !as.fetch(loaded.entryPoint, instructions, sizeof(instructions)) ||
        instructions[0] != 0x90 || instructions[1] != 0xF4 ||
        !as.read(loaded.entryPoint + 2, bss, sizeof(bss)) ||
        as.write(loaded.entryPoint, instructions, 1) ||
        !as.hasPermission(loaded.entryPoint, MemExecute) ||
        as.hasPermission(loaded.entryPoint, MemWrite)) {
        message = loaded.message.empty() ? "ELF loader self-test failed" : loaded.message;
        return false;
    }
    message = "Static ELF64 segment, BSS zero-fill, executable/read-only permissions and stack tests passed";
    return true;
}

} // namespace pshere
