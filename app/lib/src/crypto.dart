/// crypto.dart — E2E encryption layer for DeadDrop.
///
/// Ported 1:1 from spike/src/crypto.py (PyNaCl → sodium_libs).
///
/// Primitives (libsodium):
/// * Key exchange : X25519          (crypto_box / crypto_kx)
/// * Cipher       : XSalsa20-Poly1305 (crypto_secretbox / crypto_box)
/// * Signatures   : Ed25519         (crypto_sign) — sender authenticity
/// * Hash         : SHA-256         (chunk ids, file manifest integrity)
library;

import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const magic = [0x44, 0x44]; // "DD"
const version = 1;
const nonceSize = 24; // XSalsa20-Poly1305 nonce
const tagSize = 16; // Poly1305 tag
const pkSize = 32; // X25519 public key
const sigSize = 64; // Ed25519 signature
const hashSize = 32; // SHA-256
const fileIdSize = 8;

class DeadDropCryptoError implements Exception {
  final String message;
  DeadDropCryptoError(this.message);
  @override
  String toString() => 'DeadDropCryptoError: $message';
}

// ---------------------------------------------------------------------------
// Identities
// ---------------------------------------------------------------------------

/// Long-term-ish Ed25519 signing identity (per install, per user).
class Identity {
  final KeyPair keyPair;

  Identity._(this.keyPair);

  static Future<Identity> generate(Sodium sodium) async {
    final key = sodium.crypto.sign.keyPair();
    return Identity._(key);
  }

  Uint8List get verifyKey => keyPair.publicKey;

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
  final Uint8List fileId; // 8   random transfer id
  final int totalSize; // 4   plaintext file size in bytes
  final int chunkCount; // 2   number of source chunks (K)
  final int chunkSize; // 2   plaintext bytes per chunk
  final Uint8List manifestHash; // 32  sha256 of the plaintext file
  Uint8List signature; // 64  Ed25519 sig over all previous fields

  SessionHeader({
    required this.senderEphPk,
    required this.receiverPk,
    required this.fileId,
    required this.totalSize,
    required this.chunkCount,
    required this.chunkSize,
    required this.manifestHash,
    required this.signature,
  });

  static const int packedSize = 2 + 1 + 32 + 32 + 8 + 4 + 2 + 2 + 32 + 64;

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

  Session._({
    required this.box,
    required this.fileId,
    required this.chunkCount,
    required this.chunkSize,
    required this.chunks,
  });

  static Future<(Session, SessionHeader)> open(
    Sodium sodium,
    Uint8List plaintext,
    int chunkSize,
    Uint8List receiverPk,
    Identity senderIdentity,
  ) async {
    final ephKp = sodium.crypto.box.keyPair();
    final box = sodium.crypto.box.precalculate(
      publicKey: receiverPk,
      secretKey: ephKp.secretKey,
    );

    final fileId = sodium.randombytes.buf(fileIdSize);
    final manifestHash = sodium.crypto.genericHash(message: plaintext);
    final chunkCount = (plaintext.length + chunkSize - 1) ~/ chunkSize;

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
    ReceiverKeypair receiverKeypair, {
    Uint8List? senderVerifyKey,
  }) async {
    final header = SessionHeader.unpack(headerBytes);

    if (!_constantTimeEquals(header.receiverPk, receiverKeypair.publicKey)) {
      throw DeadDropCryptoError('Session not addressed to this receiver');
    }

    if (senderVerifyKey != null) {
      final valid = sodium.crypto.sign.verifyDetached(
        signature: header.signature,
        message: header.signedPayload(),
        publicKey: senderVerifyKey,
      );
      if (!valid) {
        throw DeadDropCryptoError('Sender signature invalid');
      }
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
    return _constantTimeEquals(digest, header.manifestHash);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
