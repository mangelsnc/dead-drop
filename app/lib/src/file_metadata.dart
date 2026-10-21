import 'dart:typed_data';

/// Pure, synchronous helpers for extracting file metadata from raw bytes.
///
/// All functions are fast (< 1 ms) and allocation-light. They operate on
/// the first N bytes of a file, so they work even for very large files
/// as long as the header is available.
library;

// ---------------------------------------------------------------------------
// Human-readable file sizes
// ---------------------------------------------------------------------------

/// Formats a byte count using the most appropriate unit.
///
/// Thresholds:
///   - < 1 KB:  "512 B"
///   - < 1 MB:  "345.2 KB"
///   - < 1 GB:  "2.4 MB"
///   - >= 1 GB: "1.25 GB"
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Formats a byte count with thousand separators (e.g. "2,515,968").
String formatByteCount(int bytes) {
  if (bytes < 1000) return '$bytes';
  final str = bytes.toString();
  final buffer = StringBuffer();
  final remainder = str.length % 3;
  if (remainder > 0) {
    buffer.write(str.substring(0, remainder));
    if (str.length > remainder) buffer.write(',');
  }
  for (var i = remainder; i < str.length; i += 3) {
    buffer.write(str.substring(i, i + 3));
    if (i + 3 < str.length) buffer.write(',');
  }
  return buffer.toString();
}

/// Returns a human-readable size with the exact byte count in parentheses.
///
/// Example: "2.4 MB (2,515,968 bytes)"
String formatSizeWithBytes(int bytes) {
  return '${formatFileSize(bytes)} (${formatByteCount(bytes)} bytes)';
}

// ---------------------------------------------------------------------------
// File signature (magic bytes)
// ---------------------------------------------------------------------------

/// Returns the first [count] bytes of [bytes] as uppercase hex pairs
/// separated by spaces.
///
/// Example: "89 50 4E 47 0D 0A 1A 0A" for a PNG file.
String fileSignature(Uint8List bytes, {int count = 8}) {
  final end = bytes.length < count ? bytes.length : count;
  final parts = <String>[];
  for (var i = 0; i < end; i++) {
    parts.add(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return parts.join(' ');
}

// ---------------------------------------------------------------------------
// MIME type detection
// ---------------------------------------------------------------------------

/// Guesses the MIME type from magic bytes first, then falls back to the
/// file extension.
///
/// Returns `null` when neither source yields a known type.
String? guessMimeType(Uint8List? bytes, String? extension) {
  // Magic-byte detection (most reliable)
  if (bytes != null && bytes.length >= 4) {
    final mime = _mimeFromMagicBytes(bytes);
    if (mime != null) return mime;
  }

  // Extension fallback
  if (extension != null) {
    return _mimeFromExtension(extension);
  }

  return null;
}

String? _mimeFromMagicBytes(Uint8List b) {
  // PNG: 89 50 4E 47
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  // JPEG: FF D8 FF
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  // GIF: 47 49 46 38
  if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
    return 'image/gif';
  }
  // WebP: RIFF....WEBP
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  // BMP: 42 4D
  if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) {
    return 'image/bmp';
  }
  // PDF: 25 50 44 46 (%PDF)
  if (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
    return 'application/pdf';
  }
  // ZIP: 50 4B 03 04
  if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04) {
    return 'application/zip';
  }
  // GZIP: 1F 8B
  if (b.length >= 2 && b[0] == 0x1F && b[1] == 0x8B) {
    return 'application/gzip';
  }
  return null;
}

