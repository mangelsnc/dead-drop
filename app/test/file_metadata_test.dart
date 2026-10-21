import 'dart:typed_data';

import 'package:dead_drop/src/file_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // =========================================================================
  // formatFileSize
  // =========================================================================
  group('formatFileSize', () {
    test('bytes below 1 KB', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(1), '1 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('kilobytes below 1 MB', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(353484), '345.2 KB');
      expect(formatFileSize(1048575), '1024.0 KB');
    });

    test('megabytes below 1 GB', () {
      expect(formatFileSize(1048576), '1.0 MB');
      expect(formatFileSize(2515968), '2.4 MB');
      expect(formatFileSize(10485760), '10.0 MB');
      expect(formatFileSize(1073741823), '1024.0 MB');
    });

    test('gigabytes', () {
      expect(formatFileSize(1073741824), '1.00 GB');
      expect(formatFileSize(1342177280), '1.25 GB');
      expect(formatFileSize(5368709120), '5.00 GB');
    });
  });

  // =========================================================================
  // formatByteCount
  // =========================================================================
  group('formatByteCount', () {
    test('small numbers', () {
      expect(formatByteCount(0), '0');
      expect(formatByteCount(1), '1');
      expect(formatByteCount(999), '999');
    });

    test('thousands', () {
      expect(formatByteCount(1000), '1,000');
      expect(formatByteCount(1234), '1,234');
      expect(formatByteCount(12345), '12,345');
      expect(formatByteCount(123456), '123,456');
    });

    test('millions', () {
      expect(formatByteCount(1000000), '1,000,000');
      expect(formatByteCount(2515968), '2,515,968');
      expect(formatByteCount(12345678), '12,345,678');
    });

    test('billions', () {
      expect(formatByteCount(1000000000), '1,000,000,000');
      expect(formatByteCount(1234567890), '1,234,567,890');
    });
  });

  // =========================================================================
  // formatSizeWithBytes
  // =========================================================================
  group('formatSizeWithBytes', () {
    test('combines human size with byte count', () {
      expect(formatSizeWithBytes(512), '512 B (512 bytes)');
      expect(formatSizeWithBytes(2515968), '2.4 MB (2,515,968 bytes)');
      expect(formatSizeWithBytes(1073741824), '1.00 GB (1,073,741,824 bytes)');
    });
  });

  // =========================================================================
  // fileSignature
  // =========================================================================
  group('fileSignature', () {
    test('PNG signature', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(fileSignature(png), '89 50 4E 47 0D 0A 1A 0A');
    });

    test('JPEG signature (first 3 bytes)', () {
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(fileSignature(jpg, count: 4), 'FF D8 FF E0');
    });

    test('fewer bytes than requested', () {
      final tiny = Uint8List.fromList([0x42, 0x4D]);
      expect(fileSignature(tiny), '42 4D');
    });

    test('empty bytes', () {
      expect(fileSignature(Uint8List(0)), '');
    });

    test('custom count', () {
      final data = Uint8List.fromList(List.generate(16, (i) => i));
      expect(fileSignature(data, count: 4), '00 01 02 03');
    });
  });

  // =========================================================================
  // guessMimeType
  // =========================================================================
  group('guessMimeType', () {
    test('from magic bytes: PNG', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(guessMimeType(png, null), 'image/png');
    });

    test('from magic bytes: JPEG', () {
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(guessMimeType(jpg, null), 'image/jpeg');
    });

    test('from magic bytes: GIF', () {
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      expect(guessMimeType(gif, null), 'image/gif');
    });

    test('from magic bytes: PDF', () {
      final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(guessMimeType(pdf, null), 'application/pdf');
    });

    test('from magic bytes: ZIP', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
      expect(guessMimeType(zip, null), 'application/zip');
    });

    test('magic bytes take priority over extension', () {
      // A PNG file renamed to .jpg should still be detected as PNG
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(guessMimeType(png, 'jpg'), 'image/png');
    });

    test('extension fallback when no magic bytes match', () {
      final unknown = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(guessMimeType(unknown, 'txt'), 'text/plain');
      expect(guessMimeType(unknown, 'pdf'), 'application/pdf');
      expect(guessMimeType(unknown, 'mp4'), 'video/mp4');
    });

    test('null when nothing matches', () {
      final unknown = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      expect(guessMimeType(unknown, 'xyz'), isNull);
      expect(guessMimeType(unknown, null), isNull);
    });

    test('null bytes falls back to extension', () {
      expect(guessMimeType(null, 'png'), 'image/png');
      expect(guessMimeType(null, null), isNull);
    });
  });

  // =========================================================================
  // parseImageDimensions
  // =========================================================================
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

    test('PNG 1x1', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, // width: 1
        0x00, 0x00, 0x00, 0x01, // height: 1
        0x08, 0x06, 0x00, 0x00, 0x00,
      ]);
      final dims = parseImageDimensions(png);
      expect(dims!.width, 1);
      expect(dims.height, 1);
    });

    test('GIF 800x600', () {
      final gif = Uint8List.fromList([
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
        0x20, 0x03, // width: 800 (little-endian: 0x0320)
        0x58, 0x02, // height: 600 (little-endian: 0x0258)
        0xF7, 0x00, 0x00, // packed, bg color, aspect
      ]);
      final dims = parseImageDimensions(gif);
      expect(dims, isNotNull);
      expect(dims!.width, 800);
      expect(dims.height, 600);
    });

    test('BMP 640x480', () {
      final bmp = Uint8List.fromList([
        0x42, 0x4D, // "BM"
        0x00, 0x00, 0x00, 0x00, // file size (unused)
        0x00, 0x00, 0x00, 0x00, // reserved
        0x00, 0x00, 0x00, 0x00, // data offset
        0x28, 0x00, 0x00, 0x00, // header size: 40
        0x80, 0x02, 0x00, 0x00, // width: 640 (little-endian: 0x00000280)
        0xE0, 0x01, 0x00, 0x00, // height: 480 (little-endian: 0x000001E0)
      ]);
      final dims = parseImageDimensions(bmp);
      expect(dims, isNotNull);
      expect(dims!.width, 640);
      expect(dims.height, 480);
    });

    test('JPEG with SOF0 marker', () {
      // Minimal JPEG: SOI + APP0 + SOF0
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
        0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
        0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xFF, 0xC0, 0x00, 0x11, // SOF0, length 17
        0x08, // precision: 8
        0x04, 0x38, // height: 1080 (big-endian)
        0x07, 0x80, // width: 1920 (big-endian)
        0x03, // components
      ]);
      final dims = parseImageDimensions(jpeg);
      expect(dims, isNotNull);
      expect(dims!.width, 1920);
      expect(dims.height, 1080);
    });

    test('returns null for non-image data', () {
      final text = Uint8List.fromList('Hello, world!'.codeUnits);
      expect(parseImageDimensions(text), isNull);
    });

    test('returns null for null bytes', () {
      expect(parseImageDimensions(null), isNull);
    });

    test('returns null for too-short data', () {
      expect(parseImageDimensions(Uint8List.fromList([0x89, 0x50])), isNull);
    });

    test('returns null for truncated PNG', () {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, // too short
      ]);
      expect(parseImageDimensions(png), isNull);
    });
  });

  // =========================================================================
  // countPdfPages
  // =========================================================================
  group('countPdfPages', () {
    test('counts /Type /Page occurrences', () {
      final pdfContent = '%PDF-1.4\n'
          '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
          '4 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), 2);
    });

    test('excludes /Type /Pages', () {
      final pdfContent = '%PDF-1.4\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), 1);
    });

    test('handles compact /Type/Page form', () {
      final pdfContent = '%PDF-1.4\n'
          '3 0 obj\n<< /Type/Page /Parent 2 0 R >>\nendobj\n'
          '4 0 obj\n<< /Type/Page /Parent 2 0 R >>\nendobj\n'
          '5 0 obj\n<< /Type/Page /Parent 2 0 R >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), 3);
    });

    test('compact form excludes /Type/Pages', () {
      final pdfContent = '%PDF-1.4\n'
          '2 0 obj\n<< /Type/Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
          '3 0 obj\n<< /Type/Page /Parent 2 0 R >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), 1);
    });

    test('returns null for non-PDF data', () {
      final text = Uint8List.fromList('This is not a PDF'.codeUnits);
      expect(countPdfPages(text), isNull);
    });

    test('returns null for null bytes', () {
      expect(countPdfPages(null), isNull);
    });

    test('returns null when no pages found', () {
      final pdfContent = '%PDF-1.4\n'
          '1 0 obj\n<< /Type /Catalog >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), isNull);
    });

    test('respects maxScanBytes limit', () {
      // Create a PDF with a page marker beyond the scan limit
      final header = '%PDF-1.4\n';
      final padding = List.filled(200, 'x').join();
      final pageMarker = '\n3 0 obj\n<< /Type /Page >>\nendobj\n';
      final content = header + padding + pageMarker;
      final bytes = Uint8List.fromList(content.codeUnits);
      // With a small scan limit, the page marker is beyond it
      expect(countPdfPages(bytes, maxScanBytes: 50), isNull);
      // With a large enough limit, it finds the page
      expect(countPdfPages(bytes, maxScanBytes: content.length), 1);
    });
  });
}
