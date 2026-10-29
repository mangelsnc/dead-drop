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

import 'package:sodium/sodium.dart';

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
    String? fileName,
  }) async {
    final identity = senderIdentity ?? await Identity.generate(sodium);
    final (session, header) = await Session.open(
      sodium,
      fileBytes,
      chunkSize,
      receiverKeypair.publicKey,
      identity,
      fileName: fileName,
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

  /// How often the metadata frame is sent again.
  ///
  /// The file name used to ride on sequence 0 alone, emitted once before
  /// the receiver's camera had locked on — so in practice it was usually
  /// missed, and a file arrived with a generated name and no extension.
  /// Everything else in this protocol already survives a lost frame; the
  /// name was the one thing that did not.
  ///
  /// Every 32nd frame costs about 3% of the stream and means a receiver
  /// that joins late still learns the name within a couple of seconds at
  /// any usable frame rate.
  static const int metadataInterval = 32;

  /// Produce the next frame. Sequence 0 is the encrypted metadata frame
  /// (file name), repeated every [metadataInterval] frames thereafter;
  /// every other sequence carries fountain-coded data.
  Frame nextFrame() {
    final seq = _seq++;
    if (seq == 0 || seq % metadataInterval == 0) {
      final (nonce, ct) = session.encryptPayload(
        sodium,
        // Padded to a chunk, so this frame renders at the same QR
        // version as the data frames around it and does not flash.
        buildFileMetadataPayload(
          fileName: session.fileName,
          padTo: session.chunkSize,
        ),
      );
      return Frame(
        fileId: session.fileId,
        seq: seq,
        seed: transferSeed,
        // Degree 0 is what marks this as the metadata frame.
        degree: 0,
        nonce: nonce,
        payload: ct,
      );
    }
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
      // Only the count travels; the receiver recomputes the ids from
      // (seq, seed, k).
      degree: chunkIds.length,
      nonce: nonce,
      payload: ct,
    );
  }
}
