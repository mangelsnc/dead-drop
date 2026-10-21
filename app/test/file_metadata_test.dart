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

  group('formatByteCount', () {
    test('thousands', () {
      expect(formatByteCount(1000), '1,000');
      expect(formatByteCount(2515968), '2,515,968');
    });
  });

  group('fileSignature', () {
    test('PNG signature', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(fileSignature(png), '89 50 4E 47 0D 0A 1A 0A');
    });

    test('empty bytes', () {
      expect(fileSignature(Uint8List(0)), '');
    });

    test('custom count', () {
      final data = Uint8List.fromList(List.generate(16, (i) => i));
      expect(fileSignature(data, count: 4), '00 01 02 03');
    });
  });

  group('guessMimeType', () {
    test('from magic bytes: PNG', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(guessMimeType(png, null), 'image/png');
    });

    test('extension fallback when no magic bytes match', () {
      final unknown = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(guessMimeType(unknown, 'txt'), 'text/plain');
      expect(guessMimeType(unknown, 'pdf'), 'application/pdf');
    });

    test('null when nothing matches', () {
      final unknown = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(guessMimeType(unknown, 'xyz'), isNull);
      expect(guessMimeType(unknown, null), isNull);
    });
  });
}
