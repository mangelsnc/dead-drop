/// emitter.dart — DeadDrop sender: file → encrypted fountain-coded QR frames.
///
/// Ported 1:1 from spike/src/emitter.py.
///
/// Pipeline
/// --------
///     file bytes
///       → Session.open()          (ephemeral X25519 + signed manifest header)
///       → split into K chunks     (fixed chunk_size, last one padded)
///       → LTEncoder               (endless XOR-combined frames)
///       → per frame: encrypt payload with session key (AEAD)
///       → pack into binary frame
///       → render as QR image
library;

import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs.dart';

import 'crypto.dart';
import 'fountain.dart';
import 'qrframe.dart';

class Emitter {
  final Sodium sodium;
  final Identity identity;
  final Session session;
  final SessionHeader header;
  final LTEncoder fountain;
  final int transferSeed;
  int _seq = 0;

  Emitter._({
    required this.sodium,
    required this.identity,
    required this.session,
    required this.header,
    required this.fountain,
    required this.transferSeed,
  });

  static Future<Emitter> create(
    Sodium sodium,
    Uint8List fileBytes,
    ReceiverKeypair receiverKeypair, {
    Identity? senderIdentity,
    int chunkSize = 512,
  }) async {
    final identity = senderIdentity ?? await Identity.generate(sodium);
    final (session, header) = await Session.open(
      sodium,
      fileBytes,
      chunkSize,
      receiverKeypair.publicKey,
      identity,
    );
    final fountain = LTEncoder(session.chunks);
    final transferSeed = sodium.randombytes.buf(4).buffer.asByteData().getUint32(0, Endian.big);

    return Emitter._(
      sodium: sodium,
      identity: identity,
      session: session,
      header: header,
      fountain: fountain,
      transferSeed: transferSeed,
    );
  }

  /// Bytes for the single static QR that starts the session.
  Uint8List bootstrapQrPayload() => header.pack();

  /// Produce the next encrypted fountain frame.
  Frame nextFrame() {
    final seq = _seq++;
    final (chunkIds, xored) = fountain.makeFrame(seq, transferSeed);
    final nonce = sodium.randombytes.buf(nonceSize);
    final ct = session.box.easy(
      message: xored,
      nonce: nonce,
    );
    return Frame(
      fileId: session.fileId,
      seq: seq,
      seed: transferSeed,
      chunkIds: chunkIds,
      nonce: nonce,
      payload: ct,
    );
  }
}
