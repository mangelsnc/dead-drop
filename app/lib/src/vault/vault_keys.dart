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

/// `crypto_secretbox`'s MAC size, in bytes — a fixed libsodium constant
/// (`crypto_secretbox_MACBYTES`), not configurable, hence hardcoded rather
/// than read off a [SodiumSumo] instance (unavailable to the static
/// [WrappedKey.unpack]). Any secretbox ciphertext, including a wrapped
/// data key's, is at least this long; used by [WrappedKey.unpack] to reject
/// a ciphertext too short to possibly be real before it ever reaches
/// `secretBox.openEasy`, which otherwise throws a bare `RangeError` on such
/// input instead of the library's usual [SodiumException].
const int _kSecretBoxMacBytes = 16;

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
  ///
  /// Throws [MalformedWrappedKeyException] — never a bare [RangeError] — on
  /// truncated or otherwise malformed input. This matters once the bytes
  /// come from disk (Task 5): a corrupt slot file must fail in a shape the
  /// caller can recognise and handle deliberately, not crash the way an
  /// unrelated indexing bug would. It is deliberately a *different*
  /// exception type from the wrong-passphrase path ([unwrapDataKey] returning
  /// null): corruption and a wrong passphrase are different failures and
  /// callers should not be tempted to collapse them into one message that
  /// then either alarms a coerced user over a harmless disk error, or
  /// quietly turns real corruption into what looks like "no such
  /// environment". The exception carries no information about *which* slot
  /// failed beyond what the caller already knows by construction (it is the
  /// one asking to unpack this buffer), so it does not reveal anything about
  /// the other slot.
  static WrappedKey unpack(Uint8List bytes) {
    var offset = 0;

    final saltLen = _readByte(bytes, offset, 'salt length');
    offset += 1;
    final salt = _readSlice(bytes, offset, saltLen, 'salt');
    offset += saltLen;

    final nonceLen = _readByte(bytes, offset, 'nonce length');
    offset += 1;
    final nonce = _readSlice(bytes, offset, nonceLen, 'nonce');
    offset += nonceLen;

    // The ciphertext runs to the end of the buffer; it must be at least a
    // MAC's worth of bytes (a real WrappedKey's always is — see
    // _kSecretBoxMacBytes) or this cannot be a genuine secretbox ciphertext.
    // Checking this here, not just non-emptiness, matters because
    // `secretBox.openEasy` throws a bare RangeError (not a SodiumException)
    // on a too-short ciphertext — exactly the kind of crash this method
    // exists to turn into a clean, typed failure instead.
    if (bytes.length - offset < _kSecretBoxMacBytes) {
      throw MalformedWrappedKeyException('ciphertext too short');
    }
    final ciphertext = bytes.sublist(offset);

    return WrappedKey(salt: salt, nonce: nonce, ciphertext: ciphertext);
  }

  static int _readByte(Uint8List bytes, int offset, String field) {
    if (offset >= bytes.length) {
      throw MalformedWrappedKeyException('truncated before $field');
    }
    return bytes[offset];
  }

  static Uint8List _readSlice(
    Uint8List bytes,
    int offset,
    int length,
    String field,
  ) {
    if (offset + length > bytes.length) {
      throw MalformedWrappedKeyException('truncated $field');
    }
    return bytes.sublist(offset, offset + length);
  }
}

/// Thrown by [WrappedKey.unpack] when the bytes are not a well-formed
/// [WrappedKey] — truncated, or otherwise too short to contain the fields
/// [WrappedKey.pack] writes.
///
/// Deliberately distinct from "wrong passphrase" ([unwrapDataKey] returning
/// null): this means the bytes on disk are damaged, not that an
/// authentication check failed. [message] is a short, generic description
/// (e.g. "truncated salt") — never anything derived from the bytes
/// themselves — so catching and logging it cannot leak slot contents.
class MalformedWrappedKeyException implements Exception {
  MalformedWrappedKeyException(this.message);

  final String message;

  @override
  String toString() => 'MalformedWrappedKeyException: $message';
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
