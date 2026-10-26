/// Tests for the technical-text size preference
/// (app/lib/src/text_scale.dart).
///
/// This setting exists because fingerprints and public keys are compared
/// character by character, and 64 hex characters at 13px is hard to read.
/// A comparison nobody can see properly is a security control that does
/// not work — so the thing worth pinning is that the preference survives,
/// stays inside a usable range, and never fails the app when the file is
/// missing or damaged.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/text_scale.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('text_scale_test_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('reading', () {
    test('first run gets the old fixed size', () async {
      // An existing user must see no change until they ask for one.
      expect(await TextScaleStore(directory: dir).read(),
          kDefaultTechnicalTextSize);
    });

    test('a stored size survives a restart', () async {
      await TextScaleStore(directory: dir).write(20);

      // A fresh instance, as on the next launch: no shared cache.
      expect(await TextScaleStore(directory: dir).read(), 20);
    });

    test('a damaged file means the default, not a crash', () async {
      File('${dir.path}/text_scale').writeAsStringSync('not a number');

      expect(await TextScaleStore(directory: dir).read(),
          kDefaultTechnicalTextSize);
    });

    test('an empty file means the default', () async {
      File('${dir.path}/text_scale').writeAsStringSync('');

      expect(await TextScaleStore(directory: dir).read(),
          kDefaultTechnicalTextSize);
    });

    test('an unreachable directory means the default', () async {
      // Nothing here is worth failing a launch over.
      final store = TextScaleStore(
        directory: Directory('${dir.path}/does/not/exist'),
      );

      expect(await store.read(), kDefaultTechnicalTextSize);
    });

    test('a stored value outside the range is brought back in', () async {
      // A hand-edited file, or one written by a future version with a
      // wider range. Rendering a 200px key would break every layout.
      File('${dir.path}/text_scale').writeAsStringSync('200');

      expect(await TextScaleStore(directory: dir).read(),
          kMaxTechnicalTextSize);
    });
  });

  group('writing', () {
    test('clamps above the ceiling', () async {
      final store = TextScaleStore(directory: dir);
      await store.write(999);

      expect(await store.read(), kMaxTechnicalTextSize);
    });

    test('clamps below the floor', () async {
      // The floor is the old fixed size: this control exists to make text
      // bigger, so offering smaller than "already hard to read" would be
      // a trap.
      final store = TextScaleStore(directory: dir);
      await store.write(1);

      expect(await store.read(), kMinTechnicalTextSize);
    });

    test('a failed write still applies for this session', () async {
      // A preference that does not survive a restart is a much smaller
      // problem than an error dialog over a font size.
      final store = TextScaleStore(
        directory: Directory('/proc/nonexistent/unwritable'),
      );

      await store.write(20);

      expect(await store.read(), 20);
    });
  });

  group('stepping', () {
    test('larger and smaller move by one step', () {
      expect(nextLarger(16), 16 + kTechnicalTextSizeStep);
      expect(nextSmaller(16), 16 - kTechnicalTextSizeStep);
    });

    test('stepping stops at the ends rather than wrapping', () {
      expect(nextLarger(kMaxTechnicalTextSize), kMaxTechnicalTextSize);
      expect(nextSmaller(kMinTechnicalTextSize), kMinTechnicalTextSize);
    });

    test('a step that would overshoot lands exactly on the end', () {
      final nearTop = kMaxTechnicalTextSize - (kTechnicalTextSizeStep / 2);

      expect(nextLarger(nearTop), kMaxTechnicalTextSize);
    });

    test('the range is usable: at least four steps wide', () {
      // A control with two positions is not worth the screen space.
      final steps =
          (kMaxTechnicalTextSize - kMinTechnicalTextSize) / kTechnicalTextSizeStep;

      expect(steps, greaterThanOrEqualTo(4));
    });

    test('the floor is the size the app used before this existed', () {
      expect(kMinTechnicalTextSize, kDefaultTechnicalTextSize);
    });
  });
}
