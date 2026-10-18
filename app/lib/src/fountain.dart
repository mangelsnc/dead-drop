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

int sampleDegree(Random rng, List<double> cdf) {
  final u = rng.nextDouble();
  for (var d = 0; d < cdf.length; d++) {
    if (u <= cdf[d]) return d + 1;
  }
  return cdf.length;
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
  (List<int>, Uint8List) makeFrame(int seq, int seed) {
    final rng = Random((seed << 32) ^ seq);
    final degree = min(sampleDegree(rng, cdf), k);
    final chunkIds = <int>[];
    final indices = List<int>.generate(k, (i) => i)..shuffle(rng);
    for (var i = 0; i < degree; i++) {
      chunkIds.add(indices[i]);
    }
    chunkIds.sort();

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

  LTDecoder({required this.k, required this.chunkSize});

  bool get done => decoded.length == k;

  double get efficiency =>
      framesReceived > 0 ? framesUseful / framesReceived : 0.0;

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