String? _mimeFromExtension(String ext) {
  return switch (ext.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'html' => 'text/html',
    'css' => 'text/css',
    'js' => 'application/javascript',
    'ts' => 'application/typescript',
    'dart' => 'application/dart',
    'py' => 'text/x-python',
    'yaml' || 'yml' => 'application/yaml',
    'zip' => 'application/zip',
    'tar' => 'application/x-tar',
    'gz' => 'application/gzip',
    '7z' => 'application/x-7z-compressed',
    'rar' => 'application/vnd.rar',
    'bz2' => 'application/x-bzip2',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    'flac' => 'audio/flac',
    'm4a' => 'audio/mp4',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Image dimensions (header parsing — no decode needed)
// ---------------------------------------------------------------------------

/// Parsed image dimensions.
typedef ImageDimensions = ({int width, int height});

/// Extracts image dimensions from the header bytes of common formats.
///
/// Supports PNG, JPEG, GIF, WebP, and BMP. Returns `null` if the format
/// is not recognized or the header is too short/corrupt.
ImageDimensions? parseImageDimensions(Uint8List? bytes) {
  if (bytes == null || bytes.length < 10) return null;

  // PNG: bytes 16-23 contain width and height (big-endian)
  if (_isPng(bytes)) return _pngDimensions(bytes);

  // JPEG: scan for SOF0/SOF2 markers
  if (_isJpeg(bytes)) return _jpegDimensions(bytes);

  // GIF: bytes 6-9 contain width and height (little-endian)
  if (_isGif(bytes)) return _gifDimensions(bytes);

  // WebP: VP8 / VP8L chunk
  if (_isWebP(bytes)) return _webPDimensions(bytes);

  // BMP: bytes 18-25 contain width and height (little-endian)
  if (_isBmp(bytes)) return _bmpDimensions(bytes);

  return null;
}

bool _isPng(Uint8List b) =>
    b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

ImageDimensions? _pngDimensions(Uint8List b) {
  if (b.length < 24) return null;
  final width = _readUint32BE(b, 16);
  final height = _readUint32BE(b, 20);
  if (width <= 0 || height <= 0 || width > 100000 || height > 100000) return null;
  return (width: width, height: height);
}

bool _isJpeg(Uint8List b) =>
    b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

ImageDimensions? _jpegDimensions(Uint8List b) {
  // Scan for SOF0 (0xC0) or SOF2 (0xC2) markers
  var offset = 2;
  while (offset < b.length - 9) {
    if (b[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = b[offset + 1];
    if (marker == 0xC0 || marker == 0xC2) {
      // SOF: FF C0/C2 [length:2] [precision:1] [height:2] [width:2]
      if (offset + 9 > b.length) return null;
      final height = _readUint16BE(b, offset + 5);
      final width = _readUint16BE(b, offset + 7);
      if (width > 0 && height > 0 && width <= 100000 && height <= 100000) {
        return (width: width, height: height);
      }
      return null;
    }
    // Skip to next marker: FF xx [length:2] ... data ...
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
    } else {
      if (offset + 3 > b.length) return null;
      final segLen = _readUint16BE(b, offset + 2);
      offset += 2 + segLen;
    }
  }
  return null;
}

bool _isGif(Uint8List b) =>
    b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;

ImageDimensions? _gifDimensions(Uint8List b) {
  if (b.length < 10) return null;
  final width = _readUint16LE(b, 6);
  final height = _readUint16LE(b, 8);
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

bool _isWebP(Uint8List b) =>
    b.length >= 12 &&
    b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
    b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50;

ImageDimensions? _webPDimensions(Uint8List b) {
  if (b.length < 30) return null;
  // Check for VP8 (lossy) or VP8L (lossless) chunk
  final fourCC = String.fromCharCodes(b.sublist(12, 16));
  if (fourCC == 'VP8 ') {
    // VP8: frame tag at 20-22, then start code 9D 01 2A, then dims
    if (b.length < 30) return null;
    // Find the 9D 01 2A start code (usually at offset 23)
    for (var i = 20; i < b.length - 7 && i < 30; i++) {
      if (b[i] == 0x9D && b[i + 1] == 0x01 && b[i + 2] == 0x2A) {
        final width = _readUint16LE(b, i + 3) & 0x3FFF;
        final height = _readUint16LE(b, i + 5) & 0x3FFF;
        if (width > 0 && height > 0) return (width: width, height: height);
        return null;
      }
    }
    return null;
  }
  if (fourCC == 'VP8L') {
    // VP8L: signature byte 0x2F at offset 20, then 14-bit width/height
    if (b.length < 25) return null;
    if (b[20] != 0x2F) return null;
    final bits = _readUint32LE(b, 21);
    final width = (bits & 0x3FFF) + 1;
    final height = ((bits >> 14) & 0x3FFF) + 1;
    if (width > 0 && height > 0) return (width: width, height: height);
    return null;
  }
  return null;
}

bool _isBmp(Uint8List b) =>
    b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D;

ImageDimensions? _bmpDimensions(Uint8List b) {
  if (b.length < 26) return null;
  final width = _readInt32LE(b, 18);
  final height = _readInt32LE(b, 22).abs();
  if (width <= 0 || height <= 0 || width > 100000 || height > 100000) return null;
  return (width: width, height: height);
}

// ---------------------------------------------------------------------------
// PDF page count
// ---------------------------------------------------------------------------

/// Approximate page count for a PDF, derived by scanning the first
/// [maxScanBytes] for `/Type /Page` occurrences (excluding `/Pages`).
///
/// This is fast and works for most PDFs. Returns `null` if the bytes
/// don't look like a PDF.
int? countPdfPages(Uint8List? bytes, {int maxScanBytes = 10240}) {
  if (bytes == null || bytes.length < 5) return null;

  // Verify PDF magic: %PDF-
  if (bytes[0] != 0x25 || bytes[1] != 0x50 || bytes[2] != 0x44 ||
      bytes[3] != 0x46 || bytes[4] != 0x2D) {
    return null;
  }

  final scanLen = bytes.length < maxScanBytes ? bytes.length : maxScanBytes;
  final content = String.fromCharCodes(bytes, 0, scanLen);

  // Count "/Type /Page" but NOT "/Type /Pages"
  var count = 0;
  var idx = 0;
  while (true) {
    idx = content.indexOf('/Type', idx);
    if (idx < 0) break;
    // Skip "/Type"
    var rest = content.substring(idx + 5).trimLeft();
    if (rest.startsWith('/Page')) {
      // Make sure it's not "/Pages"
      if (!rest.startsWith('/Pages')) {
        count++;
      }
    }
    idx += 5;
  }

  // Also try compact form "/Type/Page" (no space)
  if (count == 0) {
    idx = 0;
    while (true) {
      idx = content.indexOf('/Type/Page', idx);
      if (idx < 0) break;
      // Check it's not "/Type/Pages"
      final after = idx + 10;
      if (after >= content.length || content[after] != 's') {
        count++;
      }
      idx += 10;
    }
  }

  return count > 0 ? count : null;
}

// ---------------------------------------------------------------------------
// Binary helpers
// ---------------------------------------------------------------------------

int _readUint16BE(Uint8List b, int offset) =>
    (b[offset] << 8) | b[offset + 1];

int _readUint16LE(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8);

int _readUint32BE(Uint8List b, int offset) =>
    (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];

int _readUint32LE(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16) | (b[offset + 3] << 24);

int _readInt32LE(Uint8List b, int offset) {
  final unsigned = _readUint32LE(b, offset);
  return unsigned >= 0x80000000 ? unsigned - 0x100000000 : unsigned;
}
