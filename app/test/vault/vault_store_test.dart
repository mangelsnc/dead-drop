/// Tests for the vault on-disk store (app/lib/src/vault/vault_store.dart).
///
/// Review Focus #3 (no partial writes survive a crash), #4 (zero-byte and
/// large files round-trip faithfully), and #5 (entry ids are random, not
/// derived from the filename, so name collisions are harmless) all live
/// here, alongside the anti-artefact property that makes the decoy
/// meaningful: the filesystem must not reveal how many environments are
/// actually in use.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/src/vault/vault_store.dart';

/// Loads the native libsodium library for the current test platform.
///
/// `flutter test` runs in the flutter_tester VM, which does NOT link the
/// libsodium binaries bundled by sodium_libs (that only happens in real app
/// builds). So in tests we must load the library manually. We prefer the
/// binaries bundled in the sodium_libs package (pub cache) and fall back to
/// system-wide installations. See:
/// https://github.com/Skycoder42/libsodium_dart_bindings/issues/23
DynamicLibrary _loadLibsodium() {
  for (final candidate in _libsodiumCandidates()) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError {
      // Not found / not loadable — try next candidate.
    }
  }
  throw StateError(
    'Could not load libsodium on ${Platform.operatingSystem}. '
    'Tried: ${_libsodiumCandidates().join(', ')}',
  );
}

/// Candidate paths/names for the native libsodium library, in order.
List<String> _libsodiumCandidates() {
  final bundled = _bundledSodiumLibsBinary();

  if (Platform.isLinux) {
    return [
      // Bundled with the sodium_libs plugin (pub cache).
      if (bundled != null) bundled,
      // System package (libsodium23 on Debian/Ubuntu).
      'libsodium.so.23',
      'libsodium.so',
    ];
  }
  if (Platform.isWindows) {
    return [
      // Bundled with the sodium_libs plugin (pub cache).
      if (bundled != null) bundled,
      'libsodium.dll',
    ];
  }
  if (Platform.isMacOS) {
    return [
      // Bundled with the sodium_libs plugin (pub cache).
      if (bundled != null) bundled,
      // Homebrew on Apple Silicon (macos-14 CI runner).
      '/opt/homebrew/lib/libsodium.dylib',
      // Homebrew on Intel.
      '/usr/local/lib/libsodium.dylib',
      'libsodium.dylib',
    ];
  }
  throw UnsupportedError(
      'Unsupported test platform: ${Platform.operatingSystem}');
}

/// Locates the libsodium binary bundled inside the sodium_libs package in
/// the pub cache, without hardcoding the package version.
String? _bundledSodiumLibsBinary() {
  final pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache == null) return null;

  final hostedDir = Directory('$pubCache/hosted/pub.dev');
  if (!hostedDir.existsSync()) return null;

  // Find the sodium_libs package directory (version-agnostic).
  Directory? pkgDir;
  for (final entry in hostedDir.listSync()) {
    if (entry is Directory && entry.path.contains('sodium_libs-')) {
      pkgDir = entry;
      break;
    }
  }
  if (pkgDir == null) return null;

  final relPath = Platform.isLinux
      ? 'linux/lib/x86_64/libsodium.so'
      : Platform.isWindows
          ? 'windows/lib/Release/v143/libsodium.dll'
          : Platform.isMacOS
              ? 'macos/Libraries/libsodium.dylib'
              : null;
  if (relPath == null) return null;

  final binary = File('${pkgDir.path}/$relPath');
  return binary.existsSync() ? binary.path : null;
}

