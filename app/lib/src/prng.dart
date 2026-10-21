/// prng.dart — deterministic, platform-independent pseudo-random generator
/// for the fountain code.
///
/// Why not `dart:math.Random`?
/// ---------------------------
/// The fountain encoder must produce a *bit-for-bit identical* frame stream on
/// every platform (emitter and receiver derive the same frames from the same
/// `(seed, seq)` pair — see technical-spec.md §2.3). `dart:math.Random(seed)`
/// fails this twice:
///
/// 1. **It truncates the seed to 32 bits.** The old code did
///    `Random((seed << 32) ^ seq)` — the high 32 bits (the whole `seed`) were
///    silently discarded, so every transfer used the same frame sequence
///    regardless of `seed`.
/// 2. **Its algorithm is unspecified.** The Dart SDK does not guarantee the
///    same output sequence across platforms (native vs. web/JS) or across SDK
///    versions. On web, integer arithmetic additionally degrades to IEEE-754
///    doubles, so `<< 32` is lossy there as well.
///
/// What this is — and what it is NOT
/// ----------------------------------
/// This is a *selection algorithm* for the LT fountain code: it decides which
/// source chunks are XORed into each emitted frame. It is **not** a
/// cryptographic primitive and is never used for keys, nonces, or anything
/// security-sensitive — all of that stays in libsodium (see crypto.dart).
/// Predictability here is harmless to confidentiality (payloads are AEAD-
/// encrypted with random nonces); what matters is *determinism* and *even
/// mixing* of the `(seed, seq)` pair.
///
/// Construction
/// ------------
/// - `mixSeed(seed, seq)`: splitmix32 finalizer (Stafford's variant) over
///   `seed + seq·φ` — a bijective 32-bit mixing function, so distinct
///   `(seed, seq)` pairs map to distinct generator states with high
///   probability. All arithmetic is explicitly masked to 32 bits, which Dart
///   performs identically on native and on the web (integers are compiled to
///   32-bit ops when the compiler can prove the range — and here it can).
/// - `DeterministicRandom`: xorshift32 (Marsaglia) driven by that state.
///   Period 2³²−1, fully specified, trivially portable to any language with
///   32-bit integers — including the Python spike.
library;

/// 32-bit multiplication that is exact on every platform, including the web.
///
/// Dart compiled to JavaScript represents integers as IEEE-754 doubles, where
/// precision is lost above 2^53 — a plain `a * b` of two 32-bit values can
/// reach 2^64 and silently corrupt the low bits. Splitting into 16-bit halves
/// keeps every partial product below 2^32, so the result is exact everywhere.
int _mul32(int a, int b) {
  final aLo = a & 0xFFFF;
  final aHi = (a >> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  final bHi = (b >> 16) & 0xFFFF;
  // Only the low 32 bits of the product are needed:
  // (aHi*bHi << 32) vanishes, (aHi*bLo + aLo*bHi) contributes its low 16 bits.
  final mid = ((aHi * bLo + aLo * bHi) & 0xFFFF) << 16;
  return (aLo * bLo + mid) & 0xFFFFFFFF;
}

/// Mixes a 32-bit [seed] and a frame sequence number [seq] into a single
/// 32-bit generator state.
///
/// splitmix32-style finalizer: bijective over 32 bits, so no entropy is lost
/// (unlike `(seed << 32) ^ seq` fed into a 32-bit-truncating RNG, where the
/// seed vanished entirely).
int mixSeed(int seed, int seq) {
  int z = (seed + _mul32(seq, 0x9E3779B9)) & 0xFFFFFFFF;
  z = _mul32(z ^ (z >> 16), 0x21F0AAAD);
  z = _mul32(z ^ (z >> 15), 0x735A2D97);
  z = (z ^ (z >> 15)) & 0xFFFFFFFF;
  return z;
}

/// xorshift32 — a minimal, fully specified deterministic PRNG.
///
/// The sequence depends only on the constructor argument, on every platform
/// and every Dart SDK version. State zero is absorbing (xorshift of 0 is 0
/// forever), so it is remapped to a fixed non-zero constant.
class DeterministicRandom {
  int _state;

  DeterministicRandom(int seed)
      : _state = (seed & 0xFFFFFFFF) == 0 ? 0x6D2B79F5 : (seed & 0xFFFFFFFF);

  /// Next 32-bit value (unsigned).
  int nextUint32() {
    var x = _state;
    x = (x ^ ((x << 13) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    x = (x ^ (x >> 17)) & 0xFFFFFFFF;
    x = (x ^ ((x << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    _state = x;
    return x;
  }

  /// Uniform double in [0, 1) with 32 bits of resolution.
  double nextDouble() => nextUint32() / 0x100000000;

  /// Uniform integer in [0, max). Rejects `max <= 0`.
  ///
  /// Uses multiply-and-divide (Lemire's trick, spelled with `/` instead of
  /// `>> 32`): `(nextUint32() * max) / 2^32` floored is uniform for any
  /// `max <= 2^32` and — unlike a 32-bit shift — behaves identically when
  /// compiled to JavaScript, where bitwise ops truncate to 32 bits. The
  /// product stays below 2^53 for any realistic `max`, so the double
  /// arithmetic on the web is exact.
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max', 'must be positive');
    }
    return (nextUint32() * max) ~/ 0x100000000;
  }
}
