package dev.deaddrop.dead_drop

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Keeps the screen on while a transfer runs.
///
/// The sender displays animated QR codes and the receiver points a camera at
/// them; a screen that dims or locks mid-transfer stalls it, and locking the
/// sender's phone hides what the other device is reading.
///
/// FLAG_KEEP_SCREEN_ON is the Android-sanctioned way to do this: it is scoped
/// to this window, so it is released automatically if the app is backgrounded
/// or killed, and it cannot leave the device awake after we are gone. That is
/// why it is preferred here over a PowerManager.WakeLock, which would survive
/// us and needs a permission.
class MainActivity : FlutterActivity() {
    private val channelName = "dev.deaddrop/screen_wake"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        // addFlags must run on the UI thread; method channel
                        // calls already arrive there.
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "allowSleep" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