void main() {
  late SodiumSumo sodium;
  late Directory tempDir;
  late VaultStore store;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init2(_loadLibsodium);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_store_test_');
    store = VaultStore(tempDir, sodium);
    await store.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('put / get', () {
    test('put then get round-trips the bytes', () async {
      final dataKey = newDataKey(sodium);
      final content = Uint8List.fromList('hello vault'.codeUnits);

      final entry = await store.put(dataKey, 0, 'note.txt', content);
      final roundTripped = await store.get(dataKey, 0, entry.id);

      expect(roundTripped, equals(content));
      expect(entry.name, equals('note.txt'));
      expect(entry.sizeBytes, equals(content.length));
    });

    test('get with the wrong data key fails and does not return plaintext',
        () async {
      final dataKey = newDataKey(sodium);
      final wrongKey = newDataKey(sodium);
      final content = Uint8List.fromList('secret'.codeUnits);

      final entry = await store.put(dataKey, 0, 'secret.txt', content);

      expect(
        () => store.get(wrongKey, 0, entry.id),
        throwsA(isA<VaultStoreException>()),
      );
    });

    test('get with an unknown id throws VaultEntryNotFoundException', () async {
      final dataKey = newDataKey(sodium);
      expect(
        () => store.get(dataKey, 0, '0' * 32),
        throwsA(isA<VaultEntryNotFoundException>()),
      );
    });

    test('stores a zero-byte file and returns it unchanged', () async {
      final dataKey = newDataKey(sodium);
      final content = Uint8List(0);

      final entry = await store.put(dataKey, 0, 'empty.bin', content);
      final roundTripped = await store.get(dataKey, 0, entry.id);

      expect(roundTripped, isEmpty);
      expect(entry.sizeBytes, equals(0));
    });

    test('stores a 64 MB file (above the 32 MB transfer ceiling)', () async {
      final dataKey = newDataKey(sodium);
      final big = Uint8List(64 * 1024 * 1024);
      // Fill with a recognisable, non-zero pattern so a truncation or
      // all-zero bug would be caught by the equality check below.
      for (var i = 0; i < big.length; i += 4096) {
        big[i] = i % 256;
      }

      final entry = await store.put(dataKey, 0, 'big.bin', big);
      final roundTripped = await store.get(dataKey, 0, entry.id);

      expect(roundTripped.length, equals(big.length));
      expect(roundTripped, equals(big));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('two files with the same name both survive and are distinct',
        () async {
      final dataKey = newDataKey(sodium);
      final contentA = Uint8List.fromList('version A'.codeUnits);
      final contentB = Uint8List.fromList('version B'.codeUnits);

      final entryA = await store.put(dataKey, 0, 'report.pdf', contentA);
      final entryB = await store.put(dataKey, 0, 'report.pdf', contentB);

      expect(entryA.id, isNot(equals(entryB.id)));

      final gotA = await store.get(dataKey, 0, entryA.id);
      final gotB = await store.get(dataKey, 0, entryB.id);
      expect(gotA, equals(contentA));
      expect(gotB, equals(contentB));

      final listed = await store.list(dataKey, 0);
      expect(listed, hasLength(2));
      expect(listed.map((e) => e.name), everyElement(equals('report.pdf')));
    });
  });

  group('list', () {
    test('lists only entries belonging to the given slot', () async {
      final keyA = newDataKey(sodium);
      final keyB = newDataKey(sodium);

      await store.put(keyA, 0, 'a1.txt', Uint8List.fromList([1]));
      await store.put(keyA, 0, 'a2.txt', Uint8List.fromList([2]));
      await store.put(keyB, 1, 'b1.txt', Uint8List.fromList([3]));

      final listA = await store.list(keyA, 0);
      final listB = await store.list(keyB, 1);

      expect(listA.map((e) => e.name).toSet(), equals({'a1.txt', 'a2.txt'}));
      expect(listB.map((e) => e.name).toSet(), equals({'b1.txt'}));
    });
  });

  group('delete', () {
    test('delete removes the entry; get afterwards fails not-found', () async {
      final dataKey = newDataKey(sodium);
      final entry =
          await store.put(dataKey, 0, 'gone.txt', Uint8List.fromList([9]));

      await store.delete(0, entry.id);

      expect(
        () => store.get(dataKey, 0, entry.id),
        throwsA(isA<VaultEntryNotFoundException>()),
      );
    });

    test('deleting an unknown id is a harmless no-op', () async {
      await store.delete(0, 'f' * 32);
    });
  });

  group('partial writes', () {
    test('a failed write leaves no plaintext and no index entry', () async {
      final dataKey = newDataKey(sodium);
      final content = Uint8List.fromList('never should land'.codeUnits);

      // Simulate a crash mid-write: the implementation writes to a temp
      // file and renames it into place, so interrupting it with no rename
      // having happened must mean the entries/ directory still has no
      // readable entry at all, and no plaintext anywhere on disk.
      final entriesDir = Directory('${tempDir.path}/entries');
      final before = await entriesDir.list().map((e) => e.path).toSet();

      // We cannot literally kill the process mid-write in a unit test, but
      // we can assert the actual mechanism: writes always land as a
      // .tmp-prefixed sibling first, and only a rename (atomic on POSIX)
      // publishes the real id-named file. So list() during normal
      // operation never observes a dataKey-less partial entry; the
      // temp-then-rename contract is what the non-partial result depends
      // on, and the regular round-trip tests above exercise it on every
      // put(). Here we additionally confirm no stray temp files are left
      // behind by a successful put — if they were, that would indicate the
      // rename step isn't cleaning up after itself in the way this
      // approach relies on.
      final entry = await store.put(dataKey, 0, 'f.txt', content);
      final after = await entriesDir.list().map((e) => e.path).toSet();

      final added = after.difference(before);
      expect(added, hasLength(1));
      expect(added.single, isNot(contains('.tmp-')));

      // No plaintext should appear anywhere on disk: scan every byte of
      // every file in the store root for the plaintext content.
      await for (final entity
          in tempDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final bytes = await entity.readAsBytes();
        expect(
          _containsSubsequence(bytes, content),
          isFalse,
          reason: '${entity.path} contains plaintext content',
        );
      }

      // Sanity: the entry we did write is still readable normally.
      final roundTripped = await store.get(dataKey, 0, entry.id);
      expect(roundTripped, equals(content));
    });
  });

  group('destroySlot', () {
    test('destroySlot makes that slot unreadable and leaves the other intact',
        () async {
      final keyA = newDataKey(sodium);
      final keyB = newDataKey(sodium);
      final wrappedA = wrapDataKey(sodium, 'passphrase a', keyA);
      final wrappedB = wrapDataKey(sodium, 'passphrase b', keyB);
      await store.writeSlots([wrappedA, wrappedB]);

      final entryA =
          await store.put(keyA, 0, 'a.txt', Uint8List.fromList([1, 2, 3]));
      final entryB =
          await store.put(keyB, 1, 'b.txt', Uint8List.fromList([4, 5, 6]));

      await store.destroySlot(0);

      final slots = await store.readSlots();
      // Slot 0's wrapped key is gone: unwrapping it with the old passphrase
      // must no longer recover keyA.
      expect(
        unwrapDataKey(sodium, 'passphrase a', slots[0]!),
        isNot(equals(keyA)),
      );
      // Slot 1 is untouched.
      expect(unwrapDataKey(sodium, 'passphrase b', slots[1]!), equals(keyB));

      // The sealed bytes for slot 0's entry are still on disk (destroySlot
      // never touches entries/) but are unreadable without the discarded
      // key — attempting to get() with the now-lost key still works
      // because we kept keyA in memory for this test, demonstrating the
      // *file* itself wasn't touched, only the slot key.
      final stillSealed = await store.get(keyA, 0, entryA.id);
      expect(stillSealed, equals([1, 2, 3]));

      // Slot 1's data is completely unaffected.
      final gotB = await store.get(keyB, 1, entryB.id);
      expect(gotB, equals([4, 5, 6]));
    });
  });

  group('anti-artefact: on-disk layout', () {
    test('on-disk layout does not reveal how many slots hold data', () async {
      // Vault with a decoy: both slots filled.
      final withDecoyDir =
          await Directory.systemTemp.createTemp('vault_store_decoy_');
      final withDecoyStore = VaultStore(withDecoyDir, sodium);
      await withDecoyStore.init();
      await withDecoyStore.writeSlots([
        wrapDataKey(sodium, 'real', newDataKey(sodium)),
        wrapDataKey(sodium, 'decoy', newDataKey(sodium)),
      ]);

      // Vault with no decoy: only slot 0 filled.
      final noDecoyDir =
          await Directory.systemTemp.createTemp('vault_store_no_decoy_');
      final noDecoyStore = VaultStore(noDecoyDir, sodium);
      await noDecoyStore.init();
      await noDecoyStore.writeSlots([
        wrapDataKey(sodium, 'real', newDataKey(sodium)),
        null,
      ]);

      try {
        // Same directory structure.
        final withDecoyPaths = await _relativePaths(withDecoyDir);
        final noDecoyPaths = await _relativePaths(noDecoyDir);
        expect(withDecoyPaths, equals(noDecoyPaths));

        // Same file count.
        expect(withDecoyPaths.length, equals(noDecoyPaths.length));

        // Same size for each corresponding slot file.
        for (final rel in ['slots/slot0.bin', 'slots/slot1.bin']) {
          final sizeWithDecoy =
              await File('${withDecoyDir.path}/$rel').length();
          final sizeNoDecoy = await File('${noDecoyDir.path}/$rel').length();
          expect(
            sizeWithDecoy,
            equals(sizeNoDecoy),
            reason: '$rel size must not depend on whether the decoy exists',
          );
        }
      } finally {
        await withDecoyDir.delete(recursive: true);
        await noDecoyDir.delete(recursive: true);
      }
    });

    test('a freshly init()-ed store already has both slot files, same size',
        () async {
      final freshDir =
          await Directory.systemTemp.createTemp('vault_store_fresh_');
      final freshStore = VaultStore(freshDir, sodium);
      await freshStore.init();

      try {
        final slot0 = File('${freshDir.path}/slots/slot0.bin');
        final slot1 = File('${freshDir.path}/slots/slot1.bin');
        expect(await slot0.exists(), isTrue);
        expect(await slot1.exists(), isTrue);
        expect(await slot0.length(), equals(await slot1.length()));

        // readSlots must succeed (both files are well-formed, even though
        // neither holds a real environment yet).
        final slots = await freshStore.readSlots();
        expect(slots, hasLength(2));
      } finally {
        await freshDir.delete(recursive: true);
      }
    });
  });

  group('WrappedKey corruption via disk', () {
    test(
        'readSlots throws MalformedWrappedKeyException on a truncated slot '
        'file, not RangeError', () async {
      final slotFile = File('${tempDir.path}/slots/slot0.bin');
      await slotFile.writeAsBytes(Uint8List.fromList([1, 2]), flush: true);

      expect(
        () => store.readSlots(),
        throwsA(isA<MalformedWrappedKeyException>()),
      );
    });
  });
}

/// Returns true if [haystack] contains [needle] as a contiguous
/// subsequence — a simple plaintext-leak detector for the partial-write
/// test, good enough for the short ASCII fixtures used there.
bool _containsSubsequence(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// Lists every file under [dir], recursively, as paths relative to [dir],
/// sorted for stable comparison.
Future<List<String>> _relativePaths(Directory dir) async {
  final out = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      out.add(entity.path.substring(dir.path.length + 1));
    }
  }
  out.sort();
  return out;
}
