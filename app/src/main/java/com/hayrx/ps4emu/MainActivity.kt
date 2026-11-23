package com.hayrx.ps4emu

import android.app.Activity
import java.io.ByteArrayOutputStream
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.Settings
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File

class MainActivity : Activity(), InputManager.InputDeviceListener {
    private lateinit var status: TextView
    private lateinit var devices: TextView
    private lateinit var inputLog: TextView
    private lateinit var gameFile: TextView
    private lateinit var profile: TextView
    private lateinit var coreStatus: TextView
    private lateinit var firmwareProgressText: TextView
    private lateinit var firmwareProgressBar: ProgressBar
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeFirmwareDownloadId: Long? = null
    private lateinit var inputManager: InputManager
    private lateinit var connectivityManager: ConnectivityManager

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: android.net.Network) {
            runOnUiThread { refreshNetworkStatus() }
        }
        override fun onLost(network: android.net.Network) {
            runOnUiThread { refreshNetworkStatus() }
        }
        override fun onCapabilitiesChanged(
            network: android.net.Network,
            networkCapabilities: NetworkCapabilities
        ) {
            runOnUiThread { refreshNetworkStatus() }
        }
    }

    companion object {
        // Official Sony links currently exposed by the PS4 support page.
        // These are firmware packages for a real PS4, not bootable emulator images.
        private const val SONY_UPDATE_PUP =
            "https://pc.ps4.update.playstation.net/update/ps4/image/2026_1023/sys_2acc318d7cafb18d7898754c8a97e2da/PS4UPDATE.PUP"
        private const val SONY_REINSTALL_PUP =
            "https://pc.ps4.update.playstation.net/update/ps4/image/2026_1023/rec_6abfe48f2d592e10d4977757fa9c87ee/PS4UPDATE.PUP"
        private const val SONY_SUPPORT =
            "https://www.playstation.com/en-gb/support/hardware/ps4/system-software/"
        private const val PREFS = "ps4_profile"
        private const val KEY_STORAGE_GB = "storage_gb"
        private const val KEY_RAM_GB = "ram_gb"
        private const val PICKER_CODE = 4102
        private const val ELF_PICKER_CODE = 4103

        private val nativeLibraryLoaded = try { System.loadLibrary("pshere"); true } catch (_: UnsatisfiedLinkError) { false }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(this, null)
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivityManager.registerDefaultNetworkCallback(networkCallback)

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        // These are emulator profile limits, not memory/storage reserved from Android.
        prefs.edit().putInt(KEY_STORAGE_GB, 70).putInt(KEY_RAM_GB, 6).apply()

        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(22, 20, 22, 28)
            setBackgroundColor(0xFF090D18.toInt())
        }
        val scroll = ScrollView(this)
        val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        scroll.addView(content)
        page.addView(scroll)

        content.addView(label("PS4 EMULATOR", 28, 0xFFFFFFFF.toInt()))
        content.addView(label("PSHERE NATIVE CORE • VERSION 0.7.0", 11, 0xFF8EA4C8.toInt()))
        content.addView(label("Compatibility prototype. PS4 games do not run yet.", 14, 0xFFFFC66D.toInt()))

        content.addView(section("EMULATOR PROFILE"))
        profile = label("", 14, 0xFFD4DDF0.toInt())
        content.addView(profile)
        content.addView(label(
            "70 GB is a target virtual-disk limit; 6 GB is a configured RAM ceiling. " +
                "Neither is allocated from Android yet because the PS4 core and virtual disk are not implemented.",
            12, 0xFF9DB3D5.toInt()
        ))
        refreshProfile()

        content.addView(section("PSHERE NATIVE CPU CORE"))
        coreStatus = label("Loading native core...", 12, 0xFF9DB3D5.toInt())
        content.addView(coreStatus)
        content.addView(action("RUN X86-64 CORE SELF-TEST") { runCoreSelfTest() })
        content.addView(action("LOAD X86-64 ELF64") { openElfPicker() })
        content.addView(action("RUN LOADED ELF (500K INSTRUCTIONS)") { runLoadedElf() })
        refreshCoreStatus()

        content.addView(section("TABLET NETWORK BRIDGE"))
        content.addView(label(
            "The app uses Android's active network automatically. When the tablet is on Wi-Fi, " +
                "firmware downloads and app network requests use that Wi-Fi connection. " +
                "PS4 guest-network emulation is not implemented until the console core exists.",
            12, 0xFF9DB3D5.toInt()
        ))
        content.addView(action("CHECK WI-FI / INTERNET STATUS") { refreshNetworkStatus() })

        content.addView(section("PS4 FIRMWARE • DOWNLOAD & IMPORT"))
        content.addView(label("Download an official Sony PUP package. PSHere shows the real download percentage, then copies the completed package into its private firmware folder.", 12, 0xFF9DB3D5.toInt()))
        content.addView(action("DOWNLOAD + IMPORT PS4 UPDATE (.PUP)") { downloadFirmware(SONY_UPDATE_PUP, "PS4UPDATE.PUP") })
        content.addView(action("DOWNLOAD + IMPORT REINSTALL PUP") { downloadFirmware(SONY_REINSTALL_PUP, "PS4_REINSTALL.PUP") })
        firmwareProgressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100; progress = 0 }
        content.addView(firmwareProgressBar)
        firmwareProgressText = label("Firmware: not downloaded", 13, 0xFF9DB3D5.toInt())
        content.addView(firmwareProgressText)
        content.addView(action("OPEN SONY FIRMWARE PAGE") { openSonyPage() })
        content.addView(label("Important: this imports the PUP file into PSHere storage; it does NOT install or boot the PS4 operating system. PUP is not a bootable ISO. Firmware parsing and PS4 system compatibility are not implemented.", 12, 0xFFFFC66D.toInt()))
        status = label("Network: checking", 14, 0xFFB8C7E0.toInt())
        content.addView(status)
        content.addView(action("REFRESH STATUS & CONTROLLERS") { refreshAll() })
        content.addView(action("PAIR BLUETOOTH CONTROLLER") {
            try {
                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            } catch (_: Exception) {
                Toast.makeText(this, "Bluetooth settings unavailable", Toast.LENGTH_SHORT).show()
            }
        })
        content.addView(action("SELECT PUP OR GAME FILE") { openPicker() })
        gameFile = label("No file selected", 13, 0xFF9DB3D5.toInt())
        content.addView(gameFile)

        content.addView(section("CONNECTED INPUT DEVICES"))
        devices = label("", 13, 0xFFD4DDF0.toInt())
        content.addView(devices)

        content.addView(section("INPUT TEST"))
        inputLog = label("Press a keyboard key or controller button.", 14, 0xFF79D7B5.toInt())
        content.addView(inputLog)

        content.addView(section("TOUCH CONTROLS"))
        val captions = listOf("UP", "LEFT", "X", "RIGHT", "DOWN", "O", "SQUARE", "TRIANGLE")
        val codes = listOf(
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_BUTTON_A,
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_BUTTON_B,
            KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y
        )
        captions.forEachIndexed { i, caption ->
            content.addView(action(caption) {
                inputLog.text = "Touch input: $caption / " + KeyEvent.keyCodeToString(codes[i])
            })
        }

        content.addView(section("ENGINE ROADMAP"))
        content.addView(label(
            "1. Expand x86-64 CPU instruction coverage\n" +
                "2. PS4 kernel and system-library compatibility\n" +
                "3. GPU command translation and shaders\n" +
                "4. Audio, storage and compatibility testing",
            13, 0xFF8EA4C8.toInt()
        ))
        setContentView(page)
        refreshAll()
    }

    private fun label(value: String, size: Int, color: Int) = TextView(this).apply {
        text = value
        textSize = size.toFloat()
        setTextColor(color)
        setPadding(0, 9, 0, 9)
    }

    private fun section(value: String) = label(value, 15, 0xFF6EA8FF.toInt())

    private fun action(value: String, run: () -> Unit) = Button(this).apply {
        text = value
        isAllCaps = false
        setOnClickListener { run() }
    }

    private external fun nativeCoreInfo(): String
    private external fun nativeRunSelfTest(): String
    private external fun nativeLoadElf(data: ByteArray): String
    private external fun nativeRunLoadedElf(maxInstructions: Int): String

    private fun refreshCoreStatus() {
        coreStatus.text = if (nativeLibraryLoaded) {
            try { nativeCoreInfo() } catch (error: UnsatisfiedLinkError) {
                "PSHere native library failed to load: ${error.message}"
            }
        } else {
            "PSHere native library is unavailable for this device ABI."
        }
    }

    private fun runCoreSelfTest() {
        coreStatus.text = if (nativeLibraryLoaded) {
            try { nativeCoreInfo() + "\n\n" + nativeRunSelfTest() }
            catch (error: UnsatisfiedLinkError) {
                "PSHere native library failed to load: ${error.message}"
            }
        } else {
            "PSHere native library is unavailable for this device ABI."
        }
    }

    private fun refreshProfile() {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        profile.text = "Virtual storage limit: ${prefs.getInt(KEY_STORAGE_GB, 70)} GB\n" +
            "RAM ceiling: ${prefs.getInt(KEY_RAM_GB, 6)} GB"
    }

    private fun downloadFirmware(url: String, fileName: String) {
        try {
            activeFirmwareDownloadId?.let { old -> try { (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).remove(old) } catch (_: Exception) { } }
            firmwareProgressBar.progress = 0
            firmwareProgressBar.isIndeterminate = true
            firmwareProgressText.text = "Connecting to Sony…"
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle(fileName).setDescription("Official PlayStation 4 system software from Sony")
                .setMimeType("application/octet-stream")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverMetered(true).setAllowedOverRoaming(false)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            val id = (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
            activeFirmwareDownloadId = id
            firmwareProgressText.text = "Download queued: " + fileName
            pollFirmwareDownload(id, fileName)
        } catch (e: Exception) {
            firmwareProgressBar.isIndeterminate = false
            firmwareProgressText.text = "Download error: " + e.message
        }
    }

    private fun pollFirmwareDownload(id: Long, fileName: String) {
        val cursor = (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).query(DownloadManager.Query().setFilterById(id))
        if (cursor == null) { firmwareProgressText.text = "Cannot read download status."; return }
        var again = false
        try {
            if (!cursor.moveToFirst()) { firmwareProgressText.text = "Download task not found."; return }
            val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val done = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val pct = if (total > 0L) ((done * 100L) / total).toInt().coerceIn(0, 100) else -1
            firmwareProgressBar.isIndeterminate = total <= 0L && state == DownloadManager.STATUS_RUNNING
            if (pct >= 0) firmwareProgressBar.progress = pct
            when (state) {
                DownloadManager.STATUS_PENDING -> { firmwareProgressText.text = "Waiting for network…"; again = true }
                DownloadManager.STATUS_RUNNING -> { firmwareProgressText.text = if (pct >= 0) "Downloading " + fileName + ": " + pct + "% (" + (done / 1048576) + " / " + (total / 1048576) + " MB)" else "Downloading " + fileName; again = true }
                DownloadManager.STATUS_PAUSED -> { firmwareProgressText.text = "Download paused; waiting for connection…"; again = true }
                DownloadManager.STATUS_SUCCESSFUL -> { firmwareProgressBar.isIndeterminate = true; firmwareProgressText.text = "Download complete. Importing…"; importFirmwarePackage(id, fileName) }
                DownloadManager.STATUS_FAILED -> { val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)); firmwareProgressBar.isIndeterminate = false; firmwareProgressText.text = "Download failed (code " + reason + "). Check connection or Sony support page."; activeFirmwareDownloadId = null }
                else -> { firmwareProgressText.text = "Unknown download state."; again = true }
            }
        } catch (e: Exception) { firmwareProgressBar.isIndeterminate = false; firmwareProgressText.text = "Status error: " + e.message }
        finally { cursor.close() }
        if (again && activeFirmwareDownloadId == id) mainHandler.postDelayed({ pollFirmwareDownload(id, fileName) }, 500L)
    }

    private fun importFirmwarePackage(id: Long, fileName: String) {
        Thread {
            try {
                val dir = File(filesDir, "firmware")
                if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("Cannot create firmware folder")
                val target = File(dir, fileName)
                var bytes = 0L
                (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).openDownloadedFile(id).use { input ->
                    target.outputStream().buffered().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) { val count = input.read(buffer); if (count < 0) break; output.write(buffer, 0, count); bytes += count }
                    }
                }
                runOnUiThread { firmwareProgressBar.isIndeterminate = false; firmwareProgressBar.progress = 100; firmwareProgressText.text = "100% • Imported (" + (bytes / 1048576) + " MB). Not bootable yet."; gameFile.text = "PUP stored in PSHere private firmware folder: " + target.name; activeFirmwareDownloadId = null }
            } catch (e: Exception) { runOnUiThread { firmwareProgressBar.isIndeterminate = false; firmwareProgressText.text = "Import failed: " + e.message; activeFirmwareDownloadId = null } }
        }.start()
    }
    private fun openSonyPage() {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SONY_SUPPORT)))
        } catch (_: Exception) {
            Toast.makeText(this, "Could not open Sony support page", Toast.LENGTH_SHORT).show()
        }
    }

    private fun runLoadedElf() {
        coreStatus.text = "Running guest ELF with a 500,000-instruction safety budget..."
        Thread {
            val result = try {
                if (!nativeLibraryLoaded) "PSHere native library is unavailable for this device ABI."
                else nativeRunLoadedElf(500000)
            } catch (error: UnsatisfiedLinkError) {
                "ELF execution failed: ${error.message}"
            }
            runOnUiThread { coreStatus.text = result }
        }.start()
    }

    private fun openElfPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivityForResult(intent, ELF_PICKER_CODE)
    }

    private fun loadElf(uri: Uri) {
        coreStatus.text = "Reading ELF file..."
        Thread {
            val result = try {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > 128 * 1024 * 1024) {
                            throw IllegalArgumentException("ELF file exceeds the 128 MiB loader limit")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("Could not open selected file")
                if (!nativeLibraryLoaded) "PSHere native library is unavailable for this device ABI."
                else nativeLoadElf(bytes)
            } catch (error: Exception) {
                "ELF load failed: ${error.message}"
            }
            runOnUiThread {
                coreStatus.text = result
                gameFile.text = "Selected ELF: ${uri.lastPathSegment ?: uri}\n$result"
            }
        }.start()
    }

    private fun openPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, PICKER_CODE)
    }

    @Deprecated("Document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ELF_PICKER_CODE && resultCode == RESULT_OK) {
            data?.data?.let { uri -> loadElf(uri) }
        }
        if (requestCode == PICKER_CODE && resultCode == RESULT_OK) data?.data?.let { uri ->
            val name = uri.lastPathSegment ?: uri.toString()
            gameFile.text = "Selected: $name\nRead access granted. Firmware parsing and game execution are not implemented."
            try {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (_: Exception) { }
        }
    }

    private fun refreshNetworkStatus() {
        if (!::status.isInitialized) return
        val caps = connectivityManager.activeNetwork?.let {
            connectivityManager.getNetworkCapabilities(it)
        }
        val network = when {
            caps == null -> "Offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet connected"
            else -> "Network connected"
        }
        status.text = "Network: $network"
    }

    private fun refreshAll() {
        refreshNetworkStatus()
        refreshDevices()
    }

    private fun refreshDevices() {
        val found = inputManager.inputDeviceIds.asIterable().mapNotNull { id ->
            inputManager.getInputDevice(id)?.let { d ->
                val type = when {
                    d.supportsSource(InputDevice.SOURCE_GAMEPAD) -> "Gamepad"
                    d.supportsSource(InputDevice.SOURCE_JOYSTICK) -> "Joystick"
                    d.supportsSource(InputDevice.SOURCE_KEYBOARD) -> "Keyboard"
                    else -> "Input device"
                }
                "• ${d.name} — $type"
            }
        }
        devices.text = if (found.isEmpty()) {
            "No external controller detected. Pair/connect it, then refresh."
        } else found.joinToString("\n")
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            inputLog.text = "Input: " + KeyEvent.keyCodeToString(event.keyCode)
            return true
        }
        if (event.action == KeyEvent.ACTION_UP) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_JOYSTICK)) {
            inputLog.text = "Analog stick X=${event.getAxisValue(MotionEvent.AXIS_X)} " +
                "Y=${event.getAxisValue(MotionEvent.AXIS_Y)}"
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onInputDeviceAdded(deviceId: Int) = refreshDevices()
    override fun onInputDeviceRemoved(deviceId: Int) = refreshDevices()
    override fun onInputDeviceChanged(deviceId: Int) = refreshDevices()

    override fun onDestroy() {
        inputManager.unregisterInputDeviceListener(this)
        try { connectivityManager.unregisterNetworkCallback(networkCallback) } catch (_: Exception) { }
        super.onDestroy()
    }
}
