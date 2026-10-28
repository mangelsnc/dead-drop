/// desktop_scanner_view.dart — the camera view used on Linux and Windows.
///
/// `MobileScanner` is a widget: hand it a controller and it shows the
/// camera and reports codes. The desktop path has no such widget, so this
/// is it — same shape, same contract, so the receive and send pages can
/// pick one or the other without knowing how either works.
library;

import 'package:flutter/material.dart';

import '../src/capability_hint.dart';
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
    this.onMeasured,
    this.scanner,
  });

  /// Called for each payload read. May fire many times for the same code:
  /// the sender repeats frames by design and the caller decides what is
  /// new.
  final void Function(String payload) onDetect;

  /// Called when this camera has been measured well enough to describe.
  ///
  /// Fires as the reading improves, so the last call before the scanner
  /// closes is the best one. The caller decides what to do with it —
  /// receive_page stores it, so the next handshake QR can tell the
  /// sender what this camera manages.
  final void Function(CameraCapability)? onMeasured;

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
        final measured = _scanner.capability;
        if (measured != null) widget.onMeasured?.call(measured);
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

  /// What to say under the bar. Names the situation, not a raw number.
  String _statusLine() {
    final rate = _scanner.recentDecodeRate;
    if (rate == null) {
      return 'Looking… ${_scanner.framesSeen} frames checked';
    }
    if (rate >= 0.6) return 'Good — hold it there';
    if (rate >= 0.3) return 'Reading — try moving a little closer';
    if (rate > 0) return 'Weak — adjust distance or lighting';
    return 'Not reading — point at the other screen';
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

    // The preview keeps the camera's own ratio and fills the box,
    // cropping whatever does not fit rather than letterboxing.
    //
    // Fitting instead left black bands above and below on a phone, whose
    // sensor is far taller than the wide box this sits in, and shrank the
    // image to the height of the band — so the QR the user is aiming at
    // got smaller the more space was wasted. Cropping costs the edges of
    // the frame, which hold nothing: the code is in the middle, which is
    // where the user points it.
    //
    // Stretching is still not an option. A squashed QR is harder to aim
    // at, and the decoder works on the frame rather than this widget, so
    // distortion here would mislead without helping.
    final ratio = _scanner.displayAspectRatio;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Sized against the box this actually occupies rather than
        // wrapped in a FittedBox. A FittedBox needs its child to have
        // real dimensions to scale from, and a camera preview reports
        // none — handing it a 1px-tall SizedBox made the preview vanish
        // entirely on Android.
        // The preview keeps whatever shape it has and is scaled to cover
        // the box, with the overflow clipped.
        //
        // FittedBox is doing the work rather than arithmetic on a
        // reported ratio, because that ratio cannot be trusted: on
        // Android the plugin has already rotated the image, so the
        // sensor's numbers describe something other than what is on
        // screen. Three attempts at computing the right size from them
        // produced, in order, black bands, a one-pixel preview, and a
        // horizontally stretched one. Letting the widget keep its own
        // aspect and only scaling it needs none of that to be right.
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              // The box must carry the ratio of the image AS DISPLAYED.
              // A camera preview is a Texture with no intrinsic size, so
              // it does not keep any shape of its own — it fills whatever
              // box it is given, and a wrong one stretches it. Sizing
              // this from the sensor's ratio put a portrait image into a
              // landscape box, which is the widening that was reported.
              width: 1000,
              height: ratio == null ? 1000 : 1000 / ratio,
              child: _scanner.preview(),
            ),
          ),
        ),
        // How well the camera is placed, as a bar rather than a number.
        //
        // Aim, distance and focus all show up in one figure: the share of
        // recent frames that held a readable code. Users were working
        // this out by watching the frame counter and moving the camera
        // until it sped up; this says it directly.
        //
        // A rolling window, so moving closer shows an effect within a
        // second or two. A running total would keep reporting a bad
        // start long after the aim was fixed.
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QualityBar(rate: _scanner.recentDecodeRate),
                const SizedBox(height: 6),
                Text(
                  _statusLine(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                // What the camera reported, so a stretched preview can be
                // diagnosed from a screenshot instead of guessed at.
                Text(
                  _scanner.debugGeometry,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A red-to-green bar showing how well the camera is reading.
///
/// Colour and length both carry the value, so it works for someone who
/// cannot tell red from green — the two differ in lightness as well as
/// hue, which is why this is amber in the middle rather than a red/green
/// pair alone.
class _QualityBar extends StatelessWidget {
  const _QualityBar({required this.rate});

  /// Share of recent frames read, or null before enough are known.
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final value = rate ?? 0;
    final colour = rate == null
        ? Colors.white24
        : Color.lerp(
            const Color(0xFFE53935), // red
            const Color(0xFF43A047), // green
            // Squared so the bar reaches green only when reading is
            // genuinely good: a camera at 50% is usable but not where
            // the user should stop adjusting.
            (value * value).clamp(0.0, 1.0),
          )!;

    return SizedBox(
      width: 180,
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: value.clamp(0.05, 1.0),
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation<Color>(colour),
        ),
      ),
    );
  }
}
