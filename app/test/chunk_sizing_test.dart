/// Chunk-size selection, sized by how many codes the user must scan.
///
/// Reported from a phone: a 653 KB photo was split into 2,614 chunks and
/// needed roughly 2.5x that many frames scanned before it completed. The
/// fountain code was not at fault — measured overhead is 1.15x at that
/// chunk count — but every extra code is another chance to miss one.
library;

import 'package:dead_drop/src/chunking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int chunksFor(int bytes) => bytes ~/ recommendedChunkSize(bytes);

  test('a small file keeps the validated default', () {
    expect(recommendedChunkSize(8 * 1024), kDefaultChunkSize,
        reason: 'the size the spike measured, on the size it measured it');
  });

  test('the reported 653 KB photo no longer makes thousands of codes', () {
    const photo = 653 * 1024;
    const before = photo ~/ kDefaultChunkSize; // what 512 B would give
    final after = chunksFor(photo);

    expect(before, greaterThan(1000));
    expect(after, lessThan(1000),
        reason: 'scanning 1,300 codes by hand is the actual bottleneck');
    expect(after * 2, lessThanOrEqualTo(before + 2),
        reason: 'the next size up is twice the bytes, so half the codes');

    // Against what the phone actually used — the hint had halved the
    // chunk to 256 B on a poor decode rate, which is where the reported
    // 2,614 came from.
    expect(after * 4, lessThanOrEqualTo(2614 + 4),
        reason: 'a quarter of what the device was really scanning');
  });

  test('chunk count stays reasonable across realistic file sizes', () {
    // Up to the point where the largest chunk is already in use, the
    // count stays within reach. Beyond that it can only grow with the
    // file, which is a property of the format, not a choice.
    // Up to 2 MB the count stays within reach. Past that it can only
    // grow: 2048 bytes is the largest chunk a QR can carry at any error
    // correction, so a bigger file simply needs more codes. That is a
    // property of the format, not a choice this function makes.
    for (final kb in [64, 256, 653, 1024]) {
      final bytes = kb * 1024;
      expect(chunksFor(bytes), lessThanOrEqualTo(1100),
          reason: '$kb KB produced ${chunksFor(bytes)} codes');
    }
  });

  test('a large file takes the biggest chunk rather than the smallest', () {
    // The fallback used to return the FIRST fitting size, which is
    // always the default, so a 16 MB file came out as 32,768 codes.
    expect(recommendedChunkSize(16 * 1024 * 1024), kChunkSizeOptions.last);
  });

  test('a big file is slow, and that is the format, not a bug', () {
    // Worth stating: 2048 bytes is the ceiling a QR can carry, so a
    // 4 MB file is 2,048 codes however it is sliced. Anyone surprised
    // by a long transfer should find the reason written down.
    expect(chunksFor(4 * 1024 * 1024), 2048);
    expect(kChunkSizeOptions.last, 2048);
  });

  test('the chosen size can always carry the file', () {
    for (final kb in [8, 64, 653, 4096, 16384]) {
      final bytes = kb * 1024;
      final size = recommendedChunkSize(bytes);
      expect(fileSizeError(bytes, size), isNull,
          reason: '$kb KB must be sendable at the size recommended for it');
    }
  });
}
