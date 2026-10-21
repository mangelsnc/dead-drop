import 'package:dead_drop/src/file_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
