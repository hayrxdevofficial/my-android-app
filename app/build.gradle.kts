plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }

android {
    namespace = "com.hayrx.ps4emu"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.hayrx.ps4emu"
        minSdk = 26
        targetSdk = 35
        versionCode = 6
        versionName = "0.6.0"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { cppFlags += listOf("-std=c++17") }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
