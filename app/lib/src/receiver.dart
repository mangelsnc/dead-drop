/// receiver.dart — DeadDrop receiver: QR frames → decrypted, verified file.
///
/// Ported 1:1 from spike/src/receiver.py.
///
/// Pipeline
/// --------
///     bootstrap QR (once)
///       → ReceiverSession.accept()  (verify signature, derive shared key)
///     for each scanned frame:
///       → Frame.unpack()
///       → filter by file_id       (ignore frames from other sessions)
///       → decrypt payload (AEAD)  — bad frames are dropped, not fatal
///       → LTDecoder.add_frame()   (belief propagation)
///     when decoder.done:
///       → reassemble, unpad to total_size
///       → verify sha256 against signed manifest
///       → return plaintext
library;

import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs.dart';

import 'crypto.dart';
import 'fountain.dart';
import 'qrframe.dart';

class Receiver {
  final Sodium sodium;
  final ReceiverKeypair keypair;
  ReceiverSession? session;
  LTDecoder? decoder;
  int framesDropped = 0;
  int framesIgnoredOtherSession = 0;

  Receiver({required this.sodium, required this.keypair});

  /// Consume the one-time bootstrap QR and arm the decoder.
  Future<void> startSession(
    Uint8List bootstrapPayload, {
    Uint8List? senderVerifyKey,
  }) async {
    session = await ReceiverSession.accept(
      sodium,
      bootstrapPayload,
      keypair,
      senderVerifyKey: senderVerifyKey,
    );
    final h = session!.header;
    decoder = LTDecoder(k: h.chunkCount, chunkSize: h.chunkSize);
  }

  /// Process one scanned frame. Returns true if it advanced decoding.
  bool feedFrame(Uint8List frameBytes) {
    if (session == null || decoder == null) {
      throw StateError('call startSession() first');
    }
    if (decoder!.done) return false;

    Frame frame;
    try {
      frame = Frame.unpack(frameBytes);
    } catch (e) {
      framesDropped++;
      return false;
    }

    if (!_constantTimeEquals(frame.fileId, session!.header.fileId)) {
      framesIgnoredOtherSession++;
      return false;
    }

    Uint8List payload;
    try {
      payload = session!.decryptChunk(sodium, frame.nonce, frame.payload);
    } catch (e) {
      framesDropped++;
      return false;
    }

    return decoder!.addFrame(frame.chunkIds, payload);
  }

  bool get done => decoder?.done ?? false;

  double get progress {
    if (decoder == null || decoder!.k == 0) return 0.0;
    return decoder!.decoded.length / decoder!.k;
  }

  /// Reassemble + verify + unpad. Throws if integrity check fails.
  Uint8List finish() {
    if (!done) throw StateError('transfer incomplete');
    final padded = decoder!.reassemble();
    final plaintext = padded.sublist(0, session!.header.totalSize);
    if (!session!.verifyFile(sodium, plaintext)) {
      throw DeadDropCryptoError('File integrity check failed (sha256 mismatch)');
    }
    return plaintext;
  }
}

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
