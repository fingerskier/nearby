package io.github.fingerskier.nearby

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Runs on one engine for the life of the process. The watching service keeps the process alive, so the guard
 * keeps running after this activity is closed or swiped away, and reopening the app picks it up where it is.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        return cache.get(ENGINE) ?: FlutterEngine(context.applicationContext).also {
            it.plugins.add(NearbyPlugin())
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ENGINE, it)
        }
    }

    override fun shouldDestroyEngineWithHost() = false

    private companion object {
        const val ENGINE = "main"
    }
}
