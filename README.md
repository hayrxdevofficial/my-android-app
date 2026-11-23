# PS4 Emulator — Android foundation

Experimental Android frontend and early compatibility-layer project for PlayStation 4 research.

## Version 0.3.0

- Kotlin Android application
- Keyboard and USB/Bluetooth Android gamepad detection
- Controller/keyboard input event display
- Bluetooth settings shortcut for pairing
- Android default-network monitoring (Wi-Fi, mobile data, Ethernet)
- Internet validation status from Android ConnectivityManager
- Firmware downloads use Android DownloadManager and the tablet's active network route
- Local file selection through Android Storage Access Framework
- PS4 profile target: 70 GB virtual storage and 6 GB RAM ceiling
- Official Sony PUP download controls

## Tablet Wi-Fi networking

The app observes Android's default network. When the tablet is connected to Wi-Fi, Android routes app downloads and network requests over that Wi-Fi connection automatically. The status panel reports the active transport and whether Android has validated internet connectivity.

This is not yet a PS4 virtual network adapter. Game traffic, PSN protocols, multiplayer, NAT behavior and console-side sockets require a working PS4 execution core and a separate guest networking implementation. The current change verifies the tablet's network path only.

## Firmware

Sony supplies PS4 system software as PUP update/reinstallation packages, not a bootable PS4 ISO. A PUP is intended for updating or reinstalling software on a physical PS4; it is not a ready-to-boot emulator image. Use the official Sony support page linked in the app if a direct package URL changes.

Official source: https://www.playstation.com/en-gb/support/hardware/ps4/system-software/

## Resource profile

The 70 GB storage and 6 GB RAM values are configuration targets only. The current app does not reserve 6 GB of Android memory or create a 70 GB virtual disk. Those resources become active only after a virtual storage backend and PS4 execution core exist.

## Emulation status and requirements

This is not yet a functioning PS4 emulator. Selecting a PUP or game file does not boot it or run a game. A real implementation needs an x86-64 instruction translation layer for the PS4 CPU, GPU command translation, kernel/system-library compatibility, memory management, storage, audio and extensive game-by-game testing. ARM Android adds a major CPU-translation and GPU-driver challenge.

The upstream shadPS4 quick-start currently lists a PC-class x86-64-v3 CPU, Vulkan 1.3 and at least 8 GB RAM as minimum requirements, and warns that many games still do not work. This project's 6 GB profile is therefore a strict experimental budget, not a promise of compatibility.

## Build

Open in Android Studio with JDK 17 and Android SDK 35. GitHub Actions builds a debug APK and uploads `ps4-emulator-debug-apk`.
