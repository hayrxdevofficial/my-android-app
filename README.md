# PS4 Emulator — Android foundation

Experimental Android frontend for a future PlayStation 4 compatibility project.

## Version 0.2.0

- Kotlin Android application
- Keyboard and USB/Bluetooth Android gamepad detection
- Controller/keyboard input event display
- Bluetooth settings shortcut for pairing
- Network connectivity status
- Local file selection through Android Storage Access Framework
- PS4 profile target: 70 GB virtual storage and 6 GB RAM ceiling
- Download buttons for the official Sony PS4 update and reinstallation PUP packages
- GitHub Actions debug APK build

## Official firmware

The app downloads the official Sony PUP packages currently linked by Sony's PS4 support page. Downloads are saved in the Android Downloads folder using Android DownloadManager.

Sony provides PS4 system-software update and reinstallation packages in PUP format. Sony does not provide an official bootable PS4 ISO on that support page. A PUP package is intended for updating/reinstalling software on a physical PS4; it is not a ready-to-boot emulator image.

The direct Sony download URLs are versioned and can change. If a link stops working, use the in-app Open Sony firmware page action and download from Sony's official page. No third-party firmware mirrors are used.

Official source: https://www.playstation.com/en-gb/support/hardware/ps4/system-software/

## Resource profile

The 70 GB storage and 6 GB RAM values are configuration targets only. The current app does not reserve 6 GB of Android memory or create a 70 GB virtual disk. Those resources will become active only after a virtual storage backend and PS4 execution core exist.

## Current limitations

This is not yet a functioning PS4 emulator. Selecting a PUP or game file does not boot it or run a game. The current app is an Android frontend/input prototype with firmware download support. A real PS4 compatibility implementation requires substantial CPU/Jaguar, GPU, operating-system, memory, audio and storage work, plus compatibility testing. No Sony keys or copyrighted game data are included.

## Build

Open in Android Studio with JDK 17 and Android SDK 35. GitHub Actions builds a debug APK and uploads ps4-emulator-debug-apk.
