/// handshake.dart — receiver public-key exchange over QR.
///
/// Before any file can be sent, the sender needs the receiver's X25519
/// public key. The receiver displays it as a static QR; the sender scans it
/// with their camera. The payload is a compact JSON document, base64url
/// wrapped like every other DeadDrop QR (see transport.dart):
///
///     DD1.<base64url({"t":"dd-key","v":1,"pk":"<hex-encoded X25519 pk>"})>
///
/// The `t` field ("dd-key") distinguishes handshake QRs from session-header
/// and data-frame QRs, which carry binary payloads.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'transport.dart';

const String handshakeType = 'dd-key';
const int handshakeVersion = 1;

/// What the receiver's camera would like the sender to emit.
///
/// Carried in the handshake QR alongside the key, because that QR is
/// already the one thing that travels from receiver to sender. The
/// channel is one-way once the transfer starts, so this is the only
/// moment the receiver can say anything at all.
class HandshakeHint {
  const HandshakeHint({
    required this.fps,
    required this.chunkSize,
    required this.ecLevel,
  });

  final double fps;
  final int chunkSize;
  final String ecLevel;

  Map<String, dynamic> toJson() => {
        'fps': fps,
        'cs': chunkSize,
        'ec': ecLevel,
      };

  /// Reads a hint, or null when absent or malformed.
  ///
  /// A malformed hint is treated as no hint rather than as an error: it
  /// is an optimisation, and refusing a perfectly good public key because
  /// an advisory field was wrong would be a poor trade.
  static HandshakeHint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fps = raw['fps'];
    final cs = raw['cs'];
    final ec = raw['ec'];
    if (fps is! num || cs is! int || ec is! String) return null;
    if (fps <= 0 || fps > 60 || cs <= 0) return null;
    if (!const ['L', 'M', 'Q', 'H'].contains(ec)) return null;
    return HandshakeHint(
      fps: fps.toDouble(),
      chunkSize: cs,
      ecLevel: ec,
    );
  }
}

/// Everything a scanned handshake QR carries.
class HandshakePayload {
  const HandshakePayload({required this.publicKey, this.hint});

  final Uint8List publicKey;

  /// The receiver's suggested emission settings, when it sent any.
  ///
  /// Null for a QR from an older version, which is why this is a separate
  /// field rather than something the sender can assume is present.
  final HandshakeHint? hint;
}

/// Builds the QR string the receiver shows to the sender.
///
/// [hint] is optional. A reader that does not know about it ignores the
/// extra field, so adding one does not break an older sender.
String encodeHandshakeQr(Uint8List publicKey, {HandshakeHint? hint}) {
  final doc = jsonEncode({
    't': handshakeType,
    'v': handshakeVersion,
    'pk': bytesToHex(publicKey),
    if (hint != null) 'h': hint.toJson(),
  });
  return encodeQrPayload(Uint8List.fromList(utf8.encode(doc)));
}

/// Parses a scanned QR into its key and any hint it carried.
///
/// Returns null on the same conditions as [decodeHandshakeQr].
HandshakePayload? decodeHandshakePayload(String raw) {
  final bytes = decodeQrPayload(raw);
  if (bytes == null) return null;
  try {
    final doc = jsonDecode(utf8.decode(bytes));
    if (doc is! Map<String, dynamic>) return null;
    if (doc['t'] != handshakeType || doc['v'] != handshakeVersion) return null;
    final pk = hexToBytes(doc['pk'] as String);
    if (pk.length != 32) return null; // X25519 public key size
    return HandshakePayload(
      publicKey: pk,
      hint: HandshakeHint.fromJson(doc['h']),
    );
  } catch (_) {
    return null;
  }
}

/// Parses a scanned QR string into a receiver public key.
///
/// Returns `null` when the QR is not a DeadDrop handshake payload (foreign
/// QR, malformed JSON, wrong version, bad key length) so the scanner can
/// keep looking without error handling noise.
Uint8List? decodeHandshakeQr(String raw) {
  final bytes = decodeQrPayload(raw);
  if (bytes == null) return null;
  try {
    final doc = jsonDecode(utf8.decode(bytes));
    if (doc is! Map<String, dynamic>) return null;
    if (doc['t'] != handshakeType || doc['v'] != handshakeVersion) return null;
    final pk = hexToBytes(doc['pk'] as String);
    if (pk.length != 32) return null; // X25519 public key size
    return pk;
  } catch (_) {
    return null;
  }
}

/// Lowercase hex encoding.
String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Tolerant hex decoding: ignores whitespace and non-hex separators.
Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length % 2 != 0) throw const FormatException('odd hex length');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
