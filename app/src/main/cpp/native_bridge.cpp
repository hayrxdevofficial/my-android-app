#include <jni.h>

#include "pshere_core.h"

#include <sstream>

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
           << "Implemented: sparse guest pages, MOV, ADD, SUB, XOR, CMP, TEST, PUSH, POP, CALL, RET, JMP, Jcc, NOP, HLT\n"
           << "Not implemented: PS4 kernel, SELF decryption, GPU, audio, game boot";
    return env->NewStringUTF(output.str().c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_hayrx_ps4emu_MainActivity_nativeRunSelfTest(JNIEnv* env, jobject) {
    const auto result = pshere::runSelfTest();
    std::ostringstream output;
    output << (result.passed ? "PASS" : "FAIL") << ": " << result.message
           << "\nRAX = " << result.rax
           << "\nInstructions = " << result.instructions;
    return env->NewStringUTF(output.str().c_str());
}
