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
///
/// It is not enough on its own. The flag stops the screen locking but not
/// adaptive brightness from dimming it, and here the screen is the
/// transmission medium: dimming it destroys the contrast the other device's
/// camera is reading. Reported from a sending phone that kept darkening every
/// minute or so mid-transfer. So the window brightness is pinned for as long
/// as the transfer runs, and handed back to the system afterwards.
///
/// Pinned to a caller-supplied level rather than always to full. Full is the
/// right default against a phone camera, but it is not right against every
/// camera: a transfer to a Logitech StreamCam failed because the sending
/// phone's screen was bright enough that the webcam's auto-exposure stopped
/// down and the code's dark modules washed out to grey. Brightness is the
/// one variable the sender controls that changes how the other device's
/// exposure behaves, so it has to be reachable.
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
                        // Clamped here as well as on the Dart side. A value
                        // outside 0..1 is not a dimmer screen, it is
                        // BRIGHTNESS_OVERRIDE_NONE (-1) or undefined
                        // behaviour, and this is the last place that can
                        // stop one reaching the window.
                        val level = (call.argument<Double>("level") ?: 1.0)
                            .coerceIn(0.0, 1.0)
                            .toFloat()
                        window.attributes = window.attributes.apply {
                            screenBrightness = level
                        }
                        result.success(null)
                    }
                    "allowSleep" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        // BRIGHTNESS_OVERRIDE_NONE: give the system its
                        // own brightness back rather than leaving the
                        // screen pinned at full after a transfer.
                        window.attributes = window.attributes.apply {
                            screenBrightness =
                                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
