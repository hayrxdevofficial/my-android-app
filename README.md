# PSHere — Android PS4 emulation research

PSHere is an experimental Android frontend and native x86-64 execution-core prototype. It is **not a working PS4 emulator** and does not boot commercial PS4 games.

## Version 1.0.0 (first test build)

- Android application with a C++17 NDK native library and JNI bridge.
- Android launcher label: `Hayrulla004004_Dev.ps4emulator`.
- Sparse guest memory with a configurable 6 GiB budget; memory is committed on demand.
- x86-64 general-purpose registers RAX–R15, RIP and selected RFLAGS bits.
- Basic instruction subset: MOV, ADD, SUB, XOR, CMP, TEST, PUSH, POP, CALL, RET, short JMP/Jcc, NOP and HLT.
- ModRM/SIB effective-address decoding for common base, index, scale and displacement forms, including `[RAX]`, `[RBX+8]` and `[RSP-16]`.
- 4 KiB virtual pages backed by sparse guest storage.
- Four-level software x86-64 page-table walk (PML4 → PDPT → PD → PT), CR3 root value and page permission checks.
- Per-page read/write/execute protection and protected instruction fetch.
- ELF64 `ET_EXEC` and `ET_DYN` PT_LOAD loading, BSS zero-fill, entry-point validation and an initial 8 MiB stack.
- ET_DYN fixed load bias and a limited RELA relocator for `R_X86_64_RELATIVE` and selected locally-defined symbol relocations.
- Android file picker and bounded execution of a loaded ELF entry point (500,000 instructions per UI run).
- Official Sony PS4 PUP download through Android DownloadManager, with live byte-based percentage/progress display.
- Automatic copy/import of the completed PUP into the app-private `files/firmware` directory.
- Self-tests for CPU arithmetic/stack, ModRM/SIB memory addressing, virtual memory, page-table translation and synthetic ELF loading.

## Important limitations

The page tables are a software model, not a complete hardware MMU. TLBs, PCID, privilege transitions, full page-fault semantics, huge pages, copy-on-write and memory-mapped I/O are not implemented.

The ELF loader is not a complete dynamic linker. It rejects `PT_INTERP` and external `DT_NEEDED` libraries; REL/PLT relocation tables, TLS, auxiliary vectors and a full process startup ABI are not supported. The supported local RELA subset does not make arbitrary Linux binaries runnable.

The x86-64 interpreter remains a small subset. SIMD, many integer instructions, complete flags/exceptions, segment bases and full instruction decoding are missing. ELF execution stops on HLT, unsupported instructions, memory/permission faults or the instruction budget.

PS4 games still require substantially more work: PS4 SELF handling, kernel and system-library compatibility, syscalls, threads, GPU/Vulkan command translation, shader translation, audio, filesystem, timers and a much broader CPU implementation. This project does not decrypt or install Sony firmware as a running PS4 operating system, and does not launch PS4 titles. The PUP workflow only downloads and imports the package into app storage; it is not a firmware installer or emulator boot path.

## Memory profile

The 6 GiB value is a guest-memory ceiling, not memory reserved from Android at startup. The 70 GB storage value is still a target profile; a persistent virtual disk backend is not implemented.

## Networking and input

The app detects Android keyboard/gamepad devices and observes Android's active network. Android routes app downloads over the active Wi-Fi/mobile/Ethernet connection. This is not a PS4 guest network adapter, PSN implementation or multiplayer stack.

## Build

Open the project in Android Studio with JDK 17, Android SDK 35, Android NDK and CMake 3.22.1. GitHub Actions builds debug APKs for `arm64-v8a` and `x86_64`.

## Identity note

`Hayrulla004004_Dev.ps4emulator` is the Android launcher label. It does not change the developer account name or store listing identity in Google Play.
