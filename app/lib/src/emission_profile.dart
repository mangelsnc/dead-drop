/// emission_profile.dart — opt-in timing of where a sent frame's time goes.
///
/// Turned off unless the binary was built with
/// `--dart-define=DEADDROP_PROFILE_EMISSION=true`, and the constant is
/// `const`, so in an ordinary build [profileEmission] is a compile-time
/// `false` and the tree shaker drops the recording and the overlay with it.
/// Nothing to remember to take out before a release.
///
/// ## What this exists to answer
///
/// On a Slimbook 14" running Kali, the sending screen reported "2.x of 10
/// fps", and the same ~460 ms per frame whether 10 or 4 were asked for, and
/// whether chunks were 512 or 256 bytes. The event loop is blocked for about
/// half a second per cycle.
///
/// What blocks it is not known. Two candidates share that isolate:
///
///  * **Preparing** the next frame — the fountain encoder producing it and
///    [encodeQrPayload] turning it into the string the QR carries.
///  * **Drawing** it — `QrImageView` searching for a QR version, building the
///    matrix with its Reed-Solomon error correction, and rasterising it. None
///    of that is cached between frames.
///
/// `measuredFps` cannot tell them apart: it timestamps the timer callback,
/// so it sees only that a tick was late, never what made it late. This
/// measures the two separately.
///
/// ## Why drawing is timed with a post-frame callback
///
/// Building a widget does not draw it. `QrImageView`'s cost lands in
/// Flutter's own pipeline after the build method returns, so a stopwatch
/// around the build would report approximately zero and prove nothing. The
/// draw timer therefore starts when the new code is handed to the widget and
/// stops in the frame callback that follows, which is the first moment the
/// pixels exist.
///
/// That interval also contains the rest of the frame — the whole page's
/// layout and paint. On this screen the QR dominates it, but the figure is
/// "the frame this QR was drawn in", not "the QR alone", and the overlay
/// labels it accordingly.
library;

/// Whether this binary records emission timings.
///
/// A `const` so that `if (profileEmission)` is resolved at compile time and
/// a release build contains none of this.
const bool profileEmission =
    bool.fromEnvironment('DEADDROP_PROFILE_EMISSION');

/// Replaces the QR with a blank square of the same size, to find out how
/// much of a frame the code is actually responsible for.
///
/// The first attempt at this problem guessed, and guessed wrong. The
/// sending screen's frame costs about 130 ms on an M3; `QrPainter` issues
/// one `drawRect` per module and a 512-byte chunk is 89×89, so 7,921
/// rectangles looked like the answer. Rendering each code to an image
/// instead — 73× cheaper in a bench — moved the frame from 132.5 ms to
/// 120.0 ms. Nothing.
///
/// Two facts say the modules are not the cost. That change, and this:
/// 256-byte codes cost the same as 512-byte ones (122.8 against 120.0 ms)
/// although they carry far fewer modules. What does not change between
/// them is the area in pixels the code is drawn over, because the QR
/// fills whatever the layout gives it.
///
/// [profileEmission] measures the whole frame, not the QR — it was
/// written that way and says so. Nothing has yet separated the two. With
/// this flag the screen draws everything except the code, so the
/// difference between the two runs is the code's share, measured rather
/// than reasoned about.
///
/// A transfer cannot be received in this mode. It exists to be run for
/// twenty seconds against a profiling build, never shipped.
const bool profileWithoutQr =
    bool.fromEnvironment('DEADDROP_PROFILE_WITHOUT_QR');

/// Microsecond timings for one phase of frame emission, summarised as a
/// median so a single stall cannot move the figure.
///
/// Median rather than mean for the reason `EmissionRate` uses one: a garbage
/// collection pause or a dragged window is not the cost we are hunting, and a
/// mean would let one of them stand in for it.
class PhaseTimings {
  PhaseTimings({this.window = 30});

  /// How many recent samples are kept. Matches `EmissionRate`'s window so
  /// the two figures describe the same stretch of the transfer.
  final int window;

  final List<int> _micros = [];

  /// How many samples have been taken in total, not just those still in the
  /// window. Shown so a reader can tell a settled figure from a first guess.
  int get count => _count;
  int _count = 0;

  void record(int micros) {
    if (micros < 0) return;
    _count++;
    _micros.add(micros);
    if (_micros.length > window) _micros.removeAt(0);
  }

  /// The median sample in milliseconds, or null before there is one.
  double? get medianMillis {
    if (_micros.isEmpty) return null;
    final sorted = [..._micros]..sort();
    final mid = sorted.length ~/ 2;
    final micros = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    return micros / 1000;
  }

  /// The worst sample still in the window, in milliseconds.
  ///
  /// A median hides the stalls, and a frame rate is set by the slow frames
  /// as much as by the typical one.
  double? get worstMillis {
    if (_micros.isEmpty) return null;
    return _micros.reduce((a, b) => a > b ? a : b) / 1000;
  }

  void reset() {
    _micros.clear();
    _count = 0;
  }
}

/// Collects the per-phase timings for the sending screen.
///
/// Create one per transfer; [reset] it when the frame rate changes, for the
/// same reason `EmissionRate` resets, so two different rates are not averaged
/// into one meaningless figure.
class EmissionProfile {
  /// Producing the next frame and encoding its payload: everything inside
  /// the timer callback.
  final PhaseTimings prepare = PhaseTimings();

  /// From handing a new code to the widget until the frame carrying it has
  /// been drawn.
  final PhaseTimings draw = PhaseTimings();

  DateTime? _drawStartedAt;

  /// Records how long the timer callback took to build the next payload.
  void recordPrepare(Duration elapsed) {
    prepare.record(elapsed.inMicroseconds);
  }

  /// Notes that a new code was handed to the display.
  ///
  /// Called from the timer callback, after the state carrying the new code
  /// has been published.
  void markDrawStart({DateTime? at}) {
    _drawStartedAt = at ?? DateTime.now();
  }

  /// Notes that the frame carrying it has been drawn.
  ///
  /// Ignored when no draw is outstanding, so a rebuild triggered by
  /// something other than a new code — a window resize, say — does not
  /// invent a sample.
  void markDrawEnd({DateTime? at}) {
    final started = _drawStartedAt;
    if (started == null) return;
    _drawStartedAt = null;
    draw.record((at ?? DateTime.now()).difference(started).inMicroseconds);
  }

  void reset() {
    prepare.reset();
    draw.reset();
    _drawStartedAt = null;
  }

  /// One line for the on-screen overlay, or null before anything is known.
  ///
  /// Deliberately terse: it is read off a photograph of a laptop screen.
  /// `prepare` and `draw` are the two halves of a frame; `n` is how many
  /// frames have been through each.
  String? get summary {
    final p = prepare.medianMillis;
    final d = draw.medianMillis;
    if (p == null && d == null) return null;
    return 'prepare ${_ms(p)} (max ${_ms(prepare.worstMillis)}, '
        'n=${prepare.count})  ·  '
        'draw ${_ms(d)} (max ${_ms(draw.worstMillis)}, n=${draw.count})';
  }

  static String _ms(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} ms';
}
