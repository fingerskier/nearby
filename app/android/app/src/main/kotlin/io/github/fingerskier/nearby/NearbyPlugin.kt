package io.github.fingerskier.nearby

import android.Manifest
import android.app.Activity
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
    private var pendingRequest: MethodChannel.Result? = null
    private var askedBefore = false

    private val permissions = buildList {
        add(Manifest.permission.BLUETOOTH_SCAN)
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
        answerPermissionRequest()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> {
                val (status, error) = scanner.status()
                result.success(mapOf("status" to status, "error" to error))
            }
            "requestPermissions" -> requestPermissions(result)
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
     * Asks for whatever is missing and answers whether scanning is allowed. Android stops showing the dialog
     * once the user has declined twice, so after that this opens the app's settings page instead.
     */
    private fun requestPermissions(result: MethodChannel.Result) {
        val host = activity?.activity
        val missing = permissions.filter { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty() || host == null || pendingRequest != null) {
            result.success(scanner.hasPermission())
            return
        }
        if (askedBefore && missing.none { host.shouldShowRequestPermissionRationale(it) }) {
            openSettings(host)
            result.success(scanner.hasPermission())
            return
        }
        askedBefore = true
        pendingRequest = result
        host.requestPermissions(missing.toTypedArray(), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        answerPermissionRequest()
        return true
    }

    private fun answerPermissionRequest() {
        val result = pendingRequest ?: return
        pendingRequest = null
        scanner.refresh()
        if (scanner.wanted) startService()
        result.success(scanner.hasPermission())
    }

    private fun openSettings(host: Activity) {
        host.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
        )
    }

    /** Android only grants a connected-device service once the Nearby devices permission is in place. */
    private fun startService() {
        if (scanner.hasPermission() && !WatchService.running) WatchService.start(context)
    }

    /** The engine outlives the activity on purpose (see MainActivity), so quitting means ending the process. */
    private fun exit() {
        scanner.want(false)
        WatchService.stop(context)
        activity?.activity?.finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed({ Process.killProcess(Process.myPid()) }, 300)
    }

    private companion object {
        const val REQUEST_CODE = 0x6e62
    }
}
