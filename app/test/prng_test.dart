/// Tests for the deterministic PRNG (prng.dart) and its use in the fountain
/// encoder.
///
/// These are the regression tests for security-audit finding #2:
/// `Random((seed << 32) ^ seq)` truncated the seed to 32 bits, so the transfer
/// seed had no effect and `dart:math.Random`'s unspecified algorithm was the
/// only thing standing between emitter and receiver divergence.
///
/// The golden vectors below were produced by an independent Python
/// reimplementation of the same construction (splitmix32-style mixing +
/// xorshift32). They pin the exact bit stream: if any platform or SDK change
/// alters the output, these tests fail — which is exactly what must happen
/// before two devices silently disagree on a transfer.
library;

import 'dart:typed_data';

import 'package:dead_drop/src/fountain.dart';
import 'package:dead_drop/src/prng.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mixSeed', () {
    // Golden vectors from the reference implementation.
    test('matches golden vectors', () {
      expect(mixSeed(0xDEADBEEF, 5), 0xF44A515F);
      expect(mixSeed(0x12345678, 5), 0x45FA27A7);
      expect(mixSeed(0x00000000, 0), 0x00000000);
      expect(mixSeed(0x00000001, 0), 0x86D2FA73);
      expect(mixSeed(0xFFFFFFFF, 0xFFFFFFFF), 0xD267144C);
      expect(mixSeed(42, 0), 0x28082AC6);
      expect(mixSeed(42, 1), 0x20E44818);
    });

    test('seed survives mixing (regression: audit finding #2)', () {
      // The old code truncated `(seed << 32) ^ seq` to 32 bits, so both of
      // these collapsed to the same generator state (low32 == 5).
      expect(mixSeed(0xDEADBEEF, 5), isNot(mixSeed(0x12345678, 5)));
    });

    test('different seq with same seed produces different states', () {
      final states = {for (var seq = 0; seq < 1000; seq++) mixSeed(42, seq)};
      // Bijective mixing: collisions should be essentially nonexistent.
      expect(states.length, greaterThan(990));
    });
  });

  group('DeterministicRandom (xorshift32)', () {
    test('matches golden stream', () {
      final rng = DeterministicRandom(mixSeed(0xDEADBEEF, 5));
      final expected = [
        0x725C238F, 0x339AABB9, 0xBB5AA12F, 0x0099E490,
        0xBD74A835, 0x26319D8C, 0xA582FECC, 0xB13B7FC1,
      ];
      for (final e in expected) {
        expect(rng.nextUint32(), e);
      }
    });

    test('different seeds produce different streams', () {
      final a = DeterministicRandom(mixSeed(0xDEADBEEF, 5));
      final b = DeterministicRandom(mixSeed(0x12345678, 5));
      final streamA = [for (var i = 0; i < 8; i++) a.nextUint32()];
      final streamB = [for (var i = 0; i < 8; i++) b.nextUint32()];
      expect(streamA, isNot(streamB));
    });

    test('zero seed is remapped (xorshift fixed point)', () {
      // xorshift(0) == 0 forever; the constructor must remap it.
      final rng = DeterministicRandom(0);
      expect(rng.nextUint32(), 0x40AEC71F);
    });

    test('nextDouble is in [0, 1)', () {
      final rng = DeterministicRandom(12345);
      for (var i = 0; i < 1000; i++) {
        final d = rng.nextDouble();
        expect(d, greaterThanOrEqualTo(0.0));
        expect(d, lessThan(1.0));
      }
    });

    test('nextInt stays in range and rejects non-positive max', () {
      final rng = DeterministicRandom(999);
      for (var i = 0; i < 1000; i++) {
        final v = rng.nextInt(7);
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThan(7));
      }
      expect(() => rng.nextInt(0), throwsArgumentError);
      expect(() => rng.nextInt(-1), throwsArgumentError);
    });
  });

  group('LTEncoder determinism', () {
    List<Uint8List> makeChunks(int k, int size) => List.generate(
          k,
          (i) =>
              Uint8List.fromList(List.generate(size, (j) => (i + j) % 256)),
        );

    test('golden chunk-id vectors (k=10)', () {
      final encoder = LTEncoder(makeChunks(10, 64));
      final cases = <(int, int), List<int>>{
        (0, 42): [5, 9],
        (1, 42): [2, 4],
        (5, 0xDEADBEEF): [1, 4],
        (5, 0x12345678): [8],
      };
      for (final entry in cases.entries) {
        final (seq, seed) = entry.key;
        final (ids, _) = encoder.makeFrame(seq, seed);
        expect(ids, entry.value, reason: 'k=10 seq=$seq seed=$seed');
      }
    });

    test('golden chunk-id vectors (k=100 and k=1)', () {
      final enc100 = LTEncoder(makeChunks(100, 64));
      final (idsA, _) = enc100.makeFrame(0, 42);
      expect(idsA, [48, 92, 97]);
      final (idsB, _) = enc100.makeFrame(7, 0xDEADBEEF);
      expect(idsB, [
        7, 15, 16, 25, 26, 27, 31, 51, 52, 60, 68, 72, 77, 79, 80, 92, 97, 98,
      ]);

      final enc1 = LTEncoder(makeChunks(1, 64));
      final (idsC, _) = enc1.makeFrame(0, 42);
      expect(idsC, [0]);
    });

    test('same (seed, seq) reproduces the identical frame', () {
      final encoder = LTEncoder(makeChunks(50, 128));
      for (var seq = 0; seq < 20; seq++) {
        final (idsA, payloadA) = encoder.makeFrame(seq, 0xCAFEBABE);
        final (idsB, payloadB) = encoder.makeFrame(seq, 0xCAFEBABE);
        expect(idsA, idsB);
        expect(payloadA, payloadB);
      }
    });

    test('different seeds produce different frame sequences', () {
      final encoder = LTEncoder(makeChunks(50, 128));
      var differences = 0;
      for (var seq = 0; seq < 50; seq++) {
        final (idsA, _) = encoder.makeFrame(seq, 0xDEADBEEF);
        final (idsB, _) = encoder.makeFrame(seq, 0x12345678);
        if (idsA.length != idsB.length || !idsA.every(idsB.contains)) {
          differences++;
        }
      }
      // With the seed actually mixed in, essentially every frame differs.
      // (The old bug produced 0 differences here.)
      expect(differences, greaterThan(40));
    });

    test('roundtrip still decodes with the new generator', () {
      final chunks = makeChunks(10, 64);
      final encoder = LTEncoder(chunks);
      final decoder = LTDecoder(k: 10, chunkSize: 64);
      for (var seq = 0; seq < 100 && !decoder.done; seq++) {
        final (ids, payload) = encoder.makeFrame(seq, 42);
        decoder.addFrame(ids, payload);
      }
      expect(decoder.done, isTrue);
      expect(decoder.reassemble(), chunks.expand((c) => c).toList());
    });
  });
}
