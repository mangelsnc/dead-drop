/// fountain.dart — Luby Transform (LT) fountain code for the QR channel.
///
/// Ported 1:1 from spike/src/fountain.py.
///
/// Why a fountain code?
/// --------------------
/// The QR channel is a *one-way, lossy broadcast*: the emitter loops frames on
/// screen, the camera catches what it catches. There is no back-channel to say
/// "resend frame 42". Classic ARQ is impossible, and plain repetition wastes
/// bandwidth (coupon-collector problem).
///
/// An LT code solves this: the emitter produces an *unbounded* stream of
/// encoded frames, each the XOR of a pseudo-random subset of the K source
/// chunks. The receiver only needs ~K·(1+ε) *any* frames (ε ≈ 5–10%) to decode
/// everything by belief propagation — no matter which frames were lost.
library;

import 'dart:math';
import 'dart:typed_data';

import 'prng.dart';

// ---------------------------------------------------------------------------
// Degree distribution (robust soliton, simplified)
// ---------------------------------------------------------------------------

List<double> robustSolitonCdf(int k, {double c = 0.05, double delta = 0.5}) {
  final rho = List<double>.filled(k + 1, 0.0);
  rho[1] = 1.0 / k;
  for (var d = 2; d <= k; d++) {
    rho[d] = 1.0 / (d * (d - 1));
  }

  final r = k > 1 ? c * log(k / delta) * sqrt(k) : 1.0;
  final tau = List<double>.filled(k + 1, 0.0);
  final pivot = r > 0 ? max(1, min((k / r).toInt(), k)) : 1;
  for (var d = 1; d < pivot; d++) {
    tau[d] = r / (d * k);
  }
  if (pivot >= 1 && pivot <= k) {
    tau[pivot] += r > 0 ? r * log(r / delta) / k : 0.0;
  }

  final z = rho.reduce((a, b) => a + b) + tau.reduce((a, b) => a + b);
  final cdf = <double>[];
  var acc = 0.0;
  for (var d = 1; d <= k; d++) {
    acc += (rho[d] + tau[d]) / z;
    cdf.add(acc);
  }
  cdf[cdf.length - 1] = 1.0;
  return cdf;
}

int sampleDegree(DeterministicRandom rng, List<double> cdf) {
  final u = rng.nextDouble();
  for (var d = 0; d < cdf.length; d++) {
    if (u <= cdf[d]) return d + 1;
  }
  return cdf.length;
}

// ---------------------------------------------------------------------------
// Chunk id derivation — shared by both sides
// ---------------------------------------------------------------------------

/// The chunk ids frame [seq] of a transfer with [k] chunks encodes, under
/// PRNG [seed].
///
/// This is the single definition of that mapping, used by the emitter to
/// build a frame and by the receiver to recover what the frame means. The
/// ids are not transmitted, so the two sides agreeing is not something
/// the wire can check for us: if this function ever behaves differently
/// on the two of them, transfers corrupt silently. Hence one
/// implementation, and `fountain_vectors_test.dart` pinning its output
/// against fixed expected values so a refactor cannot move it.
///
/// Deterministic for a given (seq, seed, k) on every platform: the
/// generator is the specified xorshift32 in prng.dart, NOT
/// `dart:math.Random` (which truncated `(seed << 32) ^ seq` to 32 bits —
/// silently discarding `seed` — and guarantees no stable sequence across
/// platforms or SDK versions).
///
/// [cdf] is [robustSolitonCdf] for [k]; it is a parameter only so the
/// encoder can reuse the one it already built.
List<int> chunkIdsFor({
  required int seq,
  required int seed,
  required int k,
  List<double>? cdf,
}) {
  final rng = DeterministicRandom(mixSeed(seed, seq));
  final degree = min(sampleDegree(rng, cdf ?? robustSolitonCdf(k)), k);
  // Fisher-Yates on the identity permutation, driven by the deterministic
  // generator. `List.shuffle` is not usable here: it takes `dart:math.Random`.
  final indices = List<int>.generate(k, (i) => i);
  for (var i = k - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = indices[i];
    indices[i] = indices[j];
    indices[j] = tmp;
  }
  return indices.sublist(0, degree)..sort();
}

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

class LTEncoder {
  final int k;
  final int chunkSize;
  final List<Uint8List> chunks;
  final List<double> cdf;

  LTEncoder(this.chunks)
      : k = chunks.length,
        chunkSize = chunks[0].length,
        cdf = robustSolitonCdf(chunks.length) {
    if (chunks.isEmpty) throw ArgumentError('need at least one chunk');
    for (final c in chunks) {
      if (c.length != chunkSize) {
        throw ArgumentError('chunks must be padded to equal size');
      }
    }
  }

  /// Produce encoded frame #(seq) under PRNG seed.
  /// Returns (chunk_ids, payload) where payload = XOR of the chosen chunks.
  ///
  /// The ids are not transmitted: the receiver recomputes them with
  /// [chunkIdsFor] from the same (seq, seed, k). See
  /// docs/decisions/0001-derive-chunk-ids-from-the-seed.md. They are
  /// returned here because the emitter still needs them to build the
  /// payload, and because the degree goes on the wire.
  (List<int>, Uint8List) makeFrame(int seq, int seed) {
    final chunkIds = chunkIdsFor(seq: seq, seed: seed, k: k, cdf: cdf);

    final payload = Uint8List(chunkSize);
    for (final cid in chunkIds) {
      final src = chunks[cid];
      for (var i = 0; i < chunkSize; i++) {
        payload[i] ^= src[i];
      }
    }
    return (chunkIds, payload);
  }
}

