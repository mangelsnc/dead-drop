/// Does the code this screen draws carry a quiet zone around it?
///
/// A QR's margin is part of the code. A decoder locates a code by
/// finding the 1:1:3:1:1 run through each of the three finder patterns,
/// and the outer ring of every finder is dark, so without a light band
/// around it the finders merge into whatever the code is sitting on and
/// no scan line produces that run. The failure is total and silent:
/// zxing raises NotFoundException, which says the code was never
/// located — not that it was located and misread.
///
/// This already shipped once. `37d2117` replaced `QrImageView` with a
/// `QrPainter` rasterised straight onto a canvas, to cut the 7,921
/// `drawRect` calls a dense code costs. `QrPainter` paints only the
/// modules; the margin lives in `QrImageView`'s own wrapper, which that
/// path no longer went through. The codes came out edge to edge. 547
/// tests passed, because not one of them looked at the drawn pixels.
///
/// It was reverted for an unrelated reason 33 minutes later, but a
/// build carrying it reached a phone, and every receiver pointed at
/// that phone read nothing at all: a MacBook Pro M3 took 1082 frames
/// and found no code in any of them, and a Slimbook did the same.
/// Rasterising the code is still a reasonable optimisation and someone
/// will try it again. This is the test that will fail when they do.
///
/// It renders the real sending view and measures the pixels, because
/// the bug was invisible to every test that did not.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/send/send_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:qr/qr.dart';

/// `flutter_secure_storage` talks to the OS keychain over a platform
/// channel the `flutter_tester` VM does not have, and startEmitting
/// loads the device identity through it.
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      data[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      data[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();
}

Uint8List _file() => Uint8List.fromList(List.generate(4096, (i) => i % 256));

Uint8List _receiverKey() => Uint8List.fromList(List.filled(32, 7));

/// A Redmi Note 14 in portrait, in logical pixels. The device the
/// failure was reported from, and the hard case: a phone emitting is
/// width-bound, so the code is as large as it can be and the margin has
/// the least room to survive.
const _redmiPortrait = Size(393, 873);

/// A 1280x800 laptop, where the same code is drawn far larger.
const _desktopWindow = Size(1280, 800);

/// The standard's quiet zone, in modules, on every side.
///
/// Four is what ISO/IEC 18004 requires. The test asserts against it
/// directly rather than against a pixel count, because a pixel count
/// would have to be recalculated for every screen size and would stop
/// meaning anything the moment someone changed one.
const int _requiredQuietModules = 4;

/// Above this, a pixel counts as part of the light field.
///
/// The drawn code is pure white (255) and pure black (0); the midpoint
/// leaves room for the anti-aliased edge of a module without letting a
/// grey band pass as a margin.
const int _lightThreshold = 128;

/// Captured pixels per logical pixel.
///
/// The margin has to be measured finer than the error it guards against.
/// The painter's rounding cost the Redmi 0.67 px of margin; at one
/// captured pixel per logical pixel that is inside the measurement's own
/// resolution, and the shortfall would pass.
const double _captureRatio = 4;

const _ecLevels = {
  'L': QrErrorCorrectLevel.L,
  'M': QrErrorCorrectLevel.M,
  'Q': QrErrorCorrectLevel.Q,
  'H': QrErrorCorrectLevel.H,
};

/// Grabs the drawn QR as pixels.
///
/// The widget is private, so the test reads the `RepaintBoundary` the
/// sending view wraps it in, and checks that what came back is the
/// size the notifier says the code was given. Without that check a
/// boundary around some other widget would be measured in silence, and
/// a margin found on the wrong thing proves nothing.
Future<({List<List<int>> luminance, int size})> _captureCode(
  WidgetTester tester,
  double expectedSize,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('qr-code-boundary')),
  );
  expect(boundary.size.width, closeTo(expectedSize, 1.0),
      reason: 'the captured boundary is ${boundary.size.width}px wide but '
          'the sending view reports drawing the code at ${expectedSize}px, '
          'so this is not the code');
  // Rasterising is real async work on the engine, not fake-async the
  // test clock can drive, so it has to run outside the pump guard.
  final (bytes, w, h) = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _captureRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = (data!.buffer.asUint8List(), image.width, image.height);
    image.dispose();
    return result;
  }))!;

  final rows = <List<int>>[];
  for (var y = 0; y < h; y++) {
    final row = <int>[];
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      // Composited over white. The container's rounded corners are
      // transparent, and their anti-aliased edge is premultiplied, so
      // read raw they come out dark and pass for a module.
      final under = 255 - bytes[i + 3];
      row.add(((bytes[i] + under) * 30 +
              (bytes[i + 1] + under) * 59 +
              (bytes[i + 2] + under) * 11) ~/
          100);
    }
    rows.add(row);
  }
  return (luminance: rows, size: w);
}

