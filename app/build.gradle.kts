plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.hayrx.ps4emu"
    compileSdk = 35
    defaultConfig { applicationId = "com.hayrx.ps4emu"; minSdk = 26; targetSdk = 35; versionCode = 3; versionName = "0.3.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