// ---------------------------------------------------------------------------
// Decoder (belief propagation / peeling)
// ---------------------------------------------------------------------------

class LTDecoder {
  final int k;
  final int chunkSize;
  final Map<int, Uint8List> decoded = {};
  final List<(Set<int>, Uint8List)> pending = [];
  int framesReceived = 0;
  int framesUseful = 0;

  /// Frames that carried information this decoder did not already have.
  ///
  /// Distinct from [framesUseful], which counts only the frames that
  /// resolved a chunk there and then. A frame that goes into [pending]
  /// has advanced the transfer even though it revealed nothing yet, and
  /// a fully redundant one has not. This is the quantity that rises
  /// steadily through a transfer, so it is what [progress] measures.
  int framesInformative = 0;

  LTDecoder({required this.k, required this.chunkSize});

  bool get done => decoded.length == k;

  double get efficiency =>
      framesReceived > 0 ? framesUseful / framesReceived : 0.0;

  /// Frames a transfer of [k] chunks typically needs, as a multiple of
  /// k.
  ///
  /// A fountain code needs more frames than there are chunks. Measured
  /// on this implementation: 1.22x at k=200, 1.13x at k=2048. The higher
  /// figure is used so the estimate does not habitually overshoot on
  /// small transfers.
  static const double expectedOverhead = 1.22;

  /// How far along the transfer is, from 0 to 1.
  ///
  /// Measured by useful frames received against the number such a
  /// transfer takes, because neither of the obvious alternatives works:
  ///
  /// `decoded.length / k` badly understates it. Belief propagation
  /// resolves almost nothing until it cascades, so a 1 MB transfer at
  /// 512-byte chunks showed 12 chunks of 2048 after 1024 frames and
  /// finished at 2308 -- it read as 1% when it was nearly half done, and
  /// was reported from a device as a stall.
  ///
  /// Counting pending frames overstates it instead. Frames cover nearly
  /// every chunk long before they can be resolved, so the bar reached
  /// its cap and sat there for roughly half the run -- reported as
  /// minutes stuck on the final 1%.
  ///
  /// Frames received is the one quantity that rises steadily throughout,
  /// which is what a progress bar is for. It is an estimate: a transfer
  /// may finish a little before or after the bar fills, so the value is
  /// capped just below 1 and only [done] puts it at 1.
  double get progress {
    if (k == 0) return 0;
    if (done) return 1;
    final expected = k * expectedOverhead;
    final ratio = framesInformative / expected;
    return ratio > 0.99 ? 0.99 : ratio;
  }

  /// Feed one encoded frame. Returns true if it made progress.
  bool addFrame(List<int> chunkIds, Uint8List payload) {
    framesReceived++;
    final ids = Set<int>.from(chunkIds);
    final buf = Uint8List.fromList(payload);

    // Peel with already-known chunks
    for (final cid in ids.toList()) {
      if (decoded.containsKey(cid)) {
        final known = decoded[cid]!;
        for (var i = 0; i < chunkSize; i++) {
          buf[i] ^= known[i];
        }
        ids.remove(cid);
      }
    }

    if (ids.isEmpty) return false; // fully redundant frame

    framesInformative++;

    if (ids.length == 1) {
      _resolve(ids.first, buf);
      return true;
    }

    pending.add((ids, buf));
    return false;
  }

  void _resolve(int cid, Uint8List chunk) {
    if (decoded.containsKey(cid)) return;
    decoded[cid] = chunk;
    framesUseful++;

    // Cascade: try to peel pending frames with this new chunk
    var changed = true;
    while (changed) {
      changed = false;
      final stillPending = <(Set<int>, Uint8List)>[];
      for (final (ids, buf) in pending) {
        final mutableIds = Set<int>.from(ids);
        final mutableBuf = Uint8List.fromList(buf);
        for (final knownId in mutableIds.toList()) {
          if (decoded.containsKey(knownId)) {
            final known = decoded[knownId]!;
            for (var i = 0; i < chunkSize; i++) {
              mutableBuf[i] ^= known[i];
            }
            mutableIds.remove(knownId);
          }
        }
        if (mutableIds.isEmpty) {
          changed = true; // frame became fully redundant
          continue;
        }
        if (mutableIds.length == 1) {
          decoded[mutableIds.first] = mutableBuf;
          framesUseful++;
          changed = true;
          continue;
        }
        stillPending.add((mutableIds, mutableBuf));
      }
      pending
        ..clear()
        ..addAll(stillPending);
    }
  }

  /// Return the K decoded chunks concatenated (still padded).
  Uint8List reassemble() {
    if (!done) {
      throw StateError('decode incomplete: ${decoded.length}/$k');
    }
    final out = Uint8List(k * chunkSize);
    for (var i = 0; i < k; i++) {
      out.setRange(i * chunkSize, (i + 1) * chunkSize, decoded[i]!);
    }
    return out;
  }
}
