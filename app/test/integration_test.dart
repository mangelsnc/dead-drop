/// Integration tests for DeadDrop core (crypto + fountain + frames).
///
/// Ported from spike/src/test_spike.py — validates the Dart implementation
/// produces identical results to the Python spike.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'package:dead_drop/core/crypto/crypto.dart';
import 'package:dead_drop/core/emitter.dart';
import 'package:dead_drop/core/fountain/degree_distribution.dart';
import 'package:dead_drop/core/fountain/lt_decoder.dart';
import 'package:dead_drop/core/fountain/lt_encoder.dart';
import 'package:dead_drop/core/protocol/data_frame.dart';
import 'package:dead_drop/core/protocol/session_header.dart';
import 'package:dead_drop/core/receiver.dart';

void main() {
  late Sodium sodium;

  setUpAll(() async {
    sodium = await SodiumInit.init();
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

      final (_, header) = await openSession(
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

      final (session, header) = await openSession(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      final (nonce, ct) = session.encryptChunk(sodium, 0);

      final receiverSession = await acceptSession(
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

      final (_, header) = await openSession(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      expect(
        () => acceptSession(sodium, header.pack(), wrongKp),
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
      final encoder = LtEncoder(chunks);
      final decoder = LtDecoder(k: 10, chunkSize: 64);

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
      final frame = DataFrame(
        fileId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        seq: 42,
        seed: 1337,
        chunkIds: [0, 3, 7],
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
        payload: Uint8List.fromList(List.generate(100, (i) => i % 256)),
      );

      final packed = frame.pack();
      final unpacked = DataFrame.unpack(packed);

      expect(unpacked.seq, 42);
      expect(unpacked.seed, 1337);
      expect(unpacked.chunkIds, [0, 3, 7]);
      expect(unpacked.nonce, frame.nonce);
      expect(unpacked.payload, frame.payload);
    });

    test('Frame rejects bad magic', () {
      final bad = Uint8List.fromList([0x00, 0x00, 0x01, 0x00]);
      expect(() => DataFrame.unpack(bad), throwsArgumentError);
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
        sodium: sodium,
        fileBytes: plaintext,
        receiverPk: receiverKp.publicKey,
        chunkSize: 512,
      );
      final receiver = Receiver(keypair: receiverKp);

      await receiver.startSession(sodium, emitter.bootstrapQrPayload());

      // Drop every other frame
      for (var i = 0; i < 200 && !receiver.done; i++) {
        final frame = await emitter.nextFrame(sodium);
        if (i % 2 == 0) {
          await receiver.feedFrame(sodium, frame.pack());
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
    sodium: sodium,
    fileBytes: plaintext,
    receiverPk: receiverKp.publicKey,
    chunkSize: chunkSize,
  );
  final receiver = Receiver(keypair: receiverKp);

  await receiver.startSession(sodium, emitter.bootstrapQrPayload());

  var frames = 0;
  while (!receiver.done && frames < 10000) {
    final frame = await emitter.nextFrame(sodium);
    await receiver.feedFrame(sodium, frame.pack());
    frames++;
  }

  expect(receiver.done, isTrue, reason: 'Failed to decode after $frames frames');
  final recovered = receiver.finish();
  expect(recovered, plaintext);
}
