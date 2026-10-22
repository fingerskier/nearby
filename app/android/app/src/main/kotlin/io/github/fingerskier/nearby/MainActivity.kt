package io.github.fingerskier.nearby

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Shows the app's one engine (see NearbyEngine). The watching service keeps the process alive, so the guard
 * keeps running after this activity is closed or swiped away, and reopening the app picks it up where it is.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = NearbyEngine.obtain(context)

    override fun shouldDestroyEngineWithHost() = false
}
