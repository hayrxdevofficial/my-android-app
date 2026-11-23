#include <jni.h>

#include "pshere_core.h"
#include "pshere_vm.h"

#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <vector>

namespace {
std::mutex gElfRuntimeMutex;
std::unique_ptr<pshere::GuestMemory> gLoadedGuestMemory;
std::unique_ptr<pshere::VirtualAddressSpace> gLoadedAddressSpace;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_hayrx_ps4emu_MainActivity_nativeCoreInfo(JNIEnv* env, jobject) {
#if defined(__aarch64__)
    constexpr const char* architecture = "ARM64 host";
#elif defined(__x86_64__)
    constexpr const char* architecture = "x86-64 host";
#else
    constexpr const char* architecture = "other Android ABI";
#endif
    std::ostringstream output;
    output << "PSHere native core loaded\n"
           << "Host architecture: " << architecture << "\n"
           << "Guest target: x86-64 (experimental subset)\nRegisters: RAX-R15, RIP, RFLAGS\nStack: 64-bit PUSH/POP/CALL/RET\nALU: MOV, ADD, SUB, XOR, CMP, TEST\nControl flow: JMP, JE/JZ, JNE/JNZ\n"
           << "Guest RAM budget: 6 GiB, allocated on demand\n"
           << "Virtual memory: page mapping + R/W/X permissions + protected instruction fetch\n"
           << "ELF: static little-endian x86-64 ET_EXEC loader + zero-filled BSS + initial stack\n"
           << "Implemented: sparse guest pages, MOV, ADD, SUB, XOR, CMP, TEST, PUSH, POP, CALL, RET, JMP, Jcc, NOP, HLT\n"
           << "Not implemented: PS4 kernel, SELF decryption, GPU, audio, game boot";
    return env->NewStringUTF(output.str().c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_hayrx_ps4emu_MainActivity_nativeRunSelfTest(JNIEnv* env, jobject) {
    const auto result = pshere::runSelfTest();
    std::string vmMessage;
    std::string elfMessage;
    const bool vmPassed = pshere::runVirtualMemorySelfTest(vmMessage);
    const bool elfPassed = pshere::runElfLoaderSelfTest(elfMessage);
    std::ostringstream output;
    output << (result.passed ? "PASS" : "FAIL") << ": " << result.message
           << "\nRAX = " << result.rax
           << "\nInstructions = " << result.instructions
           << "\n" << (vmPassed ? "PASS" : "FAIL") << ": " << vmMessage
           << "\n" << (elfPassed ? "PASS" : "FAIL") << ": " << elfMessage;
    return env->NewStringUTF(output.str().c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_hayrx_ps4emu_MainActivity_nativeLoadElf(JNIEnv* env, jobject, jbyteArray input) {
    if (input == nullptr) return env->NewStringUTF("ELF load failed: no file data");
    const jsize length = env->GetArrayLength(input);
    if (length <= 0 || static_cast<std::size_t>(length) > 128ULL * 1024ULL * 1024ULL)
        return env->NewStringUTF("ELF load failed: file must be between 1 byte and 128 MiB");

    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
    env->GetByteArrayRegion(input, 0, length, reinterpret_cast<jbyte*>(bytes.data()));
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return env->NewStringUTF("ELF load failed while copying file data from Android");
    }

    auto memory = std::make_unique<pshere::GuestMemory>();
    auto addressSpace = std::make_unique<pshere::VirtualAddressSpace>(*memory);
    const auto loaded = pshere::Elf64Loader::loadStaticExecutable(
        *addressSpace, bytes.data(), bytes.size());
    std::ostringstream output;
    if (!loaded.success) {
        output << "ELF rejected: " << loaded.message;
        return env->NewStringUTF(output.str().c_str());
    }

    {
        std::lock_guard<std::mutex> lock(gElfRuntimeMutex);
        gLoadedGuestMemory = std::move(memory);
        gLoadedAddressSpace = std::move(addressSpace);
    }
    output << "ELF loaded into PSHere virtual memory"
           << "\nEntry point: 0x" << std::hex << loaded.entryPoint
           << "\nInitial RSP: 0x" << loaded.stackPointer
           << std::dec << "\nLoadable segments: " << loaded.loadedSegments
           << "\nMemory permissions: per-page R/W/X"
           << "\nExecution: not started; dynamic linking and process ABI are not implemented";
    return env->NewStringUTF(output.str().c_str());
}
