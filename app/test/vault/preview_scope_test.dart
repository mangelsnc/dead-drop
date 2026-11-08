/// What the vault will show in place, and what it refuses to show.
///
/// Previewing paints from bytes already in memory. Handing a file to a
/// system viewer instead would mean writing plaintext outside the vault,
/// which is the one thing the vault exists to prevent — so the set of
/// previewable types is bounded by what the app can draw itself, and
/// everything else is sent down the export route, which asks first and
/// says what it costs.
///
/// Video, audio and PDF are deliberately outside that set. The players
/// that would render them do not cover GNU/Linux or Windows, and the one
/// package that covers all five platforms pulls an HTTP client into a
/// project whose whole claim is that it has no network code. This test
/// is what holds that decision: if someone adds a viewer, it fails here
/// and they have to come back and change the rule on purpose.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/src/vault/vault_session.dart';
import 'package:dead_drop/src/vault/vault_store.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';

/// A real PDF header, so the type is decided by content and not by the
/// name — the same reason the preview reads magic bytes first.
final Uint8List _pdfBytes = Uint8List.fromList([
  0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, // %PDF-1.4
  0x0A, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A,
]);

/// A minimal RIFF/WAVE header: audio, by content.
final Uint8List _wavBytes = Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x24, 0x00, 0x00, 0x00,
  0x57, 0x41, 0x56, 0x45, // WAVE
  0x66, 0x6D, 0x74, 0x20, // fmt␣
]);

const String _refusal =
    'This file cannot be shown here. Save it outside the vault to open it.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_preview_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Opens a vault holding exactly the files given, and shows it.
  Future<void> openWith(
    WidgetTester tester,
    Map<String, Uint8List> files,
  ) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    const passphrase = 'correct horse battery staple';
    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() async {
      await controller.createVault(passphrase);
      final store = VaultStore(tempDir, sodium);
      final slots = await store.readSlots();
      final key =
          tryUnlock(sodium, passphrase, slots.cast<WrappedKey?>()).dataKey!;
      for (final entry in files.entries) {
        await store.put(key, 0, entry.key, entry.value);
      }
      controller.lock();
      return controller.unlock(passphrase);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the row for [name] and settles, the way a person opens a file.
  ///
  /// The tap runs inside [WidgetTester.runAsync] because opening a file
  /// decrypts it from disk, and real I/O does not advance under the test
  /// clock. The dialog it then shows has to be pumped outside.
  Future<void> openFile(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(name));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  group('types the vault draws itself', () {
    testWidgets('a text file opens in a dialog showing its contents',
        (tester) async {
      await openWith(tester, {
        'notes.txt': Uint8List.fromList('the meeting is at six'.codeUnits),
      });

      await openFile(tester, 'notes.txt');

      expect(find.text('the meeting is at six'), findsOneWidget,
          reason: 'text is previewable, and the preview shows the text');
      expect(find.text(_refusal), findsNothing);
    });

    testWidgets('a markdown file previews as text', (tester) async {
      await openWith(tester, {
        'plan.md': Uint8List.fromList('# Heading\n\nbody text'.codeUnits),
      });

      await openFile(tester, 'plan.md');

      expect(find.textContaining('# Heading'), findsOneWidget,
          reason: 'markdown is text/markdown, which is text/*');
      expect(find.text(_refusal), findsNothing);
    });
  });

  group('types the vault refuses, sending the user to export instead', () {
    testWidgets('a PDF is refused with the export instruction',
        (tester) async {
      await openWith(tester, {'report.pdf': _pdfBytes});

      await openFile(tester, 'report.pdf');

      expect(find.text(_refusal), findsOneWidget,
          reason: 'a PDF viewer would need a package that either misses '
              'GNU/Linux or pulls an HTTP client; export is the route');
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'refusing means no preview dialog, not an empty one');
    });

    testWidgets('an audio file is refused with the export instruction',
        (tester) async {
      await openWith(tester, {'voice.wav': _wavBytes});

      await openFile(tester, 'voice.wav');

      expect(find.text(_refusal), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a file whose name says text but whose bytes say PDF is '
        'refused', (tester) async {
      await openWith(tester, {'report.txt': _pdfBytes});

      await openFile(tester, 'report.txt');

      expect(find.text(_refusal), findsOneWidget,
          reason: 'the decision reads the bytes, so a misleading extension '
              'cannot talk the app into rendering a PDF as text');
    });
  });
}
