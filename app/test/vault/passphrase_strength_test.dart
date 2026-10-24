/// Tests for passphrase strength estimation and generation
/// (app/lib/src/vault/passphrase_strength.dart).
///
/// The headline property under test: entropy is estimated, not composition.
/// `Password1!` satisfies every "uppercase + digit + symbol + 10 chars"
/// rule and must still be rejected, because it is a dictionary word plus
/// the single most predictable capitalisation/digit/symbol choices.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/passphrase_strength.dart';
import 'package:dead_drop/src/vault/passphrase_wordlist.dart';

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
  group('estimateStrength', () {
    test('rejects known-weak passphrases', () {
      for (final weak in ['Password1!', 'MiCasa2024', '123456', 'deaddrop']) {
        expect(estimateStrength(weak).meetsMinimum, isFalse, reason: weak);
      }
    });

    test('rejects an empty passphrase', () {
      final result = estimateStrength('');
      expect(result.meetsMinimum, isFalse);
      expect(result.entropyBits, equals(0));
    });

    test('a six-digit PIN does not meet the minimum', () {
      final result = estimateStrength('483921');
      expect(result.meetsMinimum, isFalse);
      // Well below the floor — a 6-digit PIN is at most ~20 bits even
      // charged at full log2(10) per digit, and this estimator caps digit
      // runs below that.
      expect(result.entropyBits, lessThan(kMinimumEntropyBits));
    });

    test('rejects a plain keyboard walk', () {
      expect(estimateStrength('qwertyuiop').meetsMinimum, isFalse);
    });

    test('rejects a block of repeated characters', () {
      expect(estimateStrength('aaaaaaaaaaaa').meetsMinimum, isFalse);
    });

    test('accepts a long, unpredictable random string', () {
      // 24 chars drawn from a mixed charset is far above the floor even
      // under this estimator's conservative per-character accounting.
      final result = estimateStrength('xQ7!kP2@mZ9#vL4\$wR8%jN3^');
      expect(result.meetsMinimum, isTrue);
    });

    test('accepts a generated five-word passphrase', () {
      // Independent of generatePassphrase: assembles words directly from
      // the bundled wordlist so this test has no libsodium dependency.
      final passphrase =
          '${kPassphraseWordlist[10]} ${kPassphraseWordlist[20000]} '
          '${kPassphraseWordlist[30000]} ${kPassphraseWordlist[39000]} '
          '${kPassphraseWordlist[5000]}';
      final result = estimateStrength(passphrase);
      expect(result.meetsMinimum, isTrue, reason: passphrase);
    });
  });

  group('generatePassphrase', () {
    late SodiumSumo sodium;

    setUpAll(() async {
      sodium = await SodiumSumoInit.init2(_loadLibsodium);
    });

    test('returns the requested number of words', () {
      final words = generatePassphrase(sodium, words: 5);
      expect(words, hasLength(5));
    });

    test('returns distinct words from the wordlist', () {
      final words = generatePassphrase(sodium, words: 8);
      for (final word in words) {
        expect(kPassphraseWordlist, contains(word));
      }
      // Not a strict requirement that all 8 be pairwise distinct (sampling
      // is with replacement), but collisions among 8 draws from a
      // 40,000-word list should essentially never happen; a failure here
      // would indicate a broken RNG, not bad luck.
      expect(words.toSet(), hasLength(words.length));
    });

    test('a generated four-word passphrase meets the minimum entropy', () {
      final words = generatePassphrase(sodium, words: 4);
      final result = estimateStrength(words.join(' '));
      expect(result.meetsMinimum, isTrue,
          reason: '${words.join(' ')} (~${result.entropyBits} bits)');
    });

    test('a generated five-word passphrase clears the minimum with margin', () {
      final words = generatePassphrase(sodium, words: 5);
      final result = estimateStrength(words.join(' '));
      expect(result.entropyBits, greaterThan(kMinimumEntropyBits + 10));
    });

    test('two generated passphrases differ (not a fixed sequence)', () {
      // Weak evidence on its own, but combined with the source-inspection
      // test below rules out both "hardcoded" and "seeded, deterministic"
      // implementations.
      final a = generatePassphrase(sodium, words: 6);
      final b = generatePassphrase(sodium, words: 6);
      expect(a, isNot(equals(b)));
    });

    test('implementation draws from sodium.randombytes, not dart:math', () {
      // There is no mocking library in this project to intercept
      // SodiumSumo (a concrete class, not a small interface) at the call
      // site, so this is a source-level check instead: it pins down the
      // exact requirement ("use sodium.randombytes, never dart:math's
      // Random") against the body of generatePassphrase itself, rather
      // than trusting a doc comment to stay true.
      final source =
          File('lib/src/vault/passphrase_strength.dart').readAsStringSync();
      final body = _functionBody(source, 'List<String> generatePassphrase');

      expect(body, contains('sodium.randombytes'),
          reason: 'generatePassphrase must draw randomness from '
              'sodium.randombytes');
      expect(body, isNot(contains('Random(')),
          reason: 'generatePassphrase must not use dart:math Random');
    });
  });
}

/// Extracts the brace-delimited body of the first top-level function whose
/// signature starts with [signaturePrefix], for source-level assertions
/// that don't need a full Dart parser.
String _functionBody(String source, String signaturePrefix) {
  final start = source.indexOf(signaturePrefix);
  if (start == -1) {
    fail('Could not find a function starting with "$signaturePrefix"');
  }

  // Skip the parameter list first: it may itself contain a brace-delimited
  // group of named parameters (e.g. "{int words = 5}"), which is not the
  // function body.
  final parenOpen = source.indexOf('(', start);
  var parenDepth = 0;
  var parenClose = -1;
  for (var i = parenOpen; i < source.length; i++) {
    if (source[i] == '(') parenDepth++;
    if (source[i] == ')') {
      parenDepth--;
      if (parenDepth == 0) {
        parenClose = i;
        break;
      }
    }
  }
  if (parenClose == -1) {
    fail('Could not find the parameter list for "$signaturePrefix"');
  }

  final openBrace = source.indexOf('{', parenClose);
  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(openBrace, i + 1);
    }
  }
  fail('Unbalanced braces while extracting "$signaturePrefix"');
}
