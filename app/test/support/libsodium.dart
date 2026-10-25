/// Loads the native libsodium binary for tests.
///
/// Extracted from vault_controller_test.dart, where it was first written and
/// where four other vault test files had copies of it. `flutter test` runs in
/// the flutter_tester VM, which does NOT link the binaries bundled by
/// sodium_libs — that only happens in real app builds — so every test that
/// touches libsodium has to open it by hand.
///
/// See https://github.com/Skycoder42/libsodium_dart_bindings/issues/23
///
/// The five vault test files still carry their own private copies. Folding
/// them onto this one is worth doing, but it is a refactor of passing tests
/// and does not belong in the change that introduced this file.
library;

import 'dart:ffi';
import 'dart:io';

/// Loads the native libsodium library for the current test platform.
///
/// `flutter test` runs in the flutter_tester VM, which does NOT link the
/// libsodium binaries bundled by sodium_libs (that only happens in real app
/// builds). So in tests we must load the library manually. We prefer the
/// binaries bundled in the sodium_libs package (pub cache) and fall back to
/// system-wide installations. See:
/// https://github.com/Skycoder42/libsodium_dart_bindings/issues/23
DynamicLibrary loadLibsodiumForTests() {
  for (final candidate in _candidates()) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError {
      // Not found / not loadable — try next candidate.
    }
  }
  throw StateError(
    'Could not load libsodium on ${Platform.operatingSystem}. '
    'Tried: ${_candidates().join(', ')}',
  );
}

/// Candidate paths/names for the native libsodium library, in order.
List<String> _candidates() {
  final bundled = _bundled();

  if (Platform.isLinux) {
    return [
      if (bundled != null) bundled,
      'libsodium.so.23',
      'libsodium.so',
    ];
  }
  if (Platform.isWindows) {
    return [
      if (bundled != null) bundled,
      'libsodium.dll',
    ];
  }
  if (Platform.isMacOS) {
    return [
      if (bundled != null) bundled,
      '/opt/homebrew/lib/libsodium.dylib',
      '/usr/local/lib/libsodium.dylib',
      'libsodium.dylib',
    ];
  }
  throw UnsupportedError(
      'Unsupported test platform: ${Platform.operatingSystem}');
}

/// Locates the libsodium binary bundled inside the sodium_libs package in
/// the pub cache, without hardcoding the package version.
String? _bundled() {
  final pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache == null) return null;

  final hostedDir = Directory('$pubCache/hosted/pub.dev');
  if (!hostedDir.existsSync()) return null;

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
