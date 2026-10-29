/// crypto.dart — E2E encryption layer for DeadDrop.
///
/// Ported 1:1 from spike/src/crypto.py (PyNaCl → sodium).
///
/// Primitives (libsodium):
/// * Key exchange : X25519          (crypto_box / crypto_kx)
/// * Cipher       : XSalsa20-Poly1305 (crypto_secretbox / crypto_box)
/// * Signatures   : Ed25519         (crypto_sign) — sender authenticity
/// * Hash         : BLAKE2b         (file manifest integrity)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'utils.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const magic = [0x44, 0x44]; // "DD"
const version = 2; // v2: added senderVerifyKey to SessionHeader
const nonceSize = 24; // XSalsa20-Poly1305 nonce
const tagSize = 16; // Poly1305 tag
const pkSize = 32; // X25519 public key
const sigSize = 64; // Ed25519 signature
const hashSize = 32; // BLAKE2b-256 (libsodium crypto_generichash)
const fileIdSize = 8;

/// Wire-format limits.
///
/// `chunkCount` and `chunkSize` are both packed as **uint16** in the session
/// header (see [SessionHeader.pack]). `ByteData.setUint16` truncates silently
/// instead of throwing, so an out-of-range value would be written as garbage
/// and the receiver would fail incomprehensibly. We validate both against
/// these bounds *before* packing and fail loudly instead.
const maxChunkCount = 0xFFFF; // 65535 — largest value a uint16 holds
const maxChunkSize = 0xFFFF; // 65535 — uint16
const minChunkSize = 1;

/// The largest plaintext that can be transferred with a given [chunkSize]
/// without overflowing the uint16 `chunkCount` field.
int maxFileSizeForChunkSize(int chunkSize) => maxChunkCount * chunkSize;

class DeadDropCryptoError implements Exception {
  final String message;
  DeadDropCryptoError(this.message);
  @override
  String toString() => 'DeadDropCryptoError: $message';
}

// ---------------------------------------------------------------------------
// Identities
// ---------------------------------------------------------------------------

/// Long-term Ed25519 signing identity (per install, per user).
///
/// The identity is generated once on first run and persisted in secure
/// storage. It authenticates the sender: the receiver verifies the
/// session-header signature against this identity's public key.
class Identity {
  final KeyPair keyPair;

  Identity._(this.keyPair);

  /// Generate a fresh random identity. Used only on first run.
  static Future<Identity> generate(Sodium sodium) async {
    final key = sodium.crypto.sign.keyPair();
    return Identity._(key);
  }

  /// Reconstruct an identity from a 64-byte secret key (seed + public key).
  ///
  /// This is the format produced by [secretKeyBytes] and is what gets
  /// persisted in secure storage.
  static Identity fromSecretKeyBytes(Sodium sodium, Uint8List secretKeyBytes) {
    if (secretKeyBytes.length != 64) {
      throw ArgumentError(
        'Ed25519 secret key must be 64 bytes, got ${secretKeyBytes.length}',
      );
    }
    final publicKey = secretKeyBytes.sublist(32, 64);
    final keyPair = KeyPair(
      publicKey: Uint8List.fromList(publicKey),
      secretKey: SecureKey.fromList(sodium, secretKeyBytes),
    );
    return Identity._(keyPair);
  }

  Uint8List get verifyKey => keyPair.publicKey;

  /// The 64-byte secret key (seed || public key) for persistence.
  Uint8List get secretKeyBytes => keyPair.secretKey.extractBytes();

  /// Short human-readable fingerprint of this identity's public key.
  ///
  /// Returns the first 16 hex characters of the Ed25519 public key —
  /// enough for visual out-of-band comparison without being unwieldy.
  String get fingerprint => fingerprintOf(verifyKey);

  Uint8List sign(Sodium sodium, Uint8List data) {
    return sodium.crypto.sign.detached(
      message: data,
      secretKey: keyPair.secretKey,
    );
  }
}

/// Ephemeral X25519 keypair the receiver shows to the sender.
class ReceiverKeypair {
  final KeyPair keyPair;

  ReceiverKeypair._(this.keyPair);

  static Future<ReceiverKeypair> generate(Sodium sodium) async {
    final kp = sodium.crypto.box.keyPair();
    return ReceiverKeypair._(kp);
  }

  Uint8List get publicKey => keyPair.publicKey;
  SecureKey get privateKey => keyPair.secretKey;
}

