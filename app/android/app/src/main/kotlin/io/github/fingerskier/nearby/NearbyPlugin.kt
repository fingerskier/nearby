package io.github.fingerskier.nearby

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Sends events to Dart while it listens (see lib/src/android_channel.dart). Main thread only. */
object Events {
    internal var sink: EventChannel.EventSink? = null

    /** Whether anyone was listening. */
    fun emit(event: Map<String, Any?>): Boolean {
        val listener = sink ?: return false
        listener.success(event)
        return true
    }
}

/** The app's Android side: scanning, notifications, the ping, permissions and the watching service. */
class NearbyPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var scanner: LeScanner
    private lateinit var alerts: Alerts
    private var activity: ActivityPluginBinding? = null
    private var pendingAnswer: (() -> Unit)? = null

    /** Permissions this process has shown the dialog for. */
    private val asked = mutableSetOf<String>()

    private val notificationPermission = buildList {
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        alerts = Alerts(context)
        scanner = LeScanner(
            context,
            onSighting = { Events.emit(it) },
            onStatus = { status, error -> Events.emit(mapOf("type" to "scanState", "status" to status, "error" to error)) },
        )
        methods = MethodChannel(binding.binaryMessenger, "io.github.fingerskier.nearby/methods").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "io.github.fingerskier.nearby/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        Events.sink = null
        scanner.close()
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        Events.sink = sink
    }

    override fun onCancel(arguments: Any?) {
        Events.sink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
        answer()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> {
                val (status, error) = scanner.status()
                result.success(mapOf("status" to status, "error" to error))
            }
            // On first launch: everything the app needs, in one go.
            "requestPermissions" -> ask(listOf(Manifest.permission.BLUETOOTH_SCAN) + notificationPermission, ::appSettings) {
                result.success(scanner.hasPermission())
            }
            "requestScanPermission" -> ask(listOf(Manifest.permission.BLUETOOTH_SCAN), ::appSettings) {
                result.success(scanner.hasPermission())
            }
            "notificationsAllowed" -> result.success(alerts.allowed())
            "requestNotifications" -> requestNotifications(result)
            "refresh" -> {
                scanner.refresh()
                if (scanner.wanted) startService()
                result.success(null)
            }
            "startScan" -> {
                scanner.want(true)
                startService()
                result.success(null)
            }
            "stopScan" -> {
                scanner.want(false)
                result.success(null)
            }
            "notify" -> result.success(
                alerts.show(
                    call.argument<String>("title").orEmpty(),
                    call.argument<String>("body").orEmpty(),
                    call.argument<Map<String, String>>("actions").orEmpty(),
                ),
            )
            "ping" -> result.success(alerts.ping())
            "setWatching" -> {
                WatchService.update(context, call.argument<String>("text").orEmpty())
                result.success(null)
            }
            "exit" -> {
                result.success(null)
                exit()
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Shows the permission dialog for whichever of [wanted] are missing, then calls [done]. Android stops showing
     * the dialog for a permission once the user has declined it twice, so after that this opens [settings] instead.
     */
    private fun ask(wanted: List<String>, settings: () -> Intent, done: () -> Unit) {
        val host = activity?.activity
        val missing = wanted.filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty() || host == null || pendingAnswer != null) return done()
        if (missing.all { it in asked && !host.shouldShowRequestPermissionRationale(it) }) {
            host.startActivity(settings())
            return done()
        }
        asked += missing
        pendingAnswer = done
        host.requestPermissions(missing.toTypedArray(), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        answer()
        return true
    }

    private fun answer() {
        val done = pendingAnswer ?: return
        pendingAnswer = null
        scanner.refresh()
        if (scanner.wanted) startService()
        done()
    }

    /** The dialog while Android still shows it, otherwise the app's notification settings. */
    private fun requestNotifications(result: MethodChannel.Result) {
        val granted = notificationPermission.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            // Allowed, but turned off in the system settings.
            if (!alerts.allowed()) activity?.activity?.startActivity(notificationSettings())
            result.success(alerts.allowed())
            return
        }
        ask(notificationPermission, ::notificationSettings) { result.success(alerts.allowed()) }
    }

    private fun appSettings() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))

    private fun notificationSettings() =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

    /** Android only grants a connected-device service once the Nearby devices permission is in place. */
    private fun startService() {
        if (scanner.hasPermission() && !WatchService.running) WatchService.start(context)
    }

    /** The engine outlives the activity on purpose (see MainActivity), so quitting means ending the process. */
    private fun exit() {
        scanner.want(false)
        alerts.cancelAll()
        WatchService.stop(context)
        activity?.activity?.finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed({ Process.killProcess(Process.myPid()) }, 300)
    }

    private companion object {
        const val REQUEST_CODE = 0x6e62
    }
}
