/// The receive screen's layout adapts instead of growing downwards.
///
/// Reported from a real transfer: when the sender is new, the block asking
/// whether to trust them is inserted between the camera and the progress
/// bar, pushing the progress off the bottom of a phone screen. Two changes
/// answer that, and this file pins both.
///
/// On a narrow screen the handshake QR folds away once the camera is
/// running — its job ended when the sender scanned it. On a wide one the
/// camera and the reporting blocks sit in separate columns, so one can
/// never displace the other.
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

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sodiumProvider.overrideWithValue(sodium)],
        child: MaterialApp(
          theme: deadDropTheme(),
          home: const ReceivePage(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a narrow screen keeps one column', (tester) async {
    await pumpAt(tester, const Size(400, 900));
    expect(find.byType(Row), findsWidgets);
    // The handshake step is visible before scanning starts, on any width:
    // it is how the sender addresses the file to this device.
    expect(find.text('Your public key'), findsOneWidget);
  });

  testWidgets('a wide screen splits the page into two columns',
      (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    // The two-column layout puts the camera side and the reporting side in
    // Expanded children of one Row. Narrow builds never do this.
    final rows = tester.widgetList<Row>(find.byType(Row));
    final split = rows.any((r) =>
        r.children.length == 3 &&
        r.children.first is Expanded &&
        r.children.last is Expanded);
    expect(split, isTrue,
        reason: 'on a wide window the sender block must not be able to push '
            'the progress bar down, because they are in different columns');
  });

  testWidgets('progress is reported inside the scan step, not after it',
      (tester) async {
    // It was a card of its own numbered 3, which on a phone fell below
    // the fold; hoisting it above the camera then put a 3 above the 2.
    // While a transfer runs, the progress belongs with the camera.
    await pumpAt(tester, const Size(400, 900));

    // Before a session there is no progress and no result card.
    expect(find.text('Received file'), findsNothing);
    expect(find.text('Progress'), findsNothing);

    // Step 2 follows step 1, in plain order, with nothing hoisted.
    final scanY = tester.getTopLeft(find.text('Scan sender QR codes')).dy;
    final keyY = tester.getTopLeft(find.text('Your public key')).dy;
    expect(scanY, greaterThan(keyY));
  });

  testWidgets('the page scrolls rather than overflowing on a short screen',
      (tester) async {
    await pumpAt(tester, const Size(400, 600));
    expect(tester.takeException(), isNull,
        reason: 'a RenderFlex overflow here would be a visible yellow bar '
            'across a screen someone is trying to use');
  });
}
