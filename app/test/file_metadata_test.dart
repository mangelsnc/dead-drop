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
    test('returns null for null input', () {
      expect(countPdfPages(null), isNull);
    });
  });
}