// ---------------------------------------------------------------------------
// Session bootstrap
// ---------------------------------------------------------------------------

/// Everything the receiver needs to start decoding — sent once.
class SessionHeader {
  final Uint8List senderEphPk; // 32  ephemeral X25519 public key
  final Uint8List receiverPk; // 32  receiver's public key (binding)
  final Uint8List senderVerifyKey; // 32  sender's Ed25519 public key
  final Uint8List fileId; // 8   random transfer id
  final int totalSize; // 4   plaintext file size in bytes
  final int chunkCount; // 2   number of source chunks (K)
  final int chunkSize; // 2   plaintext bytes per chunk
  final Uint8List manifestHash; // 32  BLAKE2b-256 of the plaintext file
  Uint8List signature; // 64  Ed25519 sig over all previous fields

  SessionHeader({
    required this.senderEphPk,
    required this.receiverPk,
    required this.senderVerifyKey,
    required this.fileId,
    required this.totalSize,
    required this.chunkCount,
    required this.chunkSize,
    required this.manifestHash,
    required this.signature,
  });

  static const int packedSize = 2 + 1 + 32 + 32 + 32 + 8 + 4 + 2 + 2 + 32 + 64;

  Uint8List pack() {
    final out = ByteData(packedSize);
    var offset = 0;

    // MAGIC(2)
    out.setUint8(offset++, magic[0]);
    out.setUint8(offset++, magic[1]);
    // version(1)
    out.setUint8(offset++, version);
    // sender_eph_pk(32)
    out.buffer.asUint8List().setRange(offset, offset + 32, senderEphPk);
    offset += 32;
    // receiver_pk(32)
    out.buffer.asUint8List().setRange(offset, offset + 32, receiverPk);
    offset += 32;
    // sender_verify_key(32)
    out.buffer.asUint8List().setRange(offset, offset + 32, senderVerifyKey);
    offset += 32;
    // file_id(8)
    out.buffer.asUint8List().setRange(offset, offset + 8, fileId);
    offset += 8;
    // total_size(4)
    out.setUint32(offset, totalSize, Endian.big);
    offset += 4;
    // chunk_count(2)
    out.setUint16(offset, chunkCount, Endian.big);
    offset += 2;
    // chunk_size(2)
    out.setUint16(offset, chunkSize, Endian.big);
    offset += 2;
    // manifest_hash(32)
    out.buffer.asUint8List().setRange(offset, offset + 32, manifestHash);
    offset += 32;
    // signature(64)
    out.buffer.asUint8List().setRange(offset, offset + 64, signature);

    return out.buffer.asUint8List();
  }

  static SessionHeader unpack(Uint8List data) {
    if (data.length != packedSize) {
      throw DeadDropCryptoError('Invalid header size: ${data.length}');
    }

    final input = ByteData.sublistView(data);
    var offset = 0;

    // MAGIC(2)
    if (input.getUint8(offset++) != magic[0] ||
        input.getUint8(offset++) != magic[1]) {
      throw DeadDropCryptoError('Bad magic');
    }
    // version(1)
    if (input.getUint8(offset++) != version) {
      throw DeadDropCryptoError('Unsupported version');
    }
    // sender_eph_pk(32)
    final senderEphPk = data.sublist(offset, offset + 32);
    offset += 32;
    // receiver_pk(32)
    final receiverPk = data.sublist(offset, offset + 32);
    offset += 32;
    // sender_verify_key(32)
    final senderVerifyKey = data.sublist(offset, offset + 32);
    offset += 32;
    // file_id(8)
    final fileId = data.sublist(offset, offset + 8);
    offset += 8;
    // total_size(4)
    final totalSize = input.getUint32(offset, Endian.big);
    offset += 4;
    // chunk_count(2)
    final chunkCount = input.getUint16(offset, Endian.big);
    offset += 2;
    // chunk_size(2)
    final chunkSize = input.getUint16(offset, Endian.big);
    offset += 2;
    // manifest_hash(32)
    final manifestHash = data.sublist(offset, offset + 32);
    offset += 32;
    // signature(64)
    final signature = data.sublist(offset, offset + 64);

    return SessionHeader(
      senderEphPk: senderEphPk,
      receiverPk: receiverPk,
      senderVerifyKey: senderVerifyKey,
      fileId: fileId,
      totalSize: totalSize,
      chunkCount: chunkCount,
      chunkSize: chunkSize,
      manifestHash: manifestHash,
      signature: signature,
    );
  }

