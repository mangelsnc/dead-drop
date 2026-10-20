/// transport.dart — wire envelope for QR payloads.
///
/// The QR ecosystem (qr_flutter on the render side, mobile_scanner / ZXing /
/// ML Kit on the scan side) is built around *text*. Pushing raw binary bytes
/// through `String.fromCharCodes` is fragile: byte values above 0x7F can be
/// reinterpreted as multi-byte UTF-8 sequences by the scanner, corrupting the
/// payload. To make the channel robust we wrap every binary payload in a
/// printable ASCII envelope:
///
///     "DD1.<base64url-no-padding(payload)>"
///
/// The prefix identifies the app/protocol version so the receiver can ignore
/// unrelated QRs instantly, and base64url survives any text pipeline
/// unchanged. Overhead is ~33% in characters, but QR byte-mode density is
/// identical for ASCII and binary, so the practical cost is just a slightly
/// denser module pattern — acceptable for the MVP and far more reliable.
library;

import 'dart:convert';
import 'dart:typed_data';

const String transportPrefix = 'DD1.';

/// Wraps raw [payload] bytes into the printable QR envelope string.
String encodeQrPayload(Uint8List payload) {
  return transportPrefix + base64Url.encode(payload);
}

/// Extracts the raw bytes from a scanned QR string.
///
/// Returns `null` when the string is not a DeadDrop envelope (wrong prefix,
/// invalid base64) so the caller can simply ignore foreign QRs.
Uint8List? decodeQrPayload(String raw) {
  if (!raw.startsWith(transportPrefix)) return null;
  final body = raw.substring(transportPrefix.length);
  try {
    return base64Url.decode(base64Url.normalize(body));
  } on FormatException {
    return null;
  }
}
