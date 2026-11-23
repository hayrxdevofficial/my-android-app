# 3D Animator Studio (Android)

An Android WebView shell around a Three.js 3D scene editor.

## Features
- Import animated GLB / GLTF files from device storage
- Preview available skeletal animation clips
- Add demo character, cube and sphere
- Multiple objects, transform controls, orbit camera and basic battle-scene layout
- Save scene layout as JSON
- GitHub Actions builds a debug APK artifact

## Build
Requires JDK 17 and Android SDK 35.

```bash
gradle assembleDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`

The editor loads Three.js modules from jsDelivr, so the first launch and 3D editor require an internet connection. Imported GLTF files that reference external texture or binary files should be packaged as GLB for the most reliable import.
