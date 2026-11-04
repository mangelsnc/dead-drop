/// frame_dump.dart — writing camera frames to disk, for diagnosis only.
///
/// Turned off unless the binary was built with
/// `--dart-define=DEADDROP_DUMP_FRAMES=true`, and [dumpFrames] is `const`,
/// so an ordinary build resolves it to a compile-time `false` and the tree
/// shaker removes this and every call to it. Nothing to remember to take
/// out before a release.
///
/// ## Why this is gated harder than the emission profiler
///
/// That one writes numbers to the screen. This writes photographs of
/// whatever the camera is pointed at to the filesystem, where they stay
/// after the app closes. DeadDrop's whole argument is that it moves data
/// between two devices and leaks nothing anywhere else, and a build that
/// quietly saved camera images would contradict it in the one way a
/// reviewer would be right to care about.
///
/// So: off by default, compile-time removed, and when it is on the app
/// says so on screen rather than doing it silently.
///
/// ## What it is for
///
/// macOS receiving reported `bgra8888 · got 1082 · decoded 1082 · read 0`
/// on 2026-11-04 — the supported pixel format, every frame reaching the
/// decoder, no frame the converter failed to read, ample density, and not
/// one code found. The same camera reads the receiver's handshake QR.
///
/// What separates those two cases is that a handshake is one still code
/// and a fountain is codes changing twelve times a second. A camera
/// exposing for 1/30 s against a display changing every 1/12 s can
/// capture a blend of two codes: a sharp image of something that was
/// never shown. No counter can see that, and no amount of pointing the
/// camera better fixes it. Looking at the frames can tell.
library;

import 'dart:io';
import 'dart:typed_data';

/// Whether this binary writes camera frames to disk.
const bool dumpFrames = bool.fromEnvironment('DEADDROP_DUMP_FRAMES');

/// How many frames to keep. Enough to see a pattern, few enough that a
/// diagnostic run cannot fill a disk.
const int kMaxDumpedFrames = 40;

/// Writes camera frames as PPM files, which need no encoder.
///
/// PPM because it is a header and raw bytes: no image library, no new
/// dependency, and nothing that could make a network call. Preview opens
/// them on macOS; so does GIMP, ImageMagick and anything else.
class FrameDumper {
  FrameDumper(this.directory);

  /// Where the frames go. Named by the caller so the UI can show it.
  final String directory;

  int _written = 0;

  /// How many frames have been written, for the on-screen notice.
  int get written => _written;

  /// Whether this has written all it will write.
  bool get isFull => _written >= kMaxDumpedFrames;

  /// Writes one frame, or does nothing once [kMaxDumpedFrames] is reached.
  ///
  /// Takes the already-converted ARGB pixels rather than the camera's own
  /// buffer, so what lands on disk is exactly what the decoder was given —
  /// a dump of the camera's raw format would show a correct image while
  /// the decoder saw a broken one, which is the failure this is meant to
  /// catch.
  Future<void> write(Int32List argb, int width, int height) async {
    if (!dumpFrames || isFull) return;
    final index = _written;
    _written++;

    // P6: binary RGB, one byte per channel, maximum value 255.
    final header = 'P6\n$width $height\n255\n';
    final bytes = Uint8List(header.length + width * height * 3);
    bytes.setRange(0, header.length, header.codeUnits);

    var out = header.length;
    for (var i = 0; i < argb.length; i++, out += 3) {
      final pixel = argb[i];
      bytes[out] = (pixel >> 16) & 0xFF;
      bytes[out + 1] = (pixel >> 8) & 0xFF;
      bytes[out + 2] = pixel & 0xFF;
    }

    final name = index.toString().padLeft(3, '0');
    try {
      await File('$directory/frame-$name.ppm').writeAsBytes(bytes);
    } on FileSystemException {
      // A diagnostic that cannot write is not a reason to stop scanning.
    }
  }
}
