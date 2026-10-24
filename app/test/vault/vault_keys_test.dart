/// Tests for the vault key hierarchy (app/lib/src/vault/vault_keys.dart).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';

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

  group('wrapDataKey / unwrapDataKey', () {
    test('wrap then unwrap with the same passphrase returns the data key',
        () {
      final dataKey = newDataKey(sodium);
      final wrapped = wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      final unwrapped =
          unwrapDataKey(sodium, 'correct horse battery staple', wrapped);

      expect(unwrapped, equals(dataKey));
    });

    test('unwrap with a wrong passphrase returns null, does not throw', () {
      final dataKey = newDataKey(sodium);
      final wrapped = wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      Uint8List? unwrapped;
      expect(
        () => unwrapped =
            unwrapDataKey(sodium, 'wrong passphrase', wrapped),
        returnsNormally,
      );
      expect(unwrapped, isNull);
    });

    test('two wraps of the same key differ (fresh salt and nonce)', () {
      final dataKey = newDataKey(sodium);
      final a = wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final b = wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      expect(a.salt, isNot(equals(b.salt)));
      expect(a.nonce, isNot(equals(b.nonce)));
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });
  });

  group('WrappedKey.pack / unpack', () {
    test('pack/unpack round-trips a WrappedKey', () {
      final dataKey = newDataKey(sodium);
      final wrapped = wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      final roundTripped = WrappedKey.unpack(wrapped.pack());

      expect(roundTripped.salt, equals(wrapped.salt));
      expect(roundTripped.nonce, equals(wrapped.nonce));
      expect(roundTripped.ciphertext, equals(wrapped.ciphertext));

      // And the round-tripped WrappedKey must still unwrap correctly.
      final unwrapped = unwrapDataKey(
          sodium, 'correct horse battery staple', roundTripped);
      expect(unwrapped, equals(dataKey));
    });
  });

  group('newDataKey', () {
    test('returns 32 bytes of non-constant output', () {
      final a = newDataKey(sodium);
      final b = newDataKey(sodium);
      expect(a, hasLength(32));
      expect(b, hasLength(32));
      expect(a, isNot(equals(b)));
    });
  });
}
