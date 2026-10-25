/// Tests for the vault unlock path (app/lib/src/vault/vault_session.dart).
///
/// The property under test — constant derivation count regardless of
/// outcome — is the feature's headline guarantee: a coerced user typing the
/// decoy passphrase must cost an attacker-observable amount of work
/// identical to the real passphrase, a wrong passphrase, or an empty slot.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/src/vault/vault_session.dart';

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

  setUpAll(() async {
    sodium = await SodiumSumoInit.init2(_loadLibsodium);
  });

  group('tryUnlock', () {
    test('unlocks slot 0 with the real passphrase', () {
      final dataKey = newDataKey(sodium);
      final real = wrapDataKey(sodium, 'real passphrase', dataKey);
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      final result = tryUnlock(sodium, 'real passphrase', [real, decoy]);

      expect(result.ok, isTrue);
      expect(result.slotIndex, equals(0));
      expect(result.dataKey, equals(dataKey));
    });

    test('unlocks slot 1 with the decoy passphrase', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoyKey = newDataKey(sodium);
      final decoy = wrapDataKey(sodium, 'decoy passphrase', decoyKey);

      final result = tryUnlock(sodium, 'decoy passphrase', [real, decoy]);

      expect(result.ok, isTrue);
      expect(result.slotIndex, equals(1));
      expect(result.dataKey, equals(decoyKey));
    });

    test('returns not-ok for an unknown passphrase', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      final result = tryUnlock(sodium, 'wrong passphrase', [real, decoy]);

      expect(result.ok, isFalse);
      expect(result.slotIndex, isNull);
      expect(result.dataKey, isNull);
    });

    test(
        'attempts exactly kVaultEnvironmentSlots derivations regardless of '
        'outcome', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));
      final slots = [real, decoy];

      int countFor(String passphrase) {
        var count = 0;
        Uint8List? counting(
          SodiumSumo s,
          String p,
          WrappedKey w,
        ) {
          count++;
          return unwrapDataKey(s, p, w);
        }

        tryUnlock(sodium, passphrase, slots, unwrapDataKey: counting);
        return count;
      }

      final realCount = countFor('real passphrase');
      final decoyCount = countFor('decoy passphrase');
      final wrongCount = countFor('wrong passphrase');

      expect(realCount, equals(kVaultEnvironmentSlots));
      expect(decoyCount, equals(kVaultEnvironmentSlots));
      expect(wrongCount, equals(kVaultEnvironmentSlots));
    });

    test('an empty slot costs the same as a filled one', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      int countWith(List<WrappedKey?> slots, String passphrase) {
        var count = 0;
        Uint8List? counting(
          SodiumSumo s,
          String p,
          WrappedKey w,
        ) {
          count++;
          return unwrapDataKey(s, p, w);
        }

        tryUnlock(sodium, passphrase, slots, unwrapDataKey: counting);
        return count;
      }

      // A vault with a decoy...
      final withDecoyCount = countWith([real, decoy], 'real passphrase');
      // ...and a vault with no decoy at all...
      final withoutDecoyCount = countWith([real, null], 'real passphrase');

      // ...must spend identical derivation counts, or the absence of a
      // decoy becomes detectable.
      expect(withoutDecoyCount, equals(withDecoyCount));
      expect(withoutDecoyCount, equals(kVaultEnvironmentSlots));
    });
  });
}
