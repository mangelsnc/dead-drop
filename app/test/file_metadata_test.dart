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
          '3 0 obj\n<< /Type /Page >>\nendobj\n'
          '4 0 obj\n<< /Type /Page >>\nendobj\n';
      final bytes = Uint8List.fromList(pdfContent.codeUnits.toList());
      expect(countPdfPages(bytes), 2);
    });
  });
}
