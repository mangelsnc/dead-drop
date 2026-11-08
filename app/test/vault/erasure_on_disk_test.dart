/// What the two erasure paths actually leave on the filesystem.
///
/// The controller tests prove the vault stops opening. That is not the
/// same question: an owner who deletes a vault is asking for it to be
/// gone from the device, and a vault that merely refuses to unlock while
/// its files sit there has not answered them. Reported as a doubt about
/// whether deletion works at all.
///
/// The two paths differ on purpose, and the difference is the whole
/// design, so both are pinned here:
///
///   * Self-destruct runs under an attacker's hands. It discards the
///     keys and leaves the shape alone, because a device that suddenly
///     has no vault directory announces that there was something worth
///     erasing.
///   * Deleting is the owner at the controls, wanting it gone. The shape
///     goes too.
///
/// Neither claims the bytes are unrecoverable on flash with
/// wear-levelling; see docs/security.md. What is claimed is that the
/// wrapped keys are gone.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dead_drop/src/vault/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('erasure_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A store holding one file in each environment.
  Future<VaultStore> populated() async {
    final store = VaultStore(tempDir, sodium);
    await store.init();
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    await store.put(
        key, 0, 'real.txt', Uint8List.fromList(List.filled(5000, 7)));
    await store.put(
        key, 1, 'decoy.txt', Uint8List.fromList(List.filled(3000, 9)));
    return store;
  }

  List<String> survivors() => tempDir.existsSync()
      ? tempDir
          .listSync(recursive: true)
          .map((e) => e.path.replaceFirst(tempDir.path, ''))
          .toList()
      : const [];

  group('deleting the vault', () {
    test('leaves nothing on disk, not even the directory', () async {
      final store = await populated();
      expect(survivors(), isNotEmpty, reason: 'or this proves nothing');

      await store.deleteEverything();

      expect(survivors(), isEmpty);
      expect(tempDir.existsSync(), isFalse,
          reason: 'the owner asked for the vault to be gone');
    });

    test('removes every entry file, not only the keys', () async {
      final store = await populated();

      await store.deleteEverything();

      // Sealed content without its key is unreadable, but leaving it
      // behind still says how many files were kept and how big they
      // were.
      expect(
        Directory('${tempDir.path}/entries').existsSync(),
        isFalse,
      );
    });

    test('is safe to run twice', () async {
      final store = await populated();
      await store.deleteEverything();
      await store.deleteEverything();
      expect(survivors(), isEmpty);
    });
  });

  group('self-destruct', () {
    test('leaves the store looking exactly as it did', () async {
      // The property the decoy depends on. If erasing changed the file
      // count or any file's size, a seized device would show that
      // something had been destroyed.
      final store = await populated();
      final before = {
        for (final e in tempDir.listSync(recursive: true))
          e.path.replaceFirst(tempDir.path, ''):
              e is File ? e.lengthSync() : -1,
      };

      await store.destroySlot(0);
      await store.destroySlot(1);

      final after = {
        for (final e in tempDir.listSync(recursive: true))
          e.path.replaceFirst(tempDir.path, ''):
              e is File ? e.lengthSync() : -1,
      };
      expect(after, before,
          reason: 'self-destruct must not change the shape of the store');
    });

    test('leaves slots that still parse, holding nothing', () async {
      // readSlots must not start throwing, and must not report the
      // slots as absent: "this slot holds nothing" is precisely what
      // must never be observable.
      final store = await populated();
      await store.destroySlot(0);
      await store.destroySlot(1);

      final slots = await store.readSlots();

      expect(slots.length, 2);
      expect(slots.every((s) => s != null), isTrue,
          reason: 'an empty slot is written as a well-formed filler, so '
              'it is indistinguishable from an occupied one');
    });

    test('keeps the entry files, which no key now opens', () async {
      // Deliberate: removing them would be the disclosure. They are
      // sealed under a data key whose only copy was in the slot.
      final store = await populated();
      final entriesBefore =
          Directory('${tempDir.path}/entries').listSync().length;

      await store.destroySlot(0);
      await store.destroySlot(1);

      expect(Directory('${tempDir.path}/entries').listSync().length,
          entriesBefore);
    });
  });
}
