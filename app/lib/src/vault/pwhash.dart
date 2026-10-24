/// pwhash.dart — Argon2id key derivation for the DeadDrop vault.
///
/// The vault protects files at rest with a passphrase, not a key, so a
/// passphrase -> key derivation step is required before anything can be
/// encrypted or decrypted. Argon2id is libsodium's memory-hard password
/// hash: it is deliberately slow and memory-expensive, which is what makes
/// brute-forcing a weak passphrase impractical. This file is the only place
/// `crypto_pwhash` is called — every other vault module receives a key, not
/// a passphrase.
///
/// `pwhash` is SUMO-ONLY in the `sodium` package: it is not exposed by
/// `package:sodium_libs/sodium_libs.dart` (the plain `Sodium` the rest of
/// the app uses today), only by `package:sodium/sodium_sumo.dart`'s
/// `SodiumSumo`. See the spike findings recorded in
/// docs/superpowers/plans/2026-10-24-vault-coercion.md for why, and for the
/// measured cost of these parameters.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// Size, in bytes, of the random salt stored alongside each vault
/// environment so two environments (or two vaults) never derive the same
/// key from the same passphrase.
const int kVaultSaltBytes = 16;

/// Size, in bytes, of the key [deriveKek] produces.
///
/// 32 bytes matches `crypto_secretbox`'s key size, which is what the key
/// hierarchy (Task 2) wraps with this derived key.
const int _kekBytes = 32;

/// Argon2id operations limit — the CPU-cost knob.
///
/// Fixed by the implementation plan; re-tuning requires updating the spec
/// and re-measuring (see the spike findings).
const int _opsLimit = 3;

/// Argon2id memory limit, in bytes (64 MiB) — the memory-hardness knob that
/// makes GPU/ASIC brute-forcing expensive.
///
/// Fixed by the implementation plan; re-tuning requires updating the spec
/// and re-measuring (see the spike findings).
const int _memLimit = 64 * 1024 * 1024;

/// Derives a 32-byte key-encryption key (KEK) from a passphrase and salt
/// using Argon2id.
///
/// Deterministic: the same passphrase and salt always produce the same
/// key, which is what lets the vault re-derive the KEK on every unlock
/// without storing it. [salt] should come from [newSalt] and be persisted
/// alongside the environment it protects — never reused across
/// environments or vaults.
Uint8List deriveKek(SodiumSumo sodium, String passphrase, Uint8List salt) {
  // crypto_pwhash takes the password as Int8List (signed bytes), not
  // Uint8List. UTF-8 bytes are 0-255; reinterpreting the same buffer as
  // signed is a lossless bit-for-bit view, not a conversion.
  final passwordBytes = Uint8List.fromList(utf8.encode(passphrase));
  final password = Int8List.view(
      passwordBytes.buffer, passwordBytes.offsetInBytes, passwordBytes.length);

  final key = sodium.crypto.pwhash(
    outLen: _kekBytes,
    password: password,
    salt: salt,
    opsLimit: _opsLimit,
    memLimit: _memLimit,
    alg: CryptoPwhashAlgorithm.argon2id13,
  );
  try {
    return key.extractBytes();
  } finally {
    key.dispose();
  }
}

/// Generates a fresh, random salt for use with [deriveKek].
///
/// A new salt must be generated for every vault environment — reusing a
/// salt across environments would let an attacker who recovers one KEK
/// test the same passphrase against the other environment.
Uint8List newSalt(SodiumSumo sodium) => sodium.randombytes.buf(kVaultSaltBytes);
