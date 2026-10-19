/// Integration tests for DeadDrop core (crypto + fountain + frames).
///
/// Ported from spike/src/test_spike.py — validates the Dart implementation
/// produces identical results to the Python spike.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium_libs/sodium_libs.dart' show Sodium;
import 'package:sodium/sodium.dart' show SodiumInit;

import 'package:dead_drop/src/crypto.dart';
import 'package:dead_drop/src/emitter.dart';
import 'package:dead_drop/src/fountain.dart';
import 'package:dead_drop/src/qrframe.dart';
import 'package:dead_drop/src/receiver.dart';

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
  throw UnsupportedError('Unsupported test platform: ${Platform.operatingSystem}');
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
  late Sodium sodium;

  setUpAll(() async {
    sodium = await SodiumInit.init(_loadLibsodium);
  });

  group('Crypto', () {
    test('Identity sign/verify roundtrip', () async {
      final identity = await Identity.generate(sodium);
      final message = Uint8List.fromList('hello'.codeUnits);
      final signature = identity.sign(sodium, message);
      final valid = sodium.crypto.sign.verifyDetached(
        signature: signature,
        message: message,
        publicKey: identity.verifyKey,
      );
      expect(valid, isTrue);
    });

    test('SessionHeader pack/unpack roundtrip', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(1024, (i) => i % 256));

      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      final packed = header.pack();
      final unpacked = SessionHeader.unpack(packed);

      expect(unpacked.totalSize, 1024);
      expect(unpacked.chunkCount, 2);
      expect(unpacked.chunkSize, 512);
      expect(unpacked.fileId, header.fileId);
      expect(unpacked.manifestHash, header.manifestHash);
    });

    test('Session encrypt/decrypt chunk roundtrip', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(1024, (i) => i % 256));

      final (session, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      final (nonce, ct) = session.encryptChunk(sodium, 0);

      final receiverSession = await ReceiverSession.accept(
        sodium,
        header.pack(),
        receiverKp,
        senderVerifyKey: identity.verifyKey,
      );

      final decrypted = receiverSession.decryptChunk(sodium, nonce, ct);
      expect(decrypted, session.chunks[0]);
    });

    test('Receiver rejects wrong receiver_pk', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final wrongKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(512, (i) => i % 256));

      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      expect(
        () => ReceiverSession.accept(sodium, header.pack(), wrongKp),
        throwsA(isA<DeadDropCryptoError>()),
      );
    });
  });

  group('Fountain', () {
    test('LT encoder/decoder roundtrip', () {
      final chunks = List.generate(
        10,
        (i) => Uint8List.fromList(List.generate(64, (j) => (i * 64 + j) % 256)),
      );
      final encoder = LTEncoder(chunks);
      final decoder = LTDecoder(k: 10, chunkSize: 64);

      var framesNeeded = 0;
      for (var seq = 0; seq < 100 && !decoder.done; seq++) {
        final (ids, payload) = encoder.makeFrame(seq, 42);
        decoder.addFrame(ids, payload);
        framesNeeded++;
      }

      expect(decoder.done, isTrue);
      expect(framesNeeded, lessThan(30)); // should decode with ~1.3x overhead
      expect(decoder.reassemble(), chunks.expand((c) => c).toList());
    });

    test('Robust soliton CDF sums to 1.0', () {
      final cdf = robustSolitonCdf(100);
      expect(cdf.last, closeTo(1.0, 1e-10));
    });
  });

  group('Frame', () {
    test('Frame pack/unpack roundtrip', () {
      final frame = Frame(
        fileId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        seq: 42,
        seed: 1337,
        chunkIds: [0, 3, 7],
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
        payload: Uint8List.fromList(List.generate(100, (i) => i % 256)),
      );

      final packed = frame.pack();
      final unpacked = Frame.unpack(packed);

      expect(unpacked.seq, 42);
      expect(unpacked.seed, 1337);
      expect(unpacked.chunkIds, [0, 3, 7]);
      expect(unpacked.nonce, frame.nonce);
      expect(unpacked.payload, frame.payload);
    });

    test('Frame rejects bad magic', () {
      final bad = Uint8List.fromList([0x00, 0x00, 0x01, 0x00]);
      expect(() => Frame.unpack(bad), throwsArgumentError);
    });
  });

  group('End-to-end', () {
    test('Full transfer: 1KB file', () async {
      await _testTransfer(sodium, 1024, 512);
    });

    test('Full transfer: 100KB file', () async {
      await _testTransfer(sodium, 100 * 1024, 512);
    });

    test('Full transfer: 1MB file', () async {
      await _testTransfer(sodium, 1024 * 1024, 512);
    });

    test('Transfer tolerates 50% frame loss', () async {
      final plaintext = Uint8List.fromList(List.generate(8192, (i) => i % 256));
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);

      await receiver.startSession(emitter.bootstrapQrPayload());

      // Drop every other frame
      for (var i = 0; i < 200 && !receiver.done; i++) {
        final frame = emitter.nextFrame();
        if (i % 2 == 0) {
          receiver.feedFrame(frame.pack());
        }
      }

      expect(receiver.done, isTrue);
      final recovered = receiver.finish();
      expect(recovered, plaintext);
    });
  });
}

Future<void> _testTransfer(Sodium sodium, int size, int chunkSize) async {
  final plaintext = Uint8List.fromList(List.generate(size, (i) => i % 256));
  final receiverKp = await ReceiverKeypair.generate(sodium);
  final emitter = await Emitter.create(
    sodium,
    plaintext,
    receiverKp,
    chunkSize: chunkSize,
  );
  final receiver = Receiver(sodium: sodium, keypair: receiverKp);

  await receiver.startSession(emitter.bootstrapQrPayload());

  var frames = 0;
  while (!receiver.done && frames < 10000) {
    final frame = emitter.nextFrame();
    receiver.feedFrame(frame.pack());
    frames++;
  }

  expect(receiver.done, isTrue, reason: 'Failed to decode after $frames frames');
  final recovered = receiver.finish();
  expect(recovered, plaintext);
}
