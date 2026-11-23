package com.hayrx.ps4emu

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity(), InputManager.InputDeviceListener {
    private lateinit var status: TextView
    private lateinit var devices: TextView
    private lateinit var inputLog: TextView
    private lateinit var gameFile: TextView
    private lateinit var inputManager: InputManager
    private val pickerCode = 4102

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(this, null)
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(22, 20, 22, 28); setBackgroundColor(0xFF090D18.toInt()) }
        val scroll = ScrollView(this)
        val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        scroll.addView(content)
        page.addView(scroll)
        content.addView(label("PS4 EMULATOR", 28, 0xFFFFFFFF.toInt()))
        content.addView(label("ANDROID FOUNDATION • VERSION 0.1.0", 11, 0xFF8EA4C8.toInt()))
        content.addView(label("Early frontend. PS4 games do not run yet.", 14, 0xFFFFC66D.toInt()))
        status = label("Network: checking", 14, 0xFFB8C7E0.toInt()); content.addView(status)
        content.addView(action("REFRESH STATUS & CONTROLLERS") { refreshAll() })
        content.addView(action("PAIR BLUETOOTH CONTROLLER") { try { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) } catch (_: Exception) { Toast.makeText(this, "Bluetooth settings unavailable", Toast.LENGTH_SHORT).show() } })
        content.addView(action("SELECT GAME FILE") { openPicker() })
        gameFile = label("No game file selected", 13, 0xFF9DB3D5.toInt()); content.addView(gameFile)
        content.addView(section("CONNECTED INPUT DEVICES"))
        devices = label("", 13, 0xFFD4DDF0.toInt()); content.addView(devices)
        content.addView(section("INPUT TEST"))
        inputLog = label("Press a keyboard key or controller button.", 14, 0xFF79D7B5.toInt()); content.addView(inputLog)
        content.addView(section("TOUCH CONTROLS"))
        val captions = listOf("UP", "LEFT", "X", "RIGHT", "DOWN", "O", "SQUARE", "TRIANGLE")
        val codes = listOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y)
        captions.forEachIndexed { i, caption -> content.addView(action(caption) { inputLog.text = "Touch input: " + caption + " / " + KeyEvent.keyCodeToString(codes[i]) }) }
        content.addView(section("ENGINE ROADMAP"))
        content.addView(label("1. CPU, memory and kernel compatibility\n2. Graphics command translation\n3. Audio and storage systems\n4. Firmware and game compatibility tests", 13, 0xFF8EA4C8.toInt()))
        setContentView(page)
        refreshAll()
    }

    private fun label(value: String, size: Int, color: Int) = TextView(this).apply { text = value; textSize = size.toFloat(); setTextColor(color); setPadding(0, 9, 0, 9) }
    private fun section(value: String) = label(value, 15, 0xFF6EA8FF.toInt())
    private fun action(value: String, run: () -> Unit) = Button(this).apply { text = value; isAllCaps = false; setOnClickListener { run() } }

    private fun openPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"; addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) }
        startActivityForResult(intent, pickerCode)
    }

    @Deprecated("Document picker callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickerCode && resultCode == RESULT_OK) data?.data?.let { uri ->
            gameFile.text = "Selected: " + (uri.lastPathSegment ?: uri.toString()) + "\nRead access granted; execution is not implemented."
            try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) { }
        }
    }

    private fun refreshAll() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
        val network = when {
            caps == null -> "Offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data connected"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet connected"
            else -> "Network connected"
        }
        status.text = "Network: " + network
        refreshDevices()
    }

    private fun refreshDevices() {
        val found = inputManager.inputDeviceIds.mapNotNull { id -> inputManager.getInputDevice(id)?.let { d ->
            val type = when { d.supportsSource(InputDevice.SOURCE_GAMEPAD) -> "Gamepad"; d.supportsSource(InputDevice.SOURCE_JOYSTICK) -> "Joystick"; d.supportsSource(InputDevice.SOURCE_KEYBOARD) -> "Keyboard"; else -> "Input device" }
            "• " + d.name + " — " + type
        } }
        devices.text = if (found.isEmpty()) "No external controller detected. Pair/connect it, then refresh." else found.joinToString("\n")
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) { inputLog.text = "Input: " + KeyEvent.keyCodeToString(event.keyCode); return true }
        if (event.action == KeyEvent.ACTION_UP) return true
        return super.dispatchKeyEvent(event)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_JOYSTICK)) {
            inputLog.text = "Analog stick X=" + event.getAxisValue(MotionEvent.AXIS_X) + " Y=" + event.getAxisValue(MotionEvent.AXIS_Y)
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onInputDeviceAdded(deviceId: Int) = refreshDevices()
    override fun onInputDeviceRemoved(deviceId: Int) = refreshDevices()
    override fun onInputDeviceChanged(deviceId: Int) = refreshDevices()
    override fun onDestroy() { inputManager.unregisterInputDeviceListener(this); super.onDestroy() }
}
