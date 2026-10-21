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
      // Build PDF bytes as an explicit int list (no String.codeUnits).
      const pdfSource = '%PDF-1.4\n'
          '3 0 obj\n<< /Type /Page >>\nendobj\n'
          '4 0 obj\n<< /Type /Page >>\nendobj\n';
      final bytes = Uint8List.fromList(
        pdfSource.codeUnits.map((c) => c & 0xFF).toList(),
      );
      expect(countPdfPages(bytes), 2);
    });
  });
}
