package com.peoplewareinnovations.bluetooth_thermal_printer

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.util.UUID

private const val TAG = "BluetoothThermalPrinter"
private var outputStream: OutputStream? = null
private lateinit var mac: String

class BluetoothThermalPrinterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var mContext: Context
    private lateinit var channel: MethodChannel
    private lateinit var state: String

    override fun onAttachedToEngine(
        @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "bluetooth_thermal_printer"
        )
        channel.setMethodCallHandler(this)
        mContext = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getBatteryLevel" -> {
                val batteryLevel = getBatteryLevel()
                if (batteryLevel != -1) {
                    result.success(batteryLevel)
                } else {
                    result.error("UNAVAILABLE", "Battery level not available.", null)
                }
            }
            "BluetoothStatus" -> {
                var bluetoothState = "false"
                val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                if (bluetoothAdapter != null && bluetoothAdapter.isEnabled) {
                    bluetoothState = "true"
                }
                result.success(bluetoothState)
            }
            "connectionStatus" -> {
                if (outputStream != null) {
                    try {
                        outputStream?.run {
                            write(" ".toByteArray())
                            result.success("true")
                        }
                    } catch (e: Exception) {
                        result.success("false")
                        outputStream = null
                        showToast("Device was disconnected, reconnect")
                    }
                } else {
                    result.success("false")
                }
            }
            "connectPrinter" -> {
                val printerMac = call.arguments.toString()
                if (printerMac.isNotEmpty()) {
                    mac = printerMac
                } else {
                    result.success("false")
                    return
                }
                GlobalScope.launch(Dispatchers.Main) {
                    if (outputStream == null) {
                        outputStream = connect()
                        result.success(state)
                    } else {
                        result.success("true")
                    }
                }
            }
            "writeBytes" -> {
                val list = call.arguments as List<Int>
                var bytes: ByteArray = "\n".toByteArray()
                list.forEach {
                    bytes += it.toByte()
                }

                if (outputStream != null) {
                    try {
                        outputStream?.run {
                            write(bytes)
                            result.success("true")
                        }
                    } catch (e: Exception) {
                        result.success("false")
                        outputStream = null
                        showToast("Device was disconnected, reconnect")
                    }
                } else {
                    result.success("false")
                }
            }
            "printText" -> {
                val stringArrived = call.arguments.toString()

                if (outputStream != null) {
                    try {
                        val size: Int
                        val text: String
                        val line = stringArrived.split("//")
                        if (line.size > 1) {
                            size = line[0].toInt().coerceIn(1, 5)
                            text = line[1]
                        } else {
                            size = 2
                            text = stringArrived
                        }

                        outputStream?.run {
                            write(SetBytes.size[0])
                            write(SetBytes.cancelChinese)
                            write(SetBytes.escapeChars)
                            write(SetBytes.size[size])
                            write(text.toByteArray(charset("iso-8859-1")))
                            result.success("true")
                        }
                    } catch (e: Exception) {
                        result.success("false")
                        outputStream = null
                        showToast("Device was disconnected, reconnect")
                    }
                } else {
                    result.success("false")
                }
            }
            "bluetothLinked" -> result.success(getLinkedDevices())
            else -> result.notImplemented()
        }
    }

    private fun getBatteryLevel(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val batteryManager =
                mContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } else {
            val intent = ContextWrapper(mContext.applicationContext)
                .registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            intent!!.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) * 100 /
                intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        }
    }

    private suspend fun connect(): OutputStream? {
        state = "false"
        return withContext(Dispatchers.IO) {
            var currentOutputStream: OutputStream? = null
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter != null && bluetoothAdapter.isEnabled) {
                try {
                    val bluetoothDevice: BluetoothDevice =
                        bluetoothAdapter.getRemoteDevice(mac)
                    val bluetoothSocket = bluetoothDevice.createRfcommSocketToServiceRecord(
                        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
                    )
                    bluetoothAdapter.cancelDiscovery()
                    bluetoothSocket.connect()
                    if (bluetoothSocket.isConnected) {
                        currentOutputStream = bluetoothSocket.outputStream
                        state = "true"
                    } else {
                        state = "false"
                        Log.d(TAG, "Disconnected")
                    }
                } catch (e: Exception) {
                    state = "false"
                    Log.d(TAG, "connect: ${e.message}")
                    currentOutputStream?.close()
                }
            } else {
                state = "false"
                Log.d(TAG, "Adapter problem")
            }
            currentOutputStream
        }
    }

    private fun getLinkedDevices(): List<String> {
        val listItems: MutableList<String> = mutableListOf()
        val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
        val pairedDevices: Set<BluetoothDevice>? = bluetoothAdapter?.bondedDevices
        pairedDevices?.forEach { device ->
            listItems.add("${device.name}#${device.address}")
        }
        return listItems
    }

    private fun showToast(message: String) {
        Toast.makeText(mContext, message, Toast.LENGTH_SHORT).show()
    }

    object SetBytes {
        val cancelChinese = byteArrayOf(0x1C, 0x2E)
        val escapeChars = byteArrayOf(0x1B, 0x74, 0x10)
        val size = arrayOf(
            byteArrayOf(0x1D, 0x21, 0x00),
            byteArrayOf(0x1B, 0x4D, 0x01),
            byteArrayOf(0x1B, 0x4D, 0x00),
            byteArrayOf(0x1D, 0x21, 0x11),
            byteArrayOf(0x1D, 0x21, 0x22),
            byteArrayOf(0x1D, 0x21, 0x33)
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
