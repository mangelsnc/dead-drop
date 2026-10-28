import 'package:dead_drop/src/mobile_camera_measure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A clock the test drives, so rates are exact rather than racing a
  /// real stopwatch.
  late DateTime clock;
  MobileCameraMeasure build() =>
      MobileCameraMeasure(now: () => clock);

  setUp(() => clock = DateTime(2026, 1, 1, 12));

  void detect(MobileCameraMeasure m, int count,
      {int width = 1280, int height = 720, int msApart = 100}) {
    for (var i = 0; i < count; i++) {
      m.recordDetection(width: width, height: height);
      clock = clock.add(Duration(milliseconds: msApart));
    }
  }

  group('before there is enough to measure', () {
    test('reports nothing after a single detection', () {
      final m = build();
      detect(m, 1);
      expect(m.decodesPerSecond, isNull);
      expect(m.capability, isNull);
    });

    test('reports nothing after nine detections', () {
      final m = build();
      detect(m, 9);
      expect(m.capability, isNull,
          reason: 'one lucky frame must not set the sender\'s parameters');
    });
  });

  group('once measured', () {
    test('a detection every 100 ms reads as about 10 per second', () {
      final m = build();
      // 11 detections, the clock advanced 10 times before the last read.
      detect(m, 11);
      expect(m.decodesPerSecond, closeTo(10, 0.5));
    });

    test('a slower camera reads as a lower rate', () {
      final m = build();
      detect(m, 11, msApart: 250);
      expect(m.decodesPerSecond, closeTo(4, 0.3));
    });

    test('carries the frame resolution it saw', () {
      final m = build();
      detect(m, 11, width: 640, height: 480);
      final cap = m.capability!;
      expect(cap.width, 640);
      expect(cap.height, 480);
    });
  });

  group('honesty about what this path cannot see', () {
    test('decodeRate stays null, because failed frames are invisible here', () {
      final m = build();
      detect(m, 20);
      expect(m.capability!.decodeRate, isNull,
          reason:
              'MobileScanner reports only successful reads. A fabricated '
              'rate would feed suggestEmission and slow a stream that was '
              'reading perfectly well.');
    });
  });

  group('bad input', () {
    test('a zero-sized frame does not become the reported resolution', () {
      final m = build();
      detect(m, 11, width: 1280, height: 720);
      m.recordDetection(width: 0, height: 0);
      final cap = m.capability!;
      expect(cap.width, 1280);
      expect(cap.height, 720,
          reason: 'a zero would read as a tiny camera and slow the sender');
    });

    test('with only zero-sized frames there is no capability at all', () {
      final m = build();
      detect(m, 11, width: 0, height: 0);
      expect(m.capability, isNull);
    });
  });

  test('reset forgets the measurement', () {
    final m = build();
    detect(m, 15);
    expect(m.capability, isNotNull);
    m.reset();
    expect(m.capability, isNull);
    expect(m.detections, 0);
  });
}
