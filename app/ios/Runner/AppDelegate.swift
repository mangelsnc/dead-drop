import Flutter
import UIKit

/// Keeps the screen on while a transfer runs.
///
/// The sender displays animated QR codes and the receiver points a camera at
/// them; a screen that dims or locks mid-transfer stalls it, and locking the
/// sender's phone hides what the other device is reading.
///
/// `isIdleTimerDisabled` is the sanctioned API for this on iOS. It is scoped
/// to the app: the system restores normal behaviour as soon as we are
/// backgrounded or terminated, so a lock cannot outlive us and drain a
/// device whose owner may have no way to charge it.
///
/// Brightness is also set for the transfer, because the screen is the
/// transmission medium and how bright it is changes how the other device's
/// camera exposes. A transfer to a Logitech StreamCam failed because the
/// sending screen was bright enough that the webcam stopped down and the
/// code's dark modules washed out.
///
/// Unlike Android's window-scoped `screenBrightness`, `UIScreen.brightness`
/// is a device-wide setting that iOS does NOT restore by itself, so the
/// level in use when a transfer starts is saved and put back on release.
/// Without that, a transfer would permanently change a setting the user
/// never touched.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private let screenWakeChannelName = "dev.deaddrop/screen_wake"

  /// The device brightness in force before a transfer pinned it, so it can
  /// be restored. Nil when no transfer is holding it.
  private var brightnessBeforeTransfer: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: screenWakeChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "keepAwake":
          UIApplication.shared.isIdleTimerDisabled = true
          // Saved only on the first call, so a repeated keepAwake cannot
          // overwrite the user's own level with our own.
          if self?.brightnessBeforeTransfer == nil {
            self?.brightnessBeforeTransfer = UIScreen.main.brightness
          }
          let args = call.arguments as? [String: Any]
          let level = (args?["level"] as? Double) ?? 1.0
          UIScreen.main.brightness = CGFloat(min(max(level, 0.0), 1.0))
          result(nil)
        case "allowSleep":
          UIApplication.shared.isIdleTimerDisabled = false
          if let previous = self?.brightnessBeforeTransfer {
            UIScreen.main.brightness = previous
            self?.brightnessBeforeTransfer = nil
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
