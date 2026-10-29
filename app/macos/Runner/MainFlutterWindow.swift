import Cocoa
import FlutterMacOS

/// The window DeadDrop opens in.
///
/// The size is not cosmetic here: the window decides how large a QR the
/// sending screen can draw, and that decides how many bytes fit in each
/// code. A small window negotiates itself down to the smallest chunk
/// size, which for a 1 MB file is about 5,000 codes against 1,250 — the
/// difference between roughly sixteen minutes and three.
///
/// The nib opened this at 800x600, where the sender falls to 256-byte
/// chunks. Linux and Windows both start at 1280x720; this matches them,
/// and sets a floor so the window cannot be dragged below what the
/// layout needs.
class MainFlutterWindow: NSWindow {
  /// Matches gtk_window_set_default_size in linux/my_application.cc and
  /// the Size in windows/runner/main.cpp.
  private static let defaultContentSize = NSSize(width: 1280, height: 720)

  /// Below this the send screen cannot draw a code worth scanning.
  private static let minimumContentSize = NSSize(width: 960, height: 640)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.contentMinSize = MainFlutterWindow.minimumContentSize
    // Only on first run: once someone has sized the window themselves,
    // macOS restores that and overriding it would be rude.
    if !self.setFrameUsingName(self.frameAutosaveName) {
      self.setContentSize(MainFlutterWindow.defaultContentSize)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
