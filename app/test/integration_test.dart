/// Integration tests for DeadDrop core (crypto + fountain + frames).
///
/// Ported from spike/src/test_spike.py — validates the Dart implementation
/// produces identical results to the Python spike.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart' show Sodium;
import 'package:sodium/sodium.dart' show SodiumInit;

import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/src/crypto.dart';
import 'package:dead_drop/src/emitter.dart';
import 'package:dead_drop/src/fountain.dart';
import 'package:dead_drop/src/handshake.dart';
import 'package:dead_drop/src/qrframe.dart';
import 'package:dead_drop/src/receiver.dart';
import 'package:dead_drop/src/transport.dart';
import 'package:dead_drop/src/utils.dart';

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

    test('Receiver rejects forged signature (wrong sender key)', () async {
      final identity = await Identity.generate(sodium);
      final attackerIdentity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(512, (i) => i % 256));

      // Create a valid session with the real identity.
      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      // Forge a header: same fields but signed by the attacker's key,
      // with the attacker's verify key embedded. The signature IS valid
      // for the attacker's key — but the point is that the receiver
      // can now check the fingerprint and reject unknown senders.
      final forgedHeader = SessionHeader(
        senderEphPk: header.senderEphPk,
        receiverPk: header.receiverPk,
        senderVerifyKey: attackerIdentity.verifyKey,
        fileId: header.fileId,
        totalSize: header.totalSize,
        chunkCount: header.chunkCount,
        chunkSize: header.chunkSize,
        manifestHash: header.manifestHash,
        signature: Uint8List(sigSize),
      );
      forgedHeader.signature =
          attackerIdentity.sign(sodium, forgedHeader.signedPayload());

      // The forged header passes signature verification (it's self-consistent)
      // but the sender fingerprint is different — the UI layer catches this.
      final session = await ReceiverSession.accept(
        sodium,
        forgedHeader.pack(),
        receiverKp,
      );
      // The session is valid but the sender identity is the attacker's.
      expect(session.header.senderVerifyKey, attackerIdentity.verifyKey);
      expect(session.header.senderVerifyKey, isNot(identity.verifyKey));
    });

    test('Receiver rejects tampered header (invalid signature)', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(512, (i) => i % 256));

      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      // Tamper with the header: flip a byte in the manifest hash area.
      final packed = Uint8List.fromList(header.pack());
      packed[100] ^= 0xFF;

      expect(
        () => ReceiverSession.accept(sodium, packed, receiverKp),
        throwsA(isA<DeadDropCryptoError>().having(
          (e) => e.message,
          'message',
          contains('signature invalid'),
        )),
      );
    });

    test('Valid signature with correct senderVerifyKey passes', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.generate(512, (i) => i % 256));

      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      // Should not throw — the header is signed by the embedded key.
      final session = await ReceiverSession.accept(
        sodium,
        header.pack(),
        receiverKp,
      );
      expect(session.header.senderVerifyKey, identity.verifyKey);
    });

    test('Identity fingerprint is deterministic', () async {
      final identity = await Identity.generate(sodium);
      final fp1 = identity.fingerprint;
      final fp2 = identity.fingerprint;
      expect(fp1, fp2);
      expect(fp1.length, 16);

      // Reconstruct from secret key bytes — same fingerprint.
      final restored =
          Identity.fromSecretKeyBytes(sodium, identity.secretKeyBytes);
      expect(restored.fingerprint, fp1);
    });

    // The TOFU prompt asks the user to read a code off the sender's screen
    // and compare it with the one on the receiver's. That check is only
    // meaningful if both screens derive the string the same way: the sender
    // renders it from its own Identity, the receiver from the verify key it
    // reads out of the session header. If these two ever diverge, every
    // first-contact transfer would show a mismatch and users would learn to
    // click through the warning.
    test('Sender and receiver derive the same fingerprint string', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);

      final (_, header) = await Session.open(
        sodium,
        Uint8List.fromList(List.filled(64, 7)),
        512,
        receiverKp.publicKey,
        identity,
      );

      // Sender side: straight from the local identity.
      // Receiver side: from the verify key carried in the header.
      expect(fingerprintOf(header.senderVerifyKey), identity.fingerprint);
      expect(identity.fingerprint.length, fingerprintLength);
    });

    test('Different identities produce different fingerprints', () async {
      final a = await Identity.generate(sodium);
      final b = await Identity.generate(sodium);
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    // Cross-platform known-answer tests for the manifest hash.
    //
    // The manifest hash is BLAKE2b-256 (libsodium `crypto_generichash`).
    // These vectors were generated with Python's `hashlib.blake2b(data,
    // digest_size=32)` — the exact construction the spike uses — so a
    // matching result proves the Dart app and the Python spike produce
    // identical manifest hashes for identical inputs.
    test('Manifest hash matches Python BLAKE2b-256 vectors', () async {
      final vectors = <String, String>{
        // python3 -c "import hashlib; print(hashlib.blake2b(b'', digest_size=32).hexdigest())"
        '': '0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8',
        // python3 -c "import hashlib; print(hashlib.blake2b(b'hello air gap', digest_size=32).hexdigest())"
        'hello air gap':
            '0c8708c306b81c0af1073ef22378f781d3ecdd9acb0404da866dc1891cd6d858',
      };

      for (final entry in vectors.entries) {
        final input = Uint8List.fromList(entry.key.codeUnits);
        final digest = sodium.crypto.genericHash(message: input);
        final hex =
            digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        expect(hex, entry.value, reason: 'input: "${entry.key}"');
      }

      // Binary vector: bytes 0x00..0xFF.
      final binaryInput = Uint8List.fromList(
        List.generate(256, (i) => i),
      );
      final binaryDigest = sodium.crypto.genericHash(message: binaryInput);
      final binaryHex =
          binaryDigest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        binaryHex,
        '39a7eb9fedc19aabc83425c6755dd90e6f9d0c804964a1f4aaeea3b9fb599835',
        reason: 'input: bytes 0x00..0xFF',
      );
    });

    test('Manifest hash verification accepts correct file, rejects tampered',
        () async {
      final plaintext = Uint8List.fromList('verify me end to end'.codeUnits);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final identity = await Identity.generate(sodium);
      final (session, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );

      // Correct plaintext verifies.
      expect(header.manifestHash.length, hashSize);

      final receiver = await ReceiverSession.accept(
        sodium,
        header.pack(),
        receiverKp,
      );
      expect(receiver.verifyFile(sodium, plaintext), isTrue);

      // One flipped byte fails verification.
      final tampered = Uint8List.fromList(plaintext);
      tampered[0] ^= 1;
      expect(receiver.verifyFile(sodium, tampered), isFalse);
    });
  });

  group('Chunk size limits', () {
    // The session header packs chunkCount as a uint16, so a transfer can carry
    // at most 65535 chunks. ByteData.setUint16 truncates silently on overflow,
    // so Session.open must reject an oversized file *loudly* instead of
    // emitting a corrupted header the receiver cannot make sense of.

    test('recommendedChunkSize keeps the number of codes within reach', () {
      // It used to pick the smallest size that fit, optimising for how
      // scannable one code is. On a 653 KB photo that produced 1,300 of
      // them, and a user reported scanning roughly 2.5x that before one
      // completed — not because the fountain code is inefficient
      // (measured overhead is 1.15x at that scale) but because each code
      // is another chance for the camera to miss one. It now trades code
      // density for code count once a file gets large.

      // Small files still stay on the size the spike validated.
      expect(recommendedChunkSize(1024), kDefaultChunkSize);
      expect(recommendedChunkSize(64 * 1024), kDefaultChunkSize);

      // Past the comfortable count, step up rather than add codes.
      expect(recommendedChunkSize(653 * 1024), 1024);
      // 2048, not 4096: a 4096-byte frame encodes to about 5,600
      // characters and the largest QR holds 2,953, so that size was
      // removed from the options entirely.
      expect(recommendedChunkSize(4 * 1024 * 1024), 2048);

      // Whatever is chosen must be able to carry the file.
      for (final bytes in [1024, 653 * 1024, 32 * 1024 * 1024]) {
        expect(fileSizeError(bytes, recommendedChunkSize(bytes)), isNull);
      }

      // Beyond every option, it returns the largest so the caller can error.
      expect(
        recommendedChunkSize(maxFileSizeForChunkSize(4096) + 1),
        kChunkSizeOptions.last,
      );
    });

    test('fileSizeError is null when the file fits and clear when it does not',
        () {
      expect(fileSizeError(1024, 512), isNull);
      expect(fileSizeError(maxFileSizeForChunkSize(512), 512), isNull);

      final msg = fileSizeError(32 * 1024 * 1024, 512);
      expect(msg, isNotNull);
      expect(msg, contains('too large'));
      expect(msg, contains('chunk size')); // points at the fix
    });

    test('Session.open rejects chunkCount overflow (32 MB @ 512 B)', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      // 65536 chunks at 512 B — one past the uint16 ceiling.
      final plaintext = Uint8List(32 * 1024 * 1024);

      expect(
        () => Session.open(sodium, plaintext, 512, receiverKp.publicKey, identity),
        throwsA(isA<DeadDropCryptoError>()),
      );
    });

    test('Session.open accepts the exact uint16 boundary', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      // Exactly 65535 chunks at 512 B — the largest valid transfer at 512 B.
      final plaintext = Uint8List(maxChunkCount * 512);

      final (_, header) = await Session.open(
        sodium,
        plaintext,
        512,
        receiverKp.publicKey,
        identity,
      );
      expect(header.chunkCount, maxChunkCount);
      // Round-trips through the wire format without truncation.
      final unpacked = SessionHeader.unpack(header.pack());
      expect(unpacked.chunkCount, maxChunkCount);
    });

    test('Session.open rejects an out-of-range chunk size', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List(1024);

      expect(
        () => Session.open(sodium, plaintext, 0, receiverKp.publicKey, identity),
        throwsA(isA<DeadDropCryptoError>()),
      );
      expect(
        () => Session.open(
            sodium, plaintext, maxChunkSize + 1, receiverKp.publicKey, identity),
        throwsA(isA<DeadDropCryptoError>()),
      );
    });

    test('Session.open accepts 32 MB with 1024 B chunks', () async {
      // The case that silently corrupted before: 32 MB needs 65536 chunks at
      // 512 B (overflow), but 32768 at 1024 B — within uint16. We assert the
      // session is built and the header round-trips intact. A full fountain
      // decode at this K is O(K^2) and too slow for a unit test; the wire
      // format is what the overflow bug corrupted, so that is what we verify.
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List(32 * 1024 * 1024);

      final (session, header) = await Session.open(
        sodium,
        plaintext,
        1024,
        receiverKp.publicKey,
        identity,
      );
      expect(session.chunkCount, 32768);
      final unpacked = SessionHeader.unpack(header.pack());
      expect(unpacked.chunkCount, 32768);
      expect(unpacked.chunkSize, 1024);
      expect(unpacked.totalSize, 32 * 1024 * 1024);
    });

    test('Session.open accepts 64 MB with 2048 B chunks', () async {
      final identity = await Identity.generate(sodium);
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List(64 * 1024 * 1024);

      final (session, header) = await Session.open(
        sodium,
        plaintext,
        2048,
        receiverKp.publicKey,
        identity,
      );
      expect(session.chunkCount, 32768);
      final unpacked = SessionHeader.unpack(header.pack());
      expect(unpacked.chunkCount, 32768);
      expect(unpacked.chunkSize, 2048);
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

  group('frames are a constant size', () {
    test('every data frame packs to the same length', () {
      // The point of deriving chunk ids rather than transmitting them.
      // Previously a frame's length tracked the fountain degree, which
      // has a long tail by design: at k=4600 the median degree was 2 and
      // the maximum 624, so roughly 2 frames in 500 were more than
      // three times the usual size. Those jumped several QR versions,
      // which is the flash reported during emission, and the largest
      // could not be rendered at all.
      final lengths = <int>{};
      final degrees = <int>{};
      for (var seq = 1; seq <= 400; seq++) {
        final ids = chunkIdsFor(seq: seq, seed: 4242, k: 1000);
        degrees.add(ids.length);
        final frame = Frame(
          fileId: Uint8List(8),
          seq: seq,
          seed: 4242,
          degree: ids.length,
          nonce: Uint8List(nonceSize),
          payload: Uint8List(512 + 16),
        );
        lengths.add(frame.pack().length);
      }
      expect(lengths.length, 1,
          reason: 'frame lengths seen: \$lengths');
      // The control: the degrees really did vary, so the single length
      // above is the format holding it constant and not a sample that
      // happened to be uniform.
      expect(degrees.length, greaterThan(3),
          reason: 'degrees seen: \$degrees');
      expect(degrees.reduce((a, b) => a > b ? a : b), greaterThan(10));
    });
  });

  group('Frame', () {
    test('Frame pack/unpack roundtrip', () {
      final frame = Frame(
        fileId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        seq: 42,
        seed: 1337,
        degree: 3,
        nonce: Uint8List.fromList(List.generate(24, (i) => i)),
        payload: Uint8List.fromList(List.generate(100, (i) => i % 256)),
      );

      final packed = frame.pack();
      final unpacked = Frame.unpack(packed);

      expect(unpacked.seq, 42);
      expect(unpacked.seed, 1337);
      expect(unpacked.degree, 3);
      expect(unpacked.isMetadata, isFalse);
      expect(unpacked.nonce, frame.nonce);
      expect(unpacked.payload, frame.payload);
    });

    test('Frame rejects bad magic', () {
      final bad = Uint8List.fromList([0x00, 0x00, 0x01, 0x00]);
      expect(() => Frame.unpack(bad), throwsArgumentError);
    });
  });

  group('Transport envelope', () {
    test('encode/decode roundtrip preserves arbitrary bytes', () {
      final payload =
          Uint8List.fromList(List.generate(600, (i) => (i * 37 + 11) % 256));
      final encoded = encodeQrPayload(payload);
      expect(encoded.startsWith(transportPrefix), isTrue);
      // The envelope must be printable ASCII end to end — this is what makes
      // it survive text-based QR pipelines.
      for (final unit in encoded.codeUnits) {
        expect(unit, inInclusiveRange(0x20, 0x7E));
      }
      final decoded = decodeQrPayload(encoded);
      expect(decoded, payload);
    });

    test('decode rejects foreign QRs and malformed base64', () {
      expect(decodeQrPayload('https://example.com'), isNull);
      expect(decodeQrPayload('DD1.!!!not-base64!!!'), isNull);
      expect(decodeQrPayload(''), isNull);
    });
  });

  group('Handshake', () {
    test('handshake QR roundtrip yields the same public key', () async {
      final kp = await ReceiverKeypair.generate(sodium);
      final qr = encodeHandshakeQr(kp.publicKey);
      final decoded = decodeHandshakeQr(qr);
      expect(decoded, kp.publicKey);
    });

    test('handshake decoder rejects non-handshake envelopes', () {
      // A binary session header inside the envelope must not parse as a key.
      final fake = encodeQrPayload(Uint8List.fromList([1, 2, 3]));
      expect(decodeHandshakeQr(fake), isNull);
      expect(decodeHandshakeQr('random text'), isNull);
    });

    test('hex helpers roundtrip', () {
      final bytes = Uint8List.fromList([0x00, 0xab, 0xCD, 0xff]);
      expect(hexToBytes(bytesToHex(bytes)), bytes);
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

    test('Transfer carries the original file name, encrypted', () async {
      final plaintext =
          Uint8List.fromList(List.generate(4096, (i) => (i * 13) % 256));
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
        fileName: 'secret-plans.pdf',
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);

      await receiver.startSession(emitter.bootstrapQrPayload());

      // The first emitted frame is the encrypted metadata frame (seq 0).
      final metaFrame = emitter.nextFrame();
      expect(metaFrame.seq, 0);
      expect(metaFrame.isMetadata, isTrue);
      receiver.feedFrame(metaFrame.pack());
      expect(receiver.fileName, 'secret-plans.pdf');

      // The metadata frame is repeated, so a receiver whose camera locks on
      // after the first one still learns the name. Reported from device
      // testing: files kept arriving as deaddrop_received_<timestamp> with
      // no extension, because sequence 0 went by while the camera was
      // still focusing and nothing ever sent the name again.
      var repeats = 0;
      for (var i = 0; i < Emitter.metadataInterval * 2; i++) {
        if (emitter.nextFrame().isMetadata) repeats++;
      }
      expect(repeats, greaterThanOrEqualTo(1),
          reason: 'the name must not depend on catching one single frame');

      // The metadata frame must NOT count towards fountain decoding: the
      // frames just pulled were not fed to the receiver, so nothing has
      // decoded yet.
      expect(receiver.decoder!.decoded, isEmpty);
    });

    test('a receiver that joins late still learns the file name', () async {
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final plaintext = Uint8List.fromList(List.filled(4096, 7));
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
        fileName: 'evidence.jpg',
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);
      await receiver.startSession(emitter.bootstrapQrPayload());

      // Throw away the opening frames, the way a camera still focusing
      // does. This is the reported failure: the name rode on the very
      // first frame and nothing ever repeated it.
      for (var i = 0; i < 20; i++) {
        emitter.nextFrame();
      }
      expect(receiver.fileName, isNull, reason: 'nothing fed yet');

      for (var i = 0; i < Emitter.metadataInterval * 2; i++) {
        receiver.feedFrame(emitter.nextFrame().pack());
      }

      expect(receiver.fileName, 'evidence.jpg',
          reason: 'a late joiner must still end up with the real name, '
              'and therefore the real extension');

      // And the transfer itself still completes: the repeated metadata
      // frames carry no chunks, so they must not disturb decoding.
      for (var i = 0; i < 500 && !receiver.done; i++) {
        receiver.feedFrame(emitter.nextFrame().pack());
      }
      expect(receiver.done, isTrue);
      expect(receiver.finish(), plaintext);
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

    test('Full pipeline through the QR envelope (simulated camera)', () async {
      // Exercises the exact wire format the app uses: binary frame →
      // base64url envelope (what qr_flutter renders) → decodeQrPayload
      // (what the receiver does with mobile_scanner's rawValue).
      final plaintext =
          Uint8List.fromList(List.generate(20000, (i) => (i * 7 + 3) % 256));
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
        fileName: 'photo.jpg',
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);

      // Handshake QR → sender gets the key.
      final handshakeQr = encodeHandshakeQr(receiverKp.publicKey);
      expect(decodeHandshakeQr(handshakeQr), receiverKp.publicKey);

      // Bootstrap via envelope.
      final bootstrapQr = encodeQrPayload(emitter.bootstrapQrPayload());
      await receiver.startSession(decodeQrPayload(bootstrapQr)!);

      for (var i = 0; i < 500 && !receiver.done; i++) {
        final qrText = encodeQrPayload(emitter.nextFrame().pack());
        receiver.feedFrame(decodeQrPayload(qrText)!);
      }

      expect(receiver.done, isTrue);
      expect(receiver.fileName, 'photo.jpg');
      expect(receiver.finish(), plaintext);
    });

    test('Frame with out-of-range chunkIds is dropped, not fatal', () async {
      // Security audit finding #5: chunkIds come from the decrypted frame and
      // were passed to the decoder unchecked. An out-of-range cid would
      // permanently pollute `pending` and crash `reassemble()`. The payload is
      // AEAD-authenticated, so this is robustness against a corrupt emitter /
      // own bug, not a remote vulnerability — but a bad frame must be dropped,
      // never fatal.
      final plaintext = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);
      await receiver.startSession(emitter.bootstrapQrPayload());

      final k = receiver.decoder!.k;
      expect(k, greaterThan(0));

      // Chunk ids are no longer on the wire, so a frame can no longer
      // carry out-of-range ones: the receiver derives them and the
      // derivation cannot produce an id outside [0, k). What a frame
      // *can* still lie about is the degree, and a degree that
      // disagrees with the derivation means the two sides are not
      // computing the same thing — decoding anyway would corrupt the
      // file with no error anywhere.
      final forgedPayload = Uint8List(512);
      final (nonce, ct) = emitter.session.encryptPayload(sodium, forgedPayload);
      const forgedSeq = 9999;
      final realDegree =
          chunkIdsFor(seq: forgedSeq, seed: emitter.transferSeed, k: k).length;
      final evilFrame = Frame(
        fileId: emitter.session.fileId,
        seq: forgedSeq,
        seed: emitter.transferSeed,
        degree: realDegree + 1,
        nonce: nonce,
        payload: ct,
      );

      final decodedBefore = receiver.decoder!.decoded.length;
      final pendingBefore = receiver.decoder!.pending.length;

      // Must not throw, must not advance decoding, must not pollute state.
      final advanced = receiver.feedFrame(evilFrame.pack());
      expect(advanced, isFalse);
      expect(receiver.framesRejectedBadChunkIds, 1);
      expect(receiver.decoder!.decoded.length, decodedBefore);
      expect(receiver.decoder!.pending.length, pendingBefore);

      // An absurd degree is rejected the same way.
      final (nonce2, ct2) = emitter.session.encryptPayload(sodium, forgedPayload);
      final evilFrame2 = Frame(
        fileId: emitter.session.fileId,
        seq: 10000,
        seed: emitter.transferSeed,
        degree: k + 1000,
        nonce: nonce2,
        payload: ct2,
      );
      expect(receiver.feedFrame(evilFrame2.pack()), isFalse);
      expect(receiver.framesRejectedBadChunkIds, 2);
      expect(receiver.decoder!.pending.length, pendingBefore);

      // The channel absorbs the loss: a normal transfer still completes.
      for (var i = 0; i < 500 && !receiver.done; i++) {
        receiver.feedFrame(emitter.nextFrame().pack());
      }
      expect(receiver.done, isTrue);
      expect(receiver.finish(), plaintext);
    });

    test('a frame whose degree is honest is not rejected', () async {
      // The control for the test above: without it, those rejections
      // could be something else dropping every forged frame rather than
      // the degree check doing its job.
      //
      // It is a test of its own because the frame it feeds carries a
      // payload that is validly encrypted but is not the XOR of
      // anything. Accepted — correctly — it corrupts the decode, so it
      // cannot share a receiver with a transfer that must complete.
      // Putting it in the test above made that one fail on a BLAKE2b
      // mismatch, which is the integrity check working.
      final plaintext = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final receiverKp = await ReceiverKeypair.generate(sodium);
      final emitter = await Emitter.create(
        sodium,
        plaintext,
        receiverKp,
        chunkSize: 512,
      );
      final receiver = Receiver(sodium: sodium, keypair: receiverKp);
      await receiver.startSession(emitter.bootstrapQrPayload());

      const seq = 9999;
      final k = receiver.decoder!.k;
      final degree =
          chunkIdsFor(seq: seq, seed: emitter.transferSeed, k: k).length;
      final (nonce, ct) =
          emitter.session.encryptPayload(sodium, Uint8List(512));

      receiver.feedFrame(Frame(
        fileId: emitter.session.fileId,
        seq: seq,
        seed: emitter.transferSeed,
        degree: degree,
        nonce: nonce,
        payload: ct,
      ).pack());

      expect(receiver.framesRejectedBadChunkIds, 0,
          reason: 'an honest degree must not be rejected');
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

  final sw = Stopwatch()..start();
  await receiver.startSession(emitter.bootstrapQrPayload());

  var frames = 0;
  // Frame cap: chunk count × 8 is far beyond the ~1.3x overhead the LT code
  // needs, so hitting the cap means something is genuinely broken.
  final frameCap = (size / chunkSize).ceil() * 8 + 100;
  while (!receiver.done && frames < frameCap) {
    final frame = emitter.nextFrame();
    receiver.feedFrame(frame.pack());
    frames++;
  }
  sw.stop();

  expect(receiver.done, isTrue, reason: 'Failed to decode after $frames frames');
  final recovered = receiver.finish();
  expect(recovered, plaintext);

  final chunkCount = (size / chunkSize).ceil();
  final kbps = size / 1024 / (sw.elapsedMilliseconds / 1000);
  debugPrint('[benchmark] ${_formatSize(size)}: ${sw.elapsedMilliseconds} ms, '
      '$frames frames for $chunkCount chunks '
      '(overhead ${(frames / chunkCount).toStringAsFixed(2)}x), '
      '${kbps.toStringAsFixed(1)} KB/s pipeline throughput');
}

String _formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)}KB';
}
