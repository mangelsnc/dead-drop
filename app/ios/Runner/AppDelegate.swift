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
@main
@objc class AppDelegate: FlutterAppDelegate {
  private let screenWakeChannelName = "dev.deaddrop/screen_wake"

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
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "keepAwake":
          UIApplication.shared.isIdleTimerDisabled = true
          result(nil)
        case "allowSleep":
          UIApplication.shared.isIdleTimerDisabled = false
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
