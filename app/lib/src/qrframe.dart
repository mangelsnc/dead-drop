/// qrframe.dart — QR frame packing, rendering and parsing for DeadDrop.
///
/// Ported from spike/src/qrframe.py; the chunk id list has since been
/// removed from the wire (see the layout below).
///
/// Frame layout (binary, big-endian):
///     MAGIC(2)      "DD"
///     version(1)    protocol version
///     file_id(8)    random transfer id (lets receiver ignore other sessions)
///     frame_seq(4)  monotonically increasing frame number
///     seed(4)       PRNG seed for this frame's chunk selection
///     degree(2)     how many chunks this frame XORs together; 0 marks
///                   the metadata frame
///     nonce(24)     XSalsa20-Poly1305 nonce for the payload
///     payload(N)    encrypted+tagged XOR chunk (chunk_size + 16 bytes)
library;

import 'dart:typed_data';

import 'crypto.dart';

// QR byte-mode capacity per version at each EC level (versions 1..40).
// Source: ISO/IEC 18004 tables.
const qrCapacity = {
  10: {'L': 346, 'M': 274, 'Q': 216, 'H': 154},
  15: {'L': 523, 'M': 415, 'Q': 295, 'H': 223},
  20: {'L': 861, 'M': 669, 'Q': 485, 'H': 367},
  25: {'L': 1279, 'M': 1003, 'Q': 733, 'H': 559},
  30: {'L': 1735, 'M': 1371, 'Q': 1007, 'H': 775},
  35: {'L': 2303, 'M': 1815, 'Q': 1343, 'H': 1039},
  40: {'L': 2953, 'M': 2331, 'Q': 1663, 'H': 1273},
};

const frameHeaderSize = 2 + 1 + 8 + 4 + 4 + 2; // magic, ver, file_id, seq, seed, degree

class Frame {
  final Uint8List fileId;
  final int seq;
  final int seed;

  /// How many chunks this frame XORs together.
  ///
  /// The ids themselves are not transmitted: the receiver recomputes
  /// them from (seq, seed, k) with [chunkIdsFor]. See
  /// docs/decisions/0001-derive-chunk-ids-from-the-seed.md.
  ///
  /// The count still travels, so that a receiver can tell the metadata
  /// frame (degree 0, no chunks) from a data frame without recomputing
  /// anything, and so that a recomputed degree disagreeing with this one
  /// identifies a desynchronised emitter instead of decoding silently
  /// against the wrong chunks.
  final int degree;

  final Uint8List nonce;
  final Uint8List payload;

  Frame({
    required this.fileId,
    required this.seq,
    required this.seed,
    required this.degree,
    required this.nonce,
    required this.payload,
  });

  /// Whether this frame carries file metadata rather than file data.
  bool get isMetadata => degree == 0;

  Uint8List pack() {
    final totalSize = frameHeaderSize + nonceSize + payload.length;
    final out = ByteData(totalSize);
    var offset = 0;

    // MAGIC(2)
    out.setUint8(offset++, magic[0]);
    out.setUint8(offset++, magic[1]);
    // version(1)
    out.setUint8(offset++, version);
    // file_id(8)
    out.buffer.asUint8List().setRange(offset, offset + 8, fileId);
    offset += 8;
    // frame_seq(4)
    out.setUint32(offset, seq, Endian.big);
    offset += 4;
    // seed(4)
    out.setUint32(offset, seed, Endian.big);
    offset += 4;
    // degree(2)
    out.setUint16(offset, degree, Endian.big);
    offset += 2;
    // nonce(24)
    out.buffer.asUint8List().setRange(offset, offset + nonceSize, nonce);
    offset += nonceSize;
    // payload(N)
    out.buffer.asUint8List().setRange(offset, offset + payload.length, payload);

    return out.buffer.asUint8List();
  }

  static Frame unpack(Uint8List data) {
    if (data.length < frameHeaderSize) {
      throw ArgumentError('Frame too short');
    }

    final input = ByteData.sublistView(data);
    var offset = 0;

    // MAGIC(2)
    if (input.getUint8(offset++) != magic[0] ||
        input.getUint8(offset++) != magic[1]) {
      throw ArgumentError('Not a DeadDrop frame');
    }
    // version(1)
    if (input.getUint8(offset++) != version) {
      throw ArgumentError('Unsupported version');
    }
    // file_id(8)
    final fileId = data.sublist(offset, offset + 8);
    offset += 8;
    // frame_seq(4)
    final seq = input.getUint32(offset, Endian.big);
    offset += 4;
    // seed(4)
    final seed = input.getUint32(offset, Endian.big);
    offset += 4;
    // degree(2)
    final degree = input.getUint16(offset, Endian.big);
    offset += 2;
    // nonce(24)
    final nonce = data.sublist(offset, offset + nonceSize);
    offset += nonceSize;
    // payload(N)
    final payload = data.sublist(offset);

    return Frame(
      fileId: fileId,
      seq: seq,
      seed: seed,
      degree: degree,
      nonce: nonce,
      payload: payload,
    );
  }
}

/// The largest QR a version-40 code can carry at [ec], in characters.
const _maxQrChars = {'L': 2953, 'M': 2331, 'Q': 1663, 'H': 1273};

/// How many characters a data frame of [chunkSize] becomes once packed,
/// encrypted and base64url-encoded for a QR.
///
/// A fountain frame of degree d carries d chunk ids, but the payload is
/// one chunk's worth however many were XORed into it, so the size is
/// dominated by the chunk itself. Degree is bounded in practice; a
/// generous allowance keeps this an upper bound rather than a guess.
int encodedFrameChars(int chunkSize, {int maxDegree = 16}) {
  final raw = frameHeaderSize + maxDegree * 2 + nonceSize + chunkSize + 16;
  // base64 is 4 characters per 3 bytes, plus the "DD1." prefix.
  return ((raw + 2) ~/ 3) * 4 + 4;
}

/// Whether [chunkSize] can be rendered as a QR at [ec].
///
/// A chunk that does not fit has no fallback: the renderer is asked for
/// a code larger than version 40 and fails outright, which is what
/// "the screen breaks when showing QRs" meant when 2048-byte chunks
/// were selected at the default error correction.
bool chunkFitsQr(int chunkSize, String ec) =>
    encodedFrameChars(chunkSize) <= (_maxQrChars[ec] ?? _maxQrChars['M']!);

/// The error-correction levels that can carry [chunkSize], strongest
/// first. Empty when no level can.
List<String> ecLevelsFor(int chunkSize) =>
    ['H', 'Q', 'M', 'L'].where((ec) => chunkFitsQr(chunkSize, ec)).toList();

int qrCapacityAt(int version, String ec) {
  final versions = qrCapacity.keys.toList()..sort();
  final v = versions.lastWhere((x) => x <= version, orElse: () => versions.first);
  return qrCapacity[v]![ec]!;
}
