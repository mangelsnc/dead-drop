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
