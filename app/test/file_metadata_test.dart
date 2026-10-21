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
      const pdfContent = '%PDF-1.4\n'
          '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n'
          '4 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits);
      expect(countPdfPages(bytes), 2);
    });
  });
}
