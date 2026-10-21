import 'dart:typed_data';

import 'package:dead_drop/src/file_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatFileSize', () {
    test('bytes below 1 KB', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
    });
  });

  group('parseImageDimensions', () {
    test('PNG 1920x1080', () {
      // Minimal PNG header: 8-byte signature + IHDR chunk
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // "IHDR"
        0x00, 0x00, 0x07, 0x80, // width: 1920 (big-endian)
        0x00, 0x00, 0x04, 0x38, // height: 1080 (big-endian)
        0x08, 0x06, 0x00, 0x00, 0x00, // bit depth, color type, etc.
      ]);
      final dims = parseImageDimensions(png);
      expect(dims, isNotNull);
      expect(dims!.width, 1920);
      expect(dims.height, 1080);
    });

    test('returns null for null bytes', () {
      expect(parseImageDimensions(null), isNull);
    });

    test('returns null for too-short data', () {
      expect(parseImageDimensions(Uint8List.fromList([0x89, 0x50])), isNull);
    });
  });
}