  /// The exact bytes covered by the signature.
  Uint8List signedPayload() {
    final packed = pack();
    return packed.sublist(0, packed.length - sigSize);
  }
}

// ---------------------------------------------------------------------------
// Session (sender side)
// ---------------------------------------------------------------------------

class Session {
  final PrecalculatedBox box;
  final Uint8List fileId;
  final int chunkCount;
  final int chunkSize;
  final List<Uint8List> chunks;

  /// Original file name, when provided by the user. Never transmitted in the
  /// clear — it travels inside the encrypted first frame (see below).
  final String? fileName;

  Session._({
    required this.box,
    required this.fileId,
    required this.chunkCount,
    required this.chunkSize,
    required this.chunks,
    this.fileName,
  });

  static Future<(Session, SessionHeader)> open(
    Sodium sodium,
    Uint8List plaintext,
    int chunkSize,
    Uint8List receiverPk,
    Identity senderIdentity, {
    String? fileName,
  }) async {
    // Validate BEFORE doing any work: `chunkSize` and the resulting
    // `chunkCount` are packed as uint16, and `ByteData.setUint16` truncates
    // silently instead of throwing. Fail loudly here so an oversized file
    // surfaces as a clear, actionable error instead of a corrupted header
    // the receiver cannot make sense of.
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw DeadDropCryptoError(
        'Invalid chunk size $chunkSize bytes — must be between '
        '$minChunkSize and $maxChunkSize bytes.',
      );
    }

    final ephKp = sodium.crypto.box.keyPair();
    final box = sodium.crypto.box.precalculate(
      publicKey: receiverPk,
      secretKey: ephKp.secretKey,
    );

    final fileId = sodium.randombytes.buf(fileIdSize);
    final manifestHash = sodium.crypto.genericHash(message: plaintext);
    final chunkCount = (plaintext.length + chunkSize - 1) ~/ chunkSize;

    if (chunkCount > maxChunkCount) {
      throw DeadDropCryptoError(
        'File too large: ${plaintext.length} bytes needs $chunkCount chunks '
        'of $chunkSize bytes, but the protocol supports at most '
        '$maxChunkCount chunks. Maximum file size at this chunk size is '
        '${maxFileSizeForChunkSize(chunkSize)} bytes. Use a larger chunk '
        'size.',
      );
    }

    // Pre-split into source chunks (padded last chunk)
    final chunks = List<Uint8List>.generate(chunkCount, (i) {
      final start = i * chunkSize;
      final end = (start + chunkSize).clamp(0, plaintext.length);
      final chunk = Uint8List(chunkSize);
      chunk.setRange(0, end - start, plaintext.sublist(start, end));
      return chunk;
    });

    final header = SessionHeader(
      senderEphPk: ephKp.publicKey,
      receiverPk: receiverPk,
      senderVerifyKey: senderIdentity.verifyKey,
      fileId: fileId,
      totalSize: plaintext.length,
      chunkCount: chunkCount,
      chunkSize: chunkSize,
      manifestHash: manifestHash,
      signature: Uint8List(sigSize), // placeholder
    );
    header.signature = senderIdentity.sign(sodium, header.signedPayload());

    final session = Session._(
      box: box,
      fileId: fileId,
      chunkCount: chunkCount,
      chunkSize: chunkSize,
      chunks: chunks,
      fileName: fileName,
    );
    return (session, header);
  }

  /// Encrypt one source chunk. Returns (nonce, ciphertext+tag).
  (Uint8List, Uint8List) encryptChunk(Sodium sodium, int chunkId) {
    if (chunkId < 0 || chunkId >= chunkCount) {
      throw ArgumentError('chunk_id out of range');
    }
    final nonce = sodium.randombytes.buf(nonceSize);
    final ct = box.easy(
      message: chunks[chunkId],
      nonce: nonce,
    );
    return (nonce, ct);
  }

  /// Encrypts an arbitrary payload with the session key.
  ///
  /// Used for the encrypted file-metadata frame (seq 0), which carries the
  /// original file name inside the encrypted channel — per spec §2.5 no
  /// filename is ever transmitted in the clear.
  (Uint8List, Uint8List) encryptPayload(Sodium sodium, Uint8List payload) {
    final nonce = sodium.randombytes.buf(nonceSize);
    final ct = box.easy(message: payload, nonce: nonce);
    return (nonce, ct);
  }
}

