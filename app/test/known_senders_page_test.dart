/// Tests for the known-senders page
/// (app/lib/ui/senders/known_senders_page.dart).
///
/// The store behind this has supported naming, renaming, listing and
/// forgetting since the TOFU work; nothing reached the last three. This
/// page does, so these tests cover the screen rather than the storage.
///
/// One property matters more than the rest: the list is scoped to the
/// open vault environment. A decoy that showed the real environment's
/// contacts would be exactly the tell the vault exists to avoid.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/tofu_store.dart';
import 'package:dead_drop/ui/senders/known_senders_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/main.dart';

/// In-memory keychain: flutter_secure_storage talks to the OS over a
/// platform channel that does not exist in flutter_tester.
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
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async =>
      data.clear();
}

const _ana = 'aaaaaaaaaaaaaaaa';
const _bruno = 'bbbbbbbbbbbbbbbb';

Widget _wrap(TofuStore store) => ProviderScope(
      overrides: [tofuStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: deadDropTheme(),
        home: const KnownSendersPage(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStoragePlatform.instance = _FakeSecureStorage());

  testWidgets('an empty list explains how senders get here', (tester) async {
    // An empty screen with no explanation reads as broken.
    await tester.pumpWidget(_wrap(TofuStore()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nobody yet'), findsOneWidget);
  });

  testWidgets('shows each sender with its name and code', (tester) async {
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');
    await store.markKnown(_bruno);

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text(_ana), findsOneWidget);
    // An unnamed sender is still listed — it is a real sender, and
    // hiding it would make the list disagree with what the app trusts.
    expect(find.text('Unnamed sender'), findsOneWidget);
    expect(find.text(_bruno), findsOneWidget);
  });

  testWidgets('says a name is not proof of identity', (tester) async {
    // The one claim this page must not let a user make for itself: a
    // name is a local label, not an authenticated fact.
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.textContaining('not proof of identity'), findsOneWidget);
  });

  testWidgets('renaming a sender updates the list', (tester) async {
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ana (work)');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Ana (work)'), findsOneWidget);
    expect(await store.nameFor(_ana), 'Ana (work)');
  });

  testWidgets('naming a sender that had none', (tester) async {
    final store = TofuStore();
    await store.markKnown(_bruno);

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unnamed sender'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bruno');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bruno'), findsOneWidget);
  });

  testWidgets('cancelling a rename changes nothing', (tester) async {
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Wrong');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsOneWidget);
    expect(await store.nameFor(_ana), 'Ana');
  });

  testWidgets('forgetting asks first, and says what it means',
      (tester) async {
    // Forgetting is not destructive to data, but it does mean the next
    // transfer from that person asks for a fingerprint check again. The
    // user should know that before confirming.
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();

    expect(find.textContaining('check their code again'), findsOneWidget);
    expect(await store.isKnown(_ana), isTrue,
        reason: 'nothing happens until the user confirms');

    await tester.tap(find.widgetWithText(FilledButton, 'Forget'));
    await tester.pumpAndSettle();

    expect(await store.isKnown(_ana), isFalse);
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('cancelling a forget keeps the sender', (tester) async {
    final store = TofuStore();
    await store.markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await store.isKnown(_ana), isTrue);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('the decoy environment shows its own contacts, not the real ones',
      (tester) async {
    // The property this page could most easily have broken. A list of
    // real people inside the decoy is exactly the tell the vault exists
    // to avoid.
    await TofuStore(environmentSlot: 0).markKnown(_ana, name: 'Ana');

    await tester.pumpWidget(_wrap(TofuStore(environmentSlot: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsNothing);
    expect(find.textContaining('Nobody yet'), findsOneWidget);
  });
}
