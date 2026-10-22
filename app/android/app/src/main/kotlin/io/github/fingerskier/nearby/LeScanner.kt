package io.github.fingerskier.nearby

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.PowerManager
import android.os.SystemClock
import java.util.UUID

/**
 * Continuous BLE scanning that works around Android's limits:
 * - a scan running for 30 minutes is demoted to opportunistic and goes quiet, so it is renewed every 25;
 * - unfiltered scans are paused while the screen is off, so the screen-off scan uses filters;
 * - starts beyond five in 30 s are silently ignored, so starts are rate limited.
 *
 * Status names match ScannerStatus in lib/src/scan/scanner.dart. Everything runs on the main thread.
 */
class LeScanner(
    private val context: Context,
    private val onSighting: (Map<String, Any?>) -> Unit,
    private val onStatus: (status: String, error: String?) -> Unit,
) {
    private val adapter: BluetoothAdapter? = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val power = context.getSystemService(PowerManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val limiter = StartLimiter()
    private var running = false
    private var filtered = false
    private var failure: String? = null
    private var reported: Pair<String, String?>? = null

    /** Whether Dart asked for discovery. */
    var wanted = false
        private set

    private val screenOffFilters: List<ScanFilter> by lazy {
        val any = ParcelUuid(UUID(0, 0))
        buildList {
            // A zero mask matches any device that lists at least one service UUID.
            add(ScanFilter.Builder().setServiceUuid(any, any).build())
            for (company in screenOffCompanies) add(ScanFilter.Builder().setManufacturerData(company, ByteArray(0)).build())
            for (uuid in screenOffServiceData) {
                add(ScanFilter.Builder().setServiceData(ParcelUuid.fromString(uuid16(uuid)), ByteArray(0)).build())
            }
        }
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (running) onSighting(sightingOf(result))
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            if (running) results.forEach { onSighting(sightingOf(it)) }
        }

        override fun onScanFailed(errorCode: Int) {
            if (errorCode == SCAN_FAILED_ALREADY_STARTED) return
            running = false
            handler.removeCallbacks(renew)
            fail(scanErrorName(errorCode))
        }
    }

    private val retry = Runnable {
        failure = null
        apply()
    }
    private val renew = Runnable { restart() }
    private val deferredStart = Runnable { apply() }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    // Turning Bluetooth off ends every scan; start afresh once it's back.
                    if (adapter?.isEnabled != true) running = false
                    apply()
                }
                Intent.ACTION_SCREEN_OFF, Intent.ACTION_SCREEN_ON -> if (running && filtered != screenOff()) restart()
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    fun want(scan: Boolean) {
        wanted = scan
        if (!scan) {
            failure = null
            handler.removeCallbacks(retry)
        }
        apply()
    }

    /** Re-reads the permission and the adapter, e.g. after the user changed them in Settings. */
    fun refresh() = apply()

    fun hasPermission() =
        context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED

    fun status(): Pair<String, String?> = when {
        adapter == null -> "noAdapter" to null
        !hasPermission() -> "noPermission" to null
        !adapter.isEnabled -> "poweredOff" to null
        failure != null -> "failed" to failure
        running -> "scanning" to null
        else -> "idle" to null
    }

    fun close() {
        want(false)
        handler.removeCallbacksAndMessages(null)
        context.unregisterReceiver(receiver)
    }

    private fun apply() {
        handler.removeCallbacks(deferredStart)
        val ready = wanted && adapter?.isEnabled == true && hasPermission()
        if (!ready) stop() else if (!running && failure == null) start()
        report()
    }

    private fun restart() {
        stop()
        apply()
    }

    private fun start() {
        val scanner = adapter?.bluetoothLeScanner ?: return
        val now = SystemClock.elapsedRealtime()
        val wait = limiter.delayAt(now)
        if (wait > 0) {
            handler.postDelayed(deferredStart, wait)
            return
        }
        val screenOff = screenOff()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        limiter.record(now)
        try {
            scanner.startScan(if (screenOff) screenOffFilters else null, settings, callback)
        } catch (e: RuntimeException) {
            // SecurityException if the permission was just revoked, IllegalStateException if Bluetooth is going off.
            fail(e.message ?: e.javaClass.simpleName)
            return
        }
        running = true
        filtered = screenOff
        handler.postDelayed(renew, RENEW_MS)
    }

    private fun stop() {
        handler.removeCallbacks(renew)
        if (!running) return
        running = false
        try {
            adapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (_: RuntimeException) {
            // Bluetooth is already off, which stopped the scan anyway.
        }
    }

    private fun fail(error: String) {
        failure = error
        report()
        handler.removeCallbacks(retry)
        handler.postDelayed(retry, RETRY_MS)
    }

    private fun screenOff() = !power.isInteractive

    private fun report() {
        val now = status()
        if (now == reported) return
        reported = now
        onStatus(now.first, now.second)
    }

    private fun sightingOf(result: ScanResult): Map<String, Any?> {
        val record = result.scanRecord
        val makers = record?.manufacturerSpecificData
        return mapOf(
            "type" to "sighting",
            "address" to result.device.address,
            "addressType" to addressType(result.device),
            "rssi" to result.rssi,
            "name" to record?.deviceName,
            "txPower" to (result.txPower.takeIf { it != ScanResult.TX_POWER_NOT_PRESENT }
                ?: record?.txPowerLevel?.takeIf { it != Int.MIN_VALUE }),
            "manufacturer" to makers?.takeIf { it.size() > 0 }?.keyAt(0),
        )
    }

    private fun addressType(device: BluetoothDevice): String? {
        if (Build.VERSION.SDK_INT < 35) return null
        return try {
            addressTypeName(device.addressType)
        } catch (_: SecurityException) {
            null
        }
    }

    private companion object {
        const val RETRY_MS = 5_000L
        const val RENEW_MS = 25 * 60 * 1000L
    }
}
