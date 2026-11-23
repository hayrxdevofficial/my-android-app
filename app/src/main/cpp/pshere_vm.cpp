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


namespace {
constexpr std::uint64_t kPtePresent = 1ULL;
constexpr std::uint64_t kPteWrite = 1ULL << 1;
constexpr std::uint64_t kPteUser = 1ULL << 2;
constexpr std::uint64_t kPteNoExecute = 1ULL << 63;
constexpr std::uint64_t kPteAddressMask = 0x000FFFFFFFFFF000ULL;
constexpr std::uint64_t kCanonicalUserLimit = 0x0000800000000000ULL;
constexpr std::uint64_t kTableFlags = kPtePresent | kPteWrite | kPteUser;
}

X64PageTables::X64PageTables() : cr3_(allocateTable()) {}
std::uint64_t X64PageTables::cr3() const { return cr3_; }
std::uint64_t X64PageTables::allocateTable() {
    const std::uint64_t address = nextTablePhysical_;
    nextTablePhysical_ += kPageSize;
    tables_.emplace(address, Table{});
    return address;
}
X64PageTables::Table* X64PageTables::tableAt(std::uint64_t address) {
    const auto it = tables_.find(address & kPteAddressMask);
    return it == tables_.end() ? nullptr : &it->second;
}
const X64PageTables::Table* X64PageTables::tableAt(std::uint64_t address) const {
    const auto it = tables_.find(address & kPteAddressMask);
    return it == tables_.end() ? nullptr : &it->second;
}
bool X64PageTables::map(std::uint64_t va, std::uint64_t pa, std::uint8_t permissions, bool user) {
    if (va >= kCanonicalUserLimit || (va & (kPageSize - 1)) ||
        (pa & (kPageSize - 1)) || (pa & ~kPteAddressMask) ||
        permissions == 0 || (permissions & ~7U)) return false;
    const unsigned indexes[4] = {
        static_cast<unsigned>((va >> 39) & 0x1FF),
        static_cast<unsigned>((va >> 30) & 0x1FF),
        static_cast<unsigned>((va >> 21) & 0x1FF),
        static_cast<unsigned>((va >> 12) & 0x1FF)
    };
    std::uint64_t tablePhysical = cr3_;
    for (int level = 0; level < 3; ++level) {
        Table* table = tableAt(tablePhysical);
        if (!table) return false;
        std::uint64_t& entry = (*table)[indexes[level]];
        if ((entry & kPtePresent) == 0) entry = allocateTable() | kTableFlags;
        tablePhysical = entry & kPteAddressMask;
    }
    Table* leafTable = tableAt(tablePhysical);
    if (!leafTable) return false;
    std::uint64_t& leaf = (*leafTable)[indexes[3]];
    if (leaf & kPtePresent) return false;
    leaf = pa | kPtePresent;
    if (permissions & MemWrite) leaf |= kPteWrite;
    if (user) leaf |= kPteUser;
    if ((permissions & MemExecute) == 0) leaf |= kPteNoExecute;
    return true;
}
bool X64PageTables::unmap(std::uint64_t va) {
    if (va >= kCanonicalUserLimit || (va & (kPageSize - 1))) return false;
    const unsigned indexes[4] = {
        static_cast<unsigned>((va >> 39) & 0x1FF),
        static_cast<unsigned>((va >> 30) & 0x1FF),
        static_cast<unsigned>((va >> 21) & 0x1FF),
        static_cast<unsigned>((va >> 12) & 0x1FF)
    };
    std::uint64_t physical = cr3_;
    for (int level = 0; level < 3; ++level) {
        const Table* table = tableAt(physical);
        if (!table || (((*table)[indexes[level]] & kPtePresent) == 0)) return false;
        physical = (*table)[indexes[level]] & kPteAddressMask;
    }
    Table* leafTable = tableAt(physical);
    if (!leafTable || (((*leafTable)[indexes[3]] & kPtePresent) == 0)) return false;
    (*leafTable)[indexes[3]] = 0;
    return true;
}
bool X64PageTables::protect(std::uint64_t va, std::uint8_t permissions, bool user) {
    if (permissions == 0 || (permissions & ~7U) || va >= kCanonicalUserLimit ||
        (va & (kPageSize - 1))) return false;
    const unsigned indexes[4] = {
        static_cast<unsigned>((va >> 39) & 0x1FF),
        static_cast<unsigned>((va >> 30) & 0x1FF),
        static_cast<unsigned>((va >> 21) & 0x1FF),
        static_cast<unsigned>((va >> 12) & 0x1FF)
    };
    std::uint64_t physical = cr3_;
    for (int level = 0; level < 3; ++level) {
        const Table* table = tableAt(physical);
        if (!table || (((*table)[indexes[level]] & kPtePresent) == 0)) return false;
        physical = (*table)[indexes[level]] & kPteAddressMask;
    }
    Table* leafTable = tableAt(physical);
    if (!leafTable) return false;
    std::uint64_t& leaf = (*leafTable)[indexes[3]];
    if ((leaf & kPtePresent) == 0) return false;
    leaf &= ~(kPteWrite | kPteUser | kPteNoExecute);
    if (permissions & MemWrite) leaf |= kPteWrite;
    if (user) leaf |= kPteUser;
    if ((permissions & MemExecute) == 0) leaf |= kPteNoExecute;
    return true;
}
bool X64PageTables::translate(std::uint64_t va, std::uint8_t access,
                              std::uint64_t& pa, bool user) const {
    if (va >= kCanonicalUserLimit || (access & ~7U) || access == 0) return false;
    const unsigned indexes[4] = {
        static_cast<unsigned>((va >> 39) & 0x1FF),
        static_cast<unsigned>((va >> 30) & 0x1FF),
        static_cast<unsigned>((va >> 21) & 0x1FF),
        static_cast<unsigned>((va >> 12) & 0x1FF)
    };
    std::uint64_t physical = cr3_;
    bool writable = true;
    bool userAllowed = true;
    bool executable = true;
    for (int level = 0; level < 4; ++level) {
        const Table* table = tableAt(physical);
        if (!table) return false;
        const std::uint64_t entry = (*table)[indexes[level]];
        if ((entry & kPtePresent) == 0) return false;
        writable = writable && ((entry & kPteWrite) != 0);
        userAllowed = userAllowed && ((entry & kPteUser) != 0);
        executable = executable && ((entry & kPteNoExecute) == 0);
        if (level == 3) {
            if ((access & MemWrite) && !writable) return false;
            if ((access & MemExecute) && !executable) return false;
            if (user && !userAllowed) return false;
            pa = (entry & kPteAddressMask) | (va & (kPageSize - 1));
            return true;
        }
        physical = entry & kPteAddressMask;
    }
    return false;
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
        if (!backing_.write(backingAddress, &zero, 1) ||
            !pageTables_.map(address + offset, backingAddress, permissions)) {
            for (const auto page : inserted) {
                const auto it = pages_.find(page);
                if (it != pages_.end()) { pageTables_.unmap(page * kPageSize); backing_.releasePage(it->second.backingAddress); pages_.erase(it); }
            }
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
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize) {
        const auto it = pages_.find((address + offset) / kPageSize);
        if (it != pages_.end()) {
            pageTables_.unmap(address + offset);
            backing_.releasePage(it->second.backingAddress);
            pages_.erase(it);
        }
    }
    return true;
}

