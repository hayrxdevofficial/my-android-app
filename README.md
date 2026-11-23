# PS4 Emulator — Android foundation

Experimental Android frontend for a future PlayStation 4 compatibility project.

## Included in 0.1.0
- Kotlin Android application
- Keyboard and USB/Bluetooth Android gamepad detection
- Controller/keyboard input event display
- Bluetooth settings shortcut for pairing
- Network connectivity status
- Local game-file selection via Storage Access Framework
- Touch input test buttons

## Important
This is not yet a functioning PS4 emulator. Selecting a game file does not run it. A real PS4 emulator needs substantial CPU, GPU, operating-system, audio and storage implementations plus compatibility testing. No Sony firmware, keys or copyrighted game data are included.

## Build
Open in Android Studio with JDK 17 and Android SDK 35. GitHub Actions builds a debug APK and uploads `ps4-emulator-debug-apk`.
