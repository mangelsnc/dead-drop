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

/// Builds the QR string the receiver shows to the sender.
String encodeHandshakeQr(Uint8List publicKey) {
  final doc = jsonEncode({
    't': handshakeType,
    'v': handshakeVersion,
    'pk': bytesToHex(publicKey),
  });
  return encodeQrPayload(Uint8List.fromList(utf8.encode(doc)));
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
