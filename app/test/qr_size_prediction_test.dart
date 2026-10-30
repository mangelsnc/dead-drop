/// Does the size the handshake negotiates against match the size the
/// code is actually drawn at?
///
/// The handshake arrives before any QR exists, so the configuration page
/// predicts how big one will be and the negotiation uses that. A
/// prediction that is too generous is worse than no prediction at all:
/// it agrees to a chunk size this screen cannot draw, and the user finds
/// out from a warning *after* pressing Start, which is the exact failure
/// the prediction was added to prevent. Reported twice from a Redmi Note
/// 14 accepting 512 bytes from a Mac.
///
/// The unit tests in emission_hint_wiring_test.dart feed
/// predictQrDisplaySize a number by hand, so they can only prove the
/// negotiation uses what it is given. This one pumps both real screens
/// and compares what each one computes, which is the part that was
/// wrong.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/send/send_page.dart';
import 'package:dead_drop/ui/theme.dart';

/// `flutter_secure_storage` talks to the OS keychain over a platform
/// channel that does not exist in the `flutter_tester` VM, and
/// startEmitting loads the device identity through it. Without this the
/// await never returns and the test times out rather than failing.
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

/// A file big enough that the sending view has something to emit.
Uint8List _file() => Uint8List.fromList(List.generate(4096, (i) => i % 256));

/// A receiver public key. Its value does not matter here: nothing
/// decrypts in this test, the handshake only has to complete.
Uint8List _receiverKey() => Uint8List.fromList(List.filled(32, 7));

/// A Redmi Note 14 in portrait, in logical pixels: 1080x2400 at the
/// device pixel ratio Flutter reports for it. This is the device the
/// failure was reported from, so it is the one the test uses.
const _redmiPortrait = Size(393, 873);

/// A Mac Studio's window, for the contrast case: a screen that really
/// can draw a dense code must not be cut down by a pessimistic guess.
const _desktopWindow = Size(1280, 800);


Future<ProviderContainer> _pumpSendPage(
  WidgetTester tester,
  SodiumSumo sodium,
  Size size,
) async {
  tester.view.physicalSize = size;
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
  return container;
}

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  testWidgets('the predicted size is not larger than the drawn size',
      (tester) async {
    final container = await _pumpSendPage(tester, sodium, _redmiPortrait);
    final notifier = container.read(sendProvider.notifier);

    final predicted = container.read(sendProvider).qrDisplaySizePx;
    expect(predicted, greaterThan(0),
        reason: 'the configuration page must predict something, or the '
            'handshake negotiates against zero again');

    // Now the real thing: put the sending view on screen and let its
    // LayoutBuilder report what the code actually gets.
    notifier.loadBytes('payload.bin', _file());
    notifier.setReceiverPk(_receiverKey());
    await notifier.startEmitting();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final drawn = container.read(sendProvider).qrDisplaySizePx;
    // The emitter runs on a periodic timer that never stops on its own,
    // and a widget test with a pending timer never finishes.
    notifier.stopEmitting();
    await tester.pump();

    expect(container.read(sendProvider).qrDisplaySizeMeasured, isTrue,
        reason: 'the sending view did not report a measurement, so this '
            'test is comparing the prediction against itself');

    expect(predicted, lessThanOrEqualTo(drawn),
        reason: 'the prediction claimed $predicted px but the code is '
            'drawn at $drawn px. A prediction larger than the truth '
            'negotiates a chunk size this screen cannot draw, which is '
            'the bug the prediction exists to prevent: the Redmi '
            'accepted 512 bytes and warned about them after Start.');
  });

  testWidgets('the prediction is not so pessimistic it wastes a big screen',
      (tester) async {
    // The other half. Clamping the prediction to something tiny would
    // pass the test above and make every desktop transfer slower than
    // it needs to be.
    final container = await _pumpSendPage(tester, sodium, _desktopWindow);
    final notifier = container.read(sendProvider.notifier);

    final predicted = container.read(sendProvider).qrDisplaySizePx;

    notifier.loadBytes('payload.bin', _file());
    notifier.setReceiverPk(_receiverKey());
    await notifier.startEmitting();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final drawn = container.read(sendProvider).qrDisplaySizePx;
    notifier.stopEmitting();
    await tester.pump();

    expect(predicted, greaterThan(drawn * 0.75),
        reason: 'the prediction ($predicted px) gives away more than a '
            'quarter of what the screen can really draw ($drawn px), so '
            'a transfer that could run at a larger chunk size will be '
            'negotiated down for no reason');
  });
}
