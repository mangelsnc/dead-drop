/// desktop_scanner_view.dart — the camera view used on Linux and Windows.
///
/// `MobileScanner` is a widget: hand it a controller and it shows the
/// camera and reports codes. The desktop path has no such widget, so this
/// is it — same shape, same contract, so the receive and send pages can
/// pick one or the other without knowing how either works.
library;

import 'package:flutter/material.dart';

import '../src/desktop_camera.dart';
import 'theme.dart';

/// Shows a desktop camera and reports the QR payloads it reads.
///
/// Opens the camera on mount and releases it on dispose, so a page that
/// stops showing this widget has released the camera by the time the next
/// screen appears — a camera left open stays unavailable to every other
/// application on the machine.
class DesktopScannerView extends StatefulWidget {
  const DesktopScannerView({
    super.key,
    required this.onDetect,
    this.scanner,
  });

  /// Called for each payload read. May fire many times for the same code:
  /// the sender repeats frames by design and the caller decides what is
  /// new.
  final void Function(String payload) onDetect;

  /// Injectable for tests; production creates its own.
  final DesktopCameraScanner? scanner;

  @override
  State<DesktopScannerView> createState() => _DesktopScannerViewState();
}

class _DesktopScannerViewState extends State<DesktopScannerView> {
  late final DesktopCameraScanner _scanner;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _scanner = widget.scanner ?? DesktopCameraScanner();
    _start();
  }

  Future<void> _start() async {
    try {
      await _scanner.start();
      _scanner.payloads.listen(
        widget.onDetect,
        onError: (Object e) {
          if (mounted) setState(() => _error = e.toString());
        },
      );
      // Frame counts and the aspect ratio both arrive after start().
      _scanner.activity.listen((_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _ready = true);
    } on DesktopCameraException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off,
                  color: DeadDropColors.error, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: DeadDropColors.error),
              ),
            ],
          ),
        ),
      );
    }

    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    // The preview is drawn at the camera's own ratio. Stretching it to
    // fill a box of some other shape distorts the image — ugly, and
    // worse, a squashed QR is harder to aim at.
    final ratio = _scanner.aspectRatio;
    final preview = ratio == null
        ? _scanner.preview()
        : AspectRatio(aspectRatio: ratio, child: _scanner.preview());

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: preview),
        // Says whether the camera is actually looking at anything. Without
        // it a working camera that sees no code is indistinguishable from
        // one that never started.
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _scanner.framesDecoded > 0
                  ? 'Reading — ${_scanner.framesDecoded} codes so far'
                  : 'Looking… ${_scanner.framesSeen} frames checked',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
