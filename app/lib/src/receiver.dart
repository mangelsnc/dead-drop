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
  int framesRejectedBadChunkIds = 0;

  /// Original file name recovered from the encrypted metadata frame (seq 0),
  /// when the sender included one.
  String? fileName;

  Receiver({required this.sodium, required this.keypair});

  /// Consume the one-time bootstrap QR and arm the decoder.
  ///
  /// The session header carries the sender's Ed25519 verify key, and the
  /// signature is verified against it automatically. The UI layer should
  /// separately check the sender fingerprint against the TOFU store.
  Future<void> startSession(Uint8List bootstrapPayload) async {
    session = await ReceiverSession.accept(
      sodium,
      bootstrapPayload,
      keypair,
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

    // Sequence 0 carries the encrypted file metadata (original file name).
    // It is not a fountain frame: degree is 0 and it never advances decoding.
    if (frame.seq == 0) {
      final meta = parseFileMetadataPayload(payload);
      final name = meta['name'];
      if (name is String && name.isNotEmpty) {
        fileName = name;
      }
      return false;
    }

    // Bounds-check chunk ids before they reach the decoder. The payload is
    // AEAD-authenticated, so this is defence-in-depth against a corrupt
    // emitter or our own bug — not a remote attack surface. An out-of-range
    // cid would otherwise pollute `pending` permanently and crash
    // `reassemble()` with an opaque error. A bad frame is dropped, never
    // fatal: the fountain code absorbs the loss.
    if (!_validateChunkIds(frame.chunkIds, decoder!.k)) {
      framesRejectedBadChunkIds++;
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

/// Returns true only if every chunk id is a valid source-chunk index,
/// i.e. in `[0, k)`. Anything else means the frame is corrupt and must be
/// dropped before it can poison the decoder's pending set.
bool _validateChunkIds(List<int> chunkIds, int k) {
  for (final cid in chunkIds) {
    if (cid < 0 || cid >= k) return false;
  }
  return true;
}