// ---------------------------------------------------------------------------
// Encrypted file metadata (seq-0 frame payload)
// ---------------------------------------------------------------------------

/// Builds the encrypted metadata payload: a compact JSON document with the
/// original file name, padded to [padTo] bytes.
///
/// The padding is why this is not simply the JSON. A metadata frame
/// carrying only a file name is a 37-module QR where a 1024-byte data
/// chunk is 141, so without padding every 32nd frame changes the code's
/// geometry completely: on screen it reads as a flash, and a receiver's
/// auto-exposure and binarizer have to re-adapt afterwards, during
/// frames that carry actual data.
///
/// It also stops the metadata frames being the obviously smaller ones in
/// a sequence someone is watching over your shoulder. That is a side
/// benefit, not a guarantee: frame sizes are not the only thing such an
/// observer sees.
///
/// Padding is inside the encrypted payload, so it costs a receiver
/// nothing and tells an observer nothing. It is a JSON field rather than
/// trailing bytes because [parseFileMetadataPayload] rejects anything
/// after the document.
Uint8List buildFileMetadataPayload({String? fileName, int padTo = 0}) {
  final doc = <String, dynamic>{'name': fileName ?? ''};
  final bare = utf8.encode(jsonEncode(doc));
  if (padTo <= bare.length) return Uint8List.fromList(bare);

  // Adding the field costs its key, quotes, colon and comma before any
  // padding character lands, so measure rather than assume.
  final withEmptyPad = utf8.encode(jsonEncode({...doc, _padKey: ''}));
  final room = padTo - withEmptyPad.length;
  if (room <= 0) return Uint8List.fromList(bare);
  return Uint8List.fromList(
    utf8.encode(jsonEncode({...doc, _padKey: _padChar * room})),
  );
}

/// The field [buildFileMetadataPayload] pads with. Ignored on parse: a
/// reader only ever looks up the keys it knows.
const String _padKey = 'p';

/// A character that survives JSON encoding unescaped and as a single
/// byte in UTF-8, so the padded length is the length asked for.
const String _padChar = 'A';

/// Parses the decrypted metadata payload. Returns an empty map on malformed
/// input — metadata is a convenience, never a reason to fail a transfer.
Map<String, dynamic> parseFileMetadataPayload(Uint8List payload) {
  try {
    final doc = jsonDecode(utf8.decode(payload));
    return doc is Map<String, dynamic> ? doc : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

// ---------------------------------------------------------------------------
// ReceiverSession (receiver side)
// ---------------------------------------------------------------------------

class ReceiverSession {
  final PrecalculatedBox box;
  final SessionHeader header;

  ReceiverSession._({required this.box, required this.header});

  static Future<ReceiverSession> accept(
    Sodium sodium,
    Uint8List headerBytes,
    ReceiverKeypair receiverKeypair,
  ) async {
    final header = SessionHeader.unpack(headerBytes);

    if (!constantTimeEquals(header.receiverPk, receiverKeypair.publicKey)) {
      throw DeadDropCryptoError('Session not addressed to this receiver');
    }

    // Signature verification is MANDATORY — the session header must be
    // signed by the sender identity key embedded in the header itself.
    // This proves the header was not tampered with in transit.
    // The UI layer separately checks the sender fingerprint against the
    // TOFU store to detect first-time or changed senders.
    final valid = sodium.crypto.sign.verifyDetached(
      signature: header.signature,
      message: header.signedPayload(),
      publicKey: header.senderVerifyKey,
    );
    if (!valid) {
      throw DeadDropCryptoError(
        'Sender signature invalid — the session header was not signed by '
        'the sender identity it claims. This may indicate a forged or '
        'tampered bootstrap QR code.',
      );
    }

    final box = sodium.crypto.box.precalculate(
      publicKey: header.senderEphPk,
      secretKey: receiverKeypair.privateKey,
    );
    return ReceiverSession._(box: box, header: header);
  }

  Uint8List decryptChunk(Sodium sodium, Uint8List nonce, Uint8List ciphertext) {
    try {
      return box.openEasy(
        cipherText: ciphertext,
        nonce: nonce,
      );
    } catch (e) {
      throw DeadDropCryptoError('Chunk authentication failed');
    }
  }

  bool verifyFile(Sodium sodium, Uint8List plaintext) {
    final digest = sodium.crypto.genericHash(message: plaintext);
    return constantTimeEquals(digest, header.manifestHash);
  }
}
