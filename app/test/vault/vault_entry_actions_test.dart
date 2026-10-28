/// The actions on a vault entry: staging a file for sending without it
/// touching the disk, and deciding previewability from the bytes.
///
/// Reported from device testing: a file in the vault could not be sent,
/// and could not be previewed — the second because a transfer that lost
/// its file name left the entry called `deaddrop_received_<timestamp>`
/// with no extension, and previewability was guessed from that name.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/src/file_metadata.dart';
import 'package:dead_drop/ui/send/send_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  ProviderContainer makeContainer() =>
      ProviderContainer(overrides: [sodiumProvider.overrideWithValue(sodium)]);

  group('staging a vault file to send', () {
    test('loadBytes stages the name and bytes', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final bytes = Uint8List.fromList(utf8.encode('hello'));
      container.read(sendProvider.notifier).loadBytes('notes.txt', bytes);

      final state = container.read(sendProvider);
      expect(state.fileName, 'notes.txt');
      expect(state.fileBytes, bytes);
      expect(state.fileExtension, 'txt');
    });

    test('a staged file has no path, because it never touched the disk',
        () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(sendProvider.notifier).loadBytes(
            'secret.pdf',
            Uint8List.fromList(List.filled(64, 1)),
          );

      expect(container.read(sendProvider).filePath, isNull,
          reason: 'exporting the file to send it would undo the vault for '
              'as long as that copy existed');
    });

    test('a name with no extension stages cleanly', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      container.read(sendProvider.notifier).loadBytes(
            'deaddrop_received_1793188927823',
            Uint8List.fromList(List.filled(32, 2)),
          );

      final state = container.read(sendProvider);
      expect(state.fileName, 'deaddrop_received_1793188927823');
      expect(state.fileExtension, isNull);
    });
  });

  group('previewability comes from the bytes, not the name', () {
    /// The first bytes of a real PNG.
    final png = Uint8List.fromList(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]);

    test('a PNG with no extension is still recognised as an image', () {
      expect(guessMimeType(png, null), 'image/png',
          reason: 'a file whose name was lost in transit must not become '
              'unviewable because of it');
    });

    test('a PNG misnamed .txt is recognised by its content', () {
      expect(guessMimeType(png, 'txt'), 'image/png',
          reason: 'magic bytes take priority over the extension');
    });

    test('text with no magic bytes falls back to the extension', () {
      final text = Uint8List.fromList(utf8.encode('just some words here'));
      expect(guessMimeType(text, 'txt'), startsWith('text/'));
    });

    test('unknown content with no extension yields nothing', () {
      final blob = Uint8List.fromList(List.filled(64, 0xAB));
      expect(guessMimeType(blob, null), isNull,
          reason: 'offering to preview arbitrary binary would show noise');
    });
  });
}
