# PSHere — Android PS4 emulation research

Experimental Android frontend and native execution-core foundation. This repository is not yet a working PS4 emulator and does not currently boot commercial games.

## Version 0.4.0 — native core foundation

- Kotlin Android application
- C++17 native library built with Android NDK and CMake
- JNI bridge from the Android UI to the PSHere native core
- Sparse, page-based guest memory with a configurable 6 GiB ceiling (pages are committed only when written)
- Initial x86-64 interpreter subset: `MOV r64, imm64`, `NOP`, and `HLT`
- Built-in CPU smoke test: executes `MOV RAX, 42; NOP; HLT` and checks the resulting state
- Android build targets: `arm64-v8a` and `x86_64`
- Keyboard and USB/Bluetooth Android gamepad detection
- Android default-network monitoring (Wi-Fi, mobile data, Ethernet)
- Firmware downloads use Android DownloadManager and the tablet's active network route
- Local file selection through Android Storage Access Framework
- PS4 profile target: 70 GB virtual storage and 6 GB guest-memory budget

## PSHere native core

The native core is loaded by the Android app as `libpshere.so`. The UI exposes core diagnostics and a self-test button. The current interpreter is deliberately small and is only a proof that guest memory, CPU state, instruction fetch/decode, and JNI integration work together.

The memory manager uses 4 KiB pages and allocates them on demand. The 6 GiB value is a guest-memory budget, not a request to reserve 6 GiB from Android at startup. Actual device memory pressure and Android process limits still apply.

### Current instruction subset

| Instruction | Current behavior |
|---|---|
| `48 B8+r imm64` | Load a 64-bit immediate into a general-purpose register |
| `90` | NOP |
| `F4` | Halt the test CPU |

This is not a complete x86-64 implementation. It has no PS4 syscall ABI, exception handling, threads, SIMD, virtual memory permissions, executable loader, or kernel services.

## Tablet Wi-Fi networking

The app observes Android's default network. When the tablet is connected to Wi-Fi, Android routes app downloads and network requests over that Wi-Fi connection automatically. This is not yet a PS4 virtual network adapter: guest sockets, PSN protocols, multiplayer and NAT behavior are not implemented.

## Firmware

Sony supplies PS4 system software as PUP update/reinstallation packages, not a bootable PS4 ISO. A PUP is intended for updating or reinstalling software on a physical PS4; it is not a ready-to-boot emulator image. Use the official Sony support page linked in the app if a direct package URL changes.

Official source: https://www.playstation.com/en-gb/support/hardware/ps4/system-software/

## Resource profile

The 70 GB storage value remains a target only: a virtual disk backend has not yet been implemented. The 6 GB value is the guest-memory budget for the native memory manager; pages are allocated on demand, not reserved in full.

## What is still required before games can boot

1. A complete and tested x86-64 CPU implementation, including SIMD and correct flags/exceptions.
2. PS4 executable/SELF handling and a lawful firmware/system-module loading path.
3. PS4 kernel and system-library compatibility (syscalls, threads, synchronization, filesystems).
4. GPU command translation to Vulkan, plus shader translation and synchronization.
5. Audio, input mapping, timers, networking and virtual storage.
6. Compatibility tests and performance profiling on each Android GPU/SoC family.

The current Android ARM64 host also needs a fast x86-64 guest translation strategy. A small interpreter smoke test is not evidence that PS4 games can run.

## Build

Open in Android Studio with JDK 17 and Android SDK 35, with Android NDK 27.2.12479018 and CMake 3.22.1 installed. GitHub Actions builds a debug APK for `arm64-v8a` and `x86_64` and uploads the `pshere-android-debug-apk` artifact.
