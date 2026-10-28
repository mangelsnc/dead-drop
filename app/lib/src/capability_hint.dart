/// capability_hint.dart — the receiver telling the sender what its camera
/// can actually keep up with.
///
/// The sender picks the frame rate, chunk size and error-correction level,
/// but it is the *receiver's* camera that has to read them, and only the
/// receiver knows what that camera is. A laptop webcam that manages eight
/// usable frames a second will miss most of a stream emitted at twelve, and
/// the sender has no way to find that out: the channel is one-way, so
/// nothing comes back to say "too fast".
///
/// So the receiver measures itself and puts the answer in the handshake QR
/// the sender already scans. No new round trip, no new channel — the
/// information rides along with the public key.
///
/// **A hint, never an instruction.** The sender applies these by default
/// and can override every one. Three reasons: the sender watches its own
/// screen and may see something the measurement missed; a receiver with a
/// bad reading should not be able to degrade someone else's transfer; and
/// the sender is the one carrying the risk of the transfer taking longer.
library;

import 'chunking.dart';

/// What the receiver measured about its own camera.
class CameraCapability {
  const CameraCapability({
    required this.framesPerSecond,
    required this.width,
    required this.height,
    this.decodeRate,
  });

  /// Frames per second the camera actually delivers, not what it claims.
  final double framesPerSecond;

  /// Capture resolution. A low-resolution camera cannot resolve a dense
  /// code however fast it runs.
  final int width;
  final int height;

  /// Share of recent frames that yielded a readable code, when known.
  ///
  /// Null before enough frames have been seen to mean anything. This is
  /// the most honest signal available — it reflects focus, lighting and
  /// the user's steadiness, none of which resolution or frame rate show.
  final double? decodeRate;
}

/// Emission settings the receiver would like the sender to use.
class EmissionHint {
  const EmissionHint({
    required this.fps,
    required this.chunkSize,
    required this.ecLevel,
    required this.reason,
  });

  final double fps;
  final int chunkSize;
  final String ecLevel;

  /// One short sentence the sender can show, so the suggestion is not a
  /// set of numbers that appeared from nowhere.
  final String reason;
}

/// Frame rates the sender offers. Suggesting a value it cannot select
/// would be useless.
const List<double> _fpsOptions = [4, 6, 8, 10, 12, 15, 20];

/// Error-correction levels, weakest to strongest. Stronger correction
/// survives a blurrier image but fits less data per code.
const List<String> _ecLevels = ['L', 'M', 'Q', 'H'];

/// Picks the largest option that does not exceed [value].
double _fpsAtMost(double value) {
  var best = _fpsOptions.first;
  for (final option in _fpsOptions) {
    if (option <= value) best = option;
  }
  return best;
}

/// Suggests emission settings for a camera with these capabilities.
///
/// The reasoning, in order of how much each signal is trusted:
///
/// 1. **Decode rate**, when known. It is measured against real frames and
///    captures everything the other numbers miss. A camera reading fewer
///    than half the frames it sees needs a gentler stream regardless of
///    what its specification says.
/// 2. **Frame rate.** Emitting faster than the camera samples means codes
///    nobody ever sees. The suggestion stays under the measured rate, not
///    at it, because a frame caught mid-refresh is a frame wasted.
/// 3. **Resolution.** A dense QR needs pixels. Below 640x480 the chunk
///    size comes down so each code carries fewer modules.
EmissionHint suggestEmission(CameraCapability camera) {
  // Two thirds of the measured rate. Sampling exactly at the emission
  // rate catches each code at an arbitrary point in its display, often
  // mid-change; leaving headroom means most frames land on a stable code.
  var fps = _fpsAtMost(camera.framesPerSecond * 0.66);

  var chunkSize = kDefaultChunkSize;
  var ec = 'M';
  final reasons = <String>[];

  final pixels = camera.width * camera.height;
  if (pixels > 0 && pixels < 640 * 480) {
    // Not enough pixels to resolve a dense code: fewer bytes per QR means
    // fewer modules, which means each module covers more pixels.
    chunkSize = 256;
    ec = 'Q';
    reasons.add('a low-resolution camera (${camera.width}x${camera.height})');
  }

  final rate = camera.decodeRate;
  if (rate != null && rate < 0.5) {
    // Reading fewer than half the frames. Whatever the cause — focus,
    // lighting, a shaky hand — the stream is too demanding as it is.
    //
    // Slow down and correct harder, but do NOT shrink the chunk. Halving
    // it doubles how many codes must be read, so a camera already missing
    // half of them needs twice as many attempts at the same miss rate:
    // the transfer gets longer, not more reliable. Reported from a phone
    // as "I always have to read about 2.5x the chunk count", with a
    // 653 KB file split into 2614 chunks of 256 B.
    //
    // The fountain code is not the problem — measured overhead is 1.15x
    // at that chunk count. The missing frames are.
    fps = _fpsAtMost(fps * 0.75);
    ec = _ecLevels[(_ecLevels.indexOf(ec) + 1).clamp(0, _ecLevels.length - 1)];
    reasons.add('only ${(rate * 100).round()}% of frames readable so far');
  }

  // Clamp to what the sender can actually select.
  if (!kChunkSizeOptions.contains(chunkSize)) {
    chunkSize = kChunkSizeOptions.first;
  }

  final reason = reasons.isEmpty
      ? 'based on a camera running at '
          '${camera.framesPerSecond.toStringAsFixed(0)} fps'
      : 'because of ${reasons.join(' and ')}';

  return EmissionHint(
    fps: fps,
    chunkSize: chunkSize,
    ecLevel: ec,
    reason: reason,
  );
}
