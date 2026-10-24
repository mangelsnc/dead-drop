/// vault_keys.dart — the vault's key hierarchy: wrap and unwrap data keys.
///
/// Files are encrypted under a per-environment data key, never directly
/// under the passphrase-derived key. The data key is then sealed
/// ("wrapped") under a key-encryption key (KEK, see pwhash.dart) derived
/// from the operator's passphrase. This indirection is what makes
/// self-destruct practical: discarding the handful of bytes that make up a
/// [WrappedKey] renders every file in that environment unrecoverable,
/// without needing to overwrite the (much larger) file contents on flash
/// storage, where wear-levelling makes erasure unprovable.
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'pwhash.dart';

/// Size, in bytes, of the data key [newDataKey] produces.
///
/// 32 bytes matches `crypto_secretbox`'s key size: the data key is itself
/// used as a `crypto_secretbox` key when it encrypts file contents.
const int _kDataKeyBytes = 32;

/// A data key sealed under a passphrase-derived KEK.
///
/// Holds everything needed to re-derive the KEK and open the seal — the
/// salt for [deriveKek] and the secretbox nonce — plus the sealed
/// ciphertext itself. All three are safe to store unencrypted alongside the
/// vault environment: none of them is secret on its own, and together they
/// are useless without the passphrase.
class WrappedKey {
  WrappedKey({
    required this.salt,
    required this.nonce,
    required this.ciphertext,
  });

  /// Salt used to derive the KEK that sealed this key. See [deriveKek].
  final Uint8List salt;

  /// `crypto_secretbox` nonce used when sealing the data key.
  final Uint8List nonce;

  /// The data key, sealed (encrypted + authenticated) under the KEK.
  final Uint8List ciphertext;

  /// Serialises this [WrappedKey] to bytes for storage.
  ///
  /// Layout: `[salt len: 1 byte][salt][nonce len: 1 byte][nonce][ciphertext]`.
  /// Salt and nonce are length-prefixed rather than assumed fixed-size so
  /// this format tolerates future changes to [kVaultSaltBytes] or the
  /// secretbox nonce size without a migration; the ciphertext runs to the
  /// end of the buffer since its length is implied by what remains.
  Uint8List pack() {
    final out = BytesBuilder();
    out.addByte(salt.length);
    out.add(salt);
    out.addByte(nonce.length);
    out.add(nonce);
    out.add(ciphertext);
    return out.toBytes();
  }

  /// Parses bytes produced by [pack] back into a [WrappedKey].
  static WrappedKey unpack(Uint8List bytes) {
    var offset = 0;

    final saltLen = bytes[offset];
    offset += 1;
    final salt = bytes.sublist(offset, offset + saltLen);
    offset += saltLen;

    final nonceLen = bytes[offset];
    offset += 1;
    final nonce = bytes.sublist(offset, offset + nonceLen);
    offset += nonceLen;

    final ciphertext = bytes.sublist(offset);

    return WrappedKey(salt: salt, nonce: nonce, ciphertext: ciphertext);
  }
}

/// Generates a fresh, random 32-byte data key.
///
/// One data key per vault environment: it is the key files are actually
/// encrypted under, and the only thing [wrapDataKey] protects.
Uint8List newDataKey(SodiumSumo sodium) =>
    sodium.randombytes.buf(_kDataKeyBytes);

/// Seals [dataKey] under a KEK derived from [passphrase].
///
/// Generates a fresh salt (for [deriveKek]) and nonce (for the secretbox)
/// on every call, so wrapping the same data key under the same passphrase
/// twice produces different output each time — required for the "two wraps
/// differ" property and generally good hygiene for nonce reuse.
WrappedKey wrapDataKey(
  SodiumSumo sodium,
  String passphrase,
  Uint8List dataKey,
) {
  final salt = newSalt(sodium);
  final kek = deriveKek(sodium, passphrase, salt);
  final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);

  try {
    final ciphertext = sodium.crypto.secretBox.easy(
      message: dataKey,
      nonce: nonce,
      key: kek,
    );
    return WrappedKey(salt: salt, nonce: nonce, ciphertext: ciphertext);
  } finally {
    kek.dispose();
  }
}

/// Attempts to recover the data key sealed in [wrapped] using [passphrase].
///
/// Returns `null` when [passphrase] is wrong, rather than throwing. This is
/// load-bearing: an exception is an easy-to-distinguish error path, and the
/// coercion-resistance design depends on a wrong passphrase being
/// indistinguishable from there being no environment there at all. The only
/// failure this catches is the secretbox authentication failure — anything
/// else (e.g. a malformed [wrapped]) is still a bug and propagates.
Uint8List? unwrapDataKey(
  SodiumSumo sodium,
  String passphrase,
  WrappedKey wrapped,
) {
  final kek = deriveKek(sodium, passphrase, wrapped.salt);

  try {
    return sodium.crypto.secretBox.openEasy(
      cipherText: wrapped.ciphertext,
      nonce: wrapped.nonce,
      key: kek,
    );
  } on SodiumException {
    // Authentication failure: wrong passphrase (wrong KEK). Not an error
    // the caller should be able to distinguish from "no such environment".
    return null;
  } finally {
    kek.dispose();
  }
}
