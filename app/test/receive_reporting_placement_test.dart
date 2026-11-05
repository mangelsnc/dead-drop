/// What the receive screen has to say reaches the person reading it.
///
/// Two failures reported from a real macOS transfer on 2026-11-05, both
/// about where the screen puts the things it most needs read.
///
/// **An error moves the whole page.** The reporting column is built only
/// when it has content, so the page is one centred column until something
/// goes wrong and two columns afterwards. A rejected session made every
/// card on screen jump and shrink at the moment the user was trying to
/// read why — reported as "it looked broken".
///
/// **The reporting column is not where the user is looking.** While
/// scanning, the camera has their attention, and a prompt in a separate
/// column beside it goes unread however large it is. The error in the
/// report was at the top of the window in red and was still missed; so
/// was the unknown-sender prompt before it, which left a transfer sitting
/// at nothing with no visible reason. A question that blocks decoding has
/// to be answered where the camera is.
library;

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/receive/receive_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  late ProviderContainer container;

  Future<void> pumpWide(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(
      overrides: [sodiumProvider.overrideWithValue(sodium)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: deadDropTheme(),
          home: const ReceivePage(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Where the handshake card sits, which is what the user is looking at
  /// before anything goes wrong.
  Rect keyCard(WidgetTester tester) => tester.getRect(
        find
            .ancestor(
              of: find.text('Your public key'),
              matching: find.byType(Card),
            )
            .first,
      );

  testWidgets('an error does not move the rest of the page', (tester) async {
    await pumpWide(tester);
    final before = keyCard(tester);

    // The failure the user hit: a sender addressing the session to a
    // different receiver's key.
    container.read(receiveProvider.notifier).debugSetError(
        'Session rejected: Session not addressed to this receiver');
    await tester.pump();

    final after = keyCard(tester);
    expect(
      after,
      before,
      reason: 'reporting an error must not relayout what it reports about',
    );

    // And it must still be reported. A layout that stopped moving
    // because it stopped showing the error would pass the assertion
    // above for the worst possible reason.
    expect(
      find.textContaining('not addressed to this receiver'),
      findsOneWidget,
    );
  });

  testWidgets('an error is reported in the column holding the camera',
      (tester) async {
    // The reason the first report said "it looked broken": the message
    // was in the other column, away from the camera the user was
    // watching. Being large and red was not enough.
    await pumpWide(tester);
    container.read(receiveProvider.notifier).debugSetError(
        'Session rejected: Session not addressed to this receiver');
    await tester.pump();

    final scanX =
        tester.getRect(find.text('Scan sender QR codes')).center.dx;
    final errorX = tester
        .getRect(find.textContaining('not addressed to this receiver'))
        .center
        .dx;
    final pageWidth = tester.getSize(find.byType(Scaffold)).width;

    expect(
      (errorX - scanX).abs(),
      lessThan(pageWidth / 4),
      reason: 'the error belongs beside the step it is about, not in a '
          'separate column the user is not looking at',
    );
  });
}