bool VirtualAddressSpace::protect(std::uint64_t address, std::uint64_t size, std::uint8_t permissions) {
    if (!alignedRange(address, size) || permissions == 0 || (permissions & ~7U) != 0) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        if (pages_.find((address + offset) / kPageSize) == pages_.end()) return false;
    for (std::uint64_t offset = 0; offset < size; offset += kPageSize)
        if (!pageTables_.protect(address + offset, permissions)) return false;
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
        std::uint64_t translated = 0;
        if (!pageTables_.translate(cursor, requiredPermission, translated) ||
            translated != pageIt->second.backingAddress + pageOffset) return false;
        const std::uint64_t backingAddress = translated;
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
std::uint64_t VirtualAddressSpace::cr3() const { return pageTables_.cr3(); }

ElfLoadResult Elf64Loader::loadStaticExecutable(VirtualAddressSpace& as,
                                                const std::uint8_t* data,
                                                std::size_t size) {
    ElfLoadResult result;
    if (data == nullptr || size < sizeof(Elf64_Ehdr) || size > kMaxElfBytes) {
        result.message = "ELF file size is invalid"; return result;
    }
    Elf64_Ehdr header{};
    std::memcpy(&header, data, sizeof(header));
    if (std::memcmp(header.e_ident, ELFMAG, SELFMAG) != 0 ||
        header.e_ident[EI_CLASS] != ELFCLASS64 || header.e_ident[EI_DATA] != ELFDATA2LSB ||
        header.e_ident[EI_VERSION] != EV_CURRENT || header.e_machine != EM_X86_64 ||
        header.e_version != EV_CURRENT) {
        result.message = "Expected a little-endian x86-64 ELF64 executable"; return result;
    }
    if (header.e_type != ET_EXEC && header.e_type != ET_DYN) {
        result.message = "Only x86-64 ET_EXEC and ET_DYN images are supported"; return result;
    }
    if (header.e_ehsize != sizeof(Elf64_Ehdr) || header.e_phentsize != sizeof(Elf64_Phdr) ||
        header.e_phnum == 0 || header.e_phnum > 128) {
        result.message = "ELF program-header layout is unsupported"; return result;
    }
    const std::uint64_t phBytes = static_cast<std::uint64_t>(header.e_phnum) * sizeof(Elf64_Phdr);
    if (header.e_phoff > size || phBytes > size - header.e_phoff) {
        result.message = "ELF program-header table is outside the file"; return result;
    }

    const std::uint64_t loadBias = header.e_type == ET_DYN ? 0x40000000ULL : 0ULL;
    std::map<std::uint64_t, std::uint8_t> pagePermissions;
    std::uint64_t totalMemory = 0, dynamicAddress = 0, dynamicSize = 0;
    for (std::uint16_t i = 0; i < header.e_phnum; ++i) {
        Elf64_Phdr ph{};
        std::memcpy(&ph, data + header.e_phoff + static_cast<std::uint64_t>(i) * sizeof(ph), sizeof(ph));
        if (ph.p_type == PT_INTERP) {
            result.message = "PT_INTERP is unsupported: no guest dynamic linker/runtime is available"; return result;
        }
        if (ph.p_type == PT_DYNAMIC) {
            if (ph.p_memsz > kMaxLoadedBytes || ph.p_vaddr > UINT64_MAX - loadBias) {
                result.message = "ELF dynamic section bounds are invalid"; return result;
            }
            dynamicAddress = ph.p_vaddr + loadBias;
            dynamicSize = ph.p_memsz;
        }
        if (ph.p_type != PT_LOAD) continue;
        if (ph.p_filesz > ph.p_memsz || ph.p_offset > size || ph.p_filesz > size - ph.p_offset ||
            ph.p_memsz == 0 || ph.p_memsz > kMaxLoadedBytes - totalMemory ||
            ph.p_vaddr > UINT64_MAX - loadBias) {
            result.message = "ELF load segment has invalid bounds"; return result;
        }
        if (ph.p_align > 1 && ((ph.p_align & (ph.p_align - 1)) != 0 ||
            (ph.p_vaddr % ph.p_align) != (ph.p_offset % ph.p_align))) {
            result.message = "ELF segment alignment is invalid"; return result;
        }
        const std::uint64_t segmentAddress = ph.p_vaddr + loadBias;
        std::uint64_t segmentEnd = 0;
        if (!rangeEnd(segmentAddress, ph.p_memsz, segmentEnd)) {
            result.message = "ELF segment uses a non-user or overflowing virtual address"; return result;
        }
        const std::uint64_t firstPage = pageDown(segmentAddress);
        std::uint64_t lastPage = 0;
        if (!pageUp(segmentEnd, lastPage)) {
            result.message = "ELF segment page alignment overflow"; return result;
        }
        for (std::uint64_t page = firstPage; page < lastPage; page += kPageSize) {
            if (!as.isMapped(page) && !as.map(page, kPageSize, MemRead | MemWrite)) {
                result.message = "Could not allocate ELF virtual pages"; return result;
            }
            std::uint8_t permissions = 0;
            if (ph.p_flags & PF_R) permissions |= MemRead;
            if (ph.p_flags & PF_W) permissions |= MemWrite;
            if (ph.p_flags & PF_X) permissions |= MemExecute;
            pagePermissions[page] |= permissions;
            if ((pagePermissions[page] & (MemWrite | MemExecute)) == (MemWrite | MemExecute)) {
                result.message = "ELF segment layout would create a writable-executable page"; return result;
            }
        }
        if (ph.p_filesz && !as.write(segmentAddress, data + ph.p_offset, static_cast<std::size_t>(ph.p_filesz))) {
            result.message = "Could not copy ELF segment bytes"; return result;
        }
        std::vector<std::uint8_t> zeros(4096, 0);
        std::uint64_t bss = ph.p_memsz - ph.p_filesz;
        std::uint64_t bssAddress = segmentAddress + ph.p_filesz;
        while (bss) {
            const std::size_t amount = static_cast<std::size_t>(std::min<std::uint64_t>(bss, zeros.size()));
            if (!as.write(bssAddress, zeros.data(), amount)) {
                result.message = "Could not initialize ELF zero-filled segment tail"; return result;
            }
            bssAddress += amount; bss -= amount;
        }
        totalMemory += ph.p_memsz;
        ++result.loadedSegments;
    }
    if (!result.loadedSegments) {
        result.message = "ELF contains no loadable segments"; return result;
    }

    // A deliberately bounded in-process relocator: RELA relative relocations and
    // locally-defined x86-64 symbols only. External DT_NEEDED libraries are rejected.
    if (dynamicAddress && dynamicSize) {
        if (dynamicSize > 1024 * sizeof(Elf64_Dyn) || dynamicSize % sizeof(Elf64_Dyn)) {
            result.message = "ELF dynamic table size is invalid"; return result;
        }
        std::uint64_t relaPointer = 0, relaSize = 0, relaEntrySize = sizeof(Elf64_Rela);
        std::uint64_t relSize = 0, pltRelSize = 0;
        std::uint64_t symtabPointer = 0, symEntrySize = sizeof(Elf64_Sym);
        bool hasNeeded = false;
        for (std::uint64_t offset = 0; offset < dynamicSize; offset += sizeof(Elf64_Dyn)) {
            Elf64_Dyn dyn{};
            if (!as.read(dynamicAddress + offset, &dyn, sizeof(dyn))) {
                result.message = "Could not read ELF dynamic table"; return result;
            }
            if (dyn.d_tag == DT_NULL) break;
            switch (dyn.d_tag) {
                case DT_NEEDED: hasNeeded = true; break;
                case DT_RELA: relaPointer = dyn.d_un.d_ptr; break;
                case DT_RELASZ: relaSize = dyn.d_un.d_val; break;
                case DT_RELAENT: relaEntrySize = dyn.d_un.d_val; break;
                case DT_SYMTAB: symtabPointer = dyn.d_un.d_ptr; break;
                case DT_SYMENT: symEntrySize = dyn.d_un.d_val; break;
                case DT_RELSZ: relSize = dyn.d_un.d_val; break;
                case DT_PLTRELSZ: pltRelSize = dyn.d_un.d_val; break;
                case DT_REL:
                case DT_JMPREL:
                    break;
                default: break;
            }
        }
        if (relSize || pltRelSize) {
            result.message = "REL/PLT relocation tables are not supported; use RELA"; return result;
        }
        if (hasNeeded) {
            result.message = "ELF requires DT_NEEDED shared libraries; external dynamic linking is not implemented"; return result;
        }
        if (relaSize) {
            if (!relaPointer || relaEntrySize != sizeof(Elf64_Rela) ||
                relaSize % sizeof(Elf64_Rela) || relaSize > 16ULL * 1024ULL * 1024ULL) {
                result.message = "ELF RELA table metadata is invalid"; return result;
            }
            const std::uint64_t relaAddress = relaPointer + loadBias;
            for (std::uint64_t offset = 0; offset < relaSize; offset += sizeof(Elf64_Rela)) {
                Elf64_Rela rela{};
                if (!as.read(relaAddress + offset, &rela, sizeof(rela))) {
                    result.message = "ELF RELA table is outside mapped image"; return result;
                }
                const std::uint32_t type = ELF64_R_TYPE(rela.r_info);
                const std::uint32_t symbolIndex = ELF64_R_SYM(rela.r_info);
                std::uint64_t value = 0;
                if (type == R_X86_64_NONE) continue;
                if (type == R_X86_64_RELATIVE && symbolIndex == 0) {
                    value = loadBias + static_cast<std::uint64_t>(rela.r_addend);
                } else if (type == R_X86_64_64 || type == R_X86_64_GLOB_DAT ||
                           type == R_X86_64_JUMP_SLOT) {
                    if (!symtabPointer || symEntrySize != sizeof(Elf64_Sym) || symbolIndex > 1000000U) {
                        result.message = "ELF symbol relocation metadata is invalid"; return result;
                    }
                    Elf64_Sym symbol{};
                    const std::uint64_t symbolAddress = symtabPointer + loadBias +
                        static_cast<std::uint64_t>(symbolIndex) * sizeof(Elf64_Sym);
                    if (!as.read(symbolAddress, &symbol, sizeof(symbol)) || symbol.st_shndx == SHN_UNDEF) {
                        result.message = "ELF relocation references an unresolved external symbol"; return result;
                    }
                    value = loadBias + symbol.st_value;
                    if (type == R_X86_64_64) value += static_cast<std::uint64_t>(rela.r_addend);
                } else {
                    result.message = "Unsupported x86-64 ELF relocation type " + std::to_string(type); return result;
                }
                const std::uint64_t target = loadBias + rela.r_offset;
                if (!as.write(target, &value, sizeof(value))) {
                    result.message = "Could not apply ELF relocation to target page"; return result;
                }
            }
        }
    }

    for (const auto& page : pagePermissions) {
        if (!page.second || !as.protect(page.first, kPageSize, page.second)) {
            result.message = "Could not apply ELF segment memory permissions"; return result;
        }
    }
    const std::uint64_t entry = header.e_entry + loadBias;
    if (!as.hasPermission(entry, MemExecute)) {
        result.message = "ELF entry point is not inside an executable segment"; return result;
    }
    const std::uint64_t stackTop = kDefaultStackTop;
    const std::uint64_t stackBase = stackTop - kStackSize;
    if (!as.map(stackBase, kStackSize, MemRead | MemWrite)) {
        result.message = "Could not allocate initial user stack"; return result;
    }
    result.success = true;
    result.entryPoint = entry;
    result.stackPointer = stackTop;
    result.imageBase = loadBias;
    result.message = header.e_type == ET_DYN
        ? "ET_DYN image loaded with load bias and supported RELA relocations; external libraries are not linked"
        : "ET_EXEC image loaded with segment permissions and initial stack";
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
    CpuState guestCpu;
    guestCpu.rip = loaded.entryPoint;
    guestCpu.registers[RSP] = loaded.stackPointer;
    X64Interpreter interpreter(as);
    interpreter.step(guestCpu);
    interpreter.step(guestCpu);
    if (!guestCpu.halted || guestCpu.instructionsExecuted != 2) {
        message = "ELF entry point could not execute through protected virtual memory";
        return false;
    }
    message = "Static ELF64 segment, BSS zero-fill, R/W/X protection, initial stack and CPU entry execution tests passed";
    return true;
}

} // namespace pshere
