package io.github.fingerskier.nearby

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The app's one Flutter engine, for the life of the process. The activity shows it, and the watching service
 * starts it without one when Android restarts the process after reclaiming it.
 */
object NearbyEngine {
    private const val ID = "main"

    fun obtain(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        return cache.get(ID) ?: FlutterEngine(context.applicationContext).also {
            it.plugins.add(NearbyPlugin())
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ID, it)
        }
    }
}