/// The light margin on each side of the drawn code, in captured pixels.
///
/// The code's extent is the bounding box of every dark pixel. That is
/// exact for a QR, because three of its corners are finder patterns,
/// whose outer rings are dark: the box runs from finder edge to finder
/// edge on every side. Scanning a single row or column instead counts
/// any light data modules that happen to start that line as margin --
/// which reported "53 px left, 21 px right" for a code whose margins
/// were 25 on all four sides.
({int left, int right, int top, int bottom, int codeWidth}) _marginsOf(
  List<List<int>> lum,
) {
  final h = lum.length;
  final w = lum[0].length;
  var minX = w, maxX = -1, minY = h, maxY = -1;
  for (var y = 0; y < h; y++) {
    final row = lum[y];
    for (var x = 0; x < w; x++) {
      if (row[x] > _lightThreshold) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  return (
    left: minX,
    right: w - 1 - maxX,
    top: minY,
    bottom: h - 1 - maxY,
    codeWidth: maxX - minX + 1,
  );
}

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  Future<void> check(
    WidgetTester tester,
    Size window,
    String device,
  ) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [sodiumProvider.overrideWithValue(sodium)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const SendPage()),
      ),
    );
    // Fixed pumps rather than pumpAndSettle: the identity card holds a
    // running animation, so settling never completes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final notifier = container.read(sendProvider.notifier);
    notifier.loadBytes('payload.bin', _file());
    notifier.setReceiverPk(_receiverKey());
    await notifier.startEmitting();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final state = container.read(sendProvider);
    final drawnSize = state.qrDisplaySizePx;
    final chunkSize = state.chunkSize;
    final ecLevel = state.ecLevel;
    final payload = state.currentQrData!;

    final captured = await _captureCode(tester, drawnSize);

    // The emitter runs on a periodic timer that never stops on its own,
    // and a widget test with a pending timer never finishes.
    notifier.stopEmitting();
    await tester.pump();

    expect(state.qrDisplaySizeMeasured, isTrue,
        reason: 'the sending view never reported a measurement, so this '
            'test is looking at something other than the drawn code');

    final margins = _marginsOf(captured.luminance);
    final worst = [margins.left, margins.right, margins.top, margins.bottom]
        .reduce((a, b) => a < b ? a : b);

    // The pitch is the drawn code's width over its module count, and the
    // count comes from the payload actually on screen, asked of the `qr`
    // package directly. The frame on screen when a transfer starts is
    // the bootstrap, far shorter than a data frame, so the configured
    // chunk size describes a code that is not the one in this image.
    final modules = QrImage(QrCode.fromData(
      data: payload,
      errorCorrectLevel: _ecLevels[ecLevel]!,
    )).moduleCount;
    final pitch = margins.codeWidth / modules;
    final quietModules = worst / pitch;

    // One captured pixel is the measurement's resolution, and the edge
    // of a module drawn at a fractional position can land either side.
    final tolerance = 1 / pitch;

    expect(quietModules,
        greaterThanOrEqualTo(_requiredQuietModules - tolerance),
        reason: 'on $device the code is drawn with only '
            '${quietModules.toStringAsFixed(1)} modules of quiet zone '
            '(${worst / _captureRatio}px at '
            '${(pitch / _captureRatio).toStringAsFixed(2)}px per module, '
            'measured off the drawn code; the transfer is configured for '
            '$chunkSize B at EC-$ecLevel). '
            'ISO/IEC 18004 requires $_requiredQuietModules. Below that '
            'the dark outer ring of each finder pattern merges with '
            'whatever the code sits on, no scan line yields the '
            '1:1:3:1:1 run zxing looks for, and every receiver reports '
            'NotFoundException on every frame — which is exactly what '
            'happened when 37d2117 rasterised the code without its '
            'margin.');
  }

  testWidgets('a phone draws the code with its quiet zone', (tester) async {
    await check(tester, _redmiPortrait, 'a Redmi Note 14');
  });

  testWidgets('a laptop draws the code with its quiet zone', (tester) async {
    // The same guard on a screen where the code is much larger. A fix
    // that hard-coded a pixel margin would pass on one of these two and
    // fail on the other.
    await check(tester, _desktopWindow, 'a 1280x800 laptop');
  });
}
