/// Tests for the Argon2id key-derivation wrapper (app/lib/src/vault/pwhash.dart).
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/pwhash.dart';

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

  group('deriveKek', () {
    test('is deterministic for the same passphrase and salt', () {
      final salt = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', salt);
      final b = deriveKek(sodium, 'correct horse battery staple', salt);
      try {
        expect(a.extractBytes(), equals(b.extractBytes()));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('differs when the salt differs', () {
      final saltA = newSalt(sodium);
      final saltB = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', saltA);
      final b = deriveKek(sodium, 'correct horse battery staple', saltB);
      try {
        expect(a.extractBytes(), isNot(equals(b.extractBytes())));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('differs when the passphrase differs', () {
      final salt = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', salt);
      final b = deriveKek(sodium, 'correct horse battery staple!', salt);
      try {
        expect(a.extractBytes(), isNot(equals(b.extractBytes())));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('returns a 32-byte SecureKey', () {
      final salt = newSalt(sodium);
      final key = deriveKek(sodium, 'correct horse battery staple', salt);
      try {
        expect(key.length, 32);
      } finally {
        key.dispose();
      }
    });

    test('returned key is usable and disposable', () {
      // Covers the hardening fix: deriveKek returns a SecureKey (not raw
      // bytes) so the KEK never sits unprotected in pageable heap memory.
      // The caller must be able to read it via extractBytes() and dispose
      // it without error.
      final salt = newSalt(sodium);
      final key = deriveKek(sodium, 'correct horse battery staple', salt);
      expect(key, isA<SecureKey>());
      expect(() => key.extractBytes(), returnsNormally);
      expect(() => key.dispose(), returnsNormally);
    });
  });

  group('newSalt', () {
    test('returns kVaultSaltBytes of non-constant output', () {
      final a = newSalt(sodium);
      final b = newSalt(sodium);
      expect(a, hasLength(kVaultSaltBytes));
      expect(b, hasLength(kVaultSaltBytes));
      expect(a, isNot(equals(b)));
    });
  });
}
