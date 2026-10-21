/// chunking.dart — chunk-size selection and file-size validation.
///
/// The session header packs `chunkCount` as a **uint16**, so a transfer can
/// carry at most [maxChunkCount] chunks. With the default 512-byte chunk that
/// ceiling is ~32 MB; `ByteData.setUint16` truncates silently on overflow, so
/// without an explicit check a too-large file would corrupt the header and the
/// transfer would fail incomprehensibly on the receiver.
///
/// This module is the single source of truth for:
///   * which chunk sizes the app offers ([kChunkSizeOptions]),
///   * picking the smallest chunk size that fits a file ([recommendedChunkSize]),
///   * turning an oversized file into a clear, jargon-free message
///     ([fileSizeError] / [fileTooLargeError]).
///
/// It is pure Dart (no Flutter UI imports) so both the send page and the unit
/// tests can use it without pulling in platform plugins.
library;

import 'crypto.dart';

/// Chunk sizes offered in the UI, ascending. Larger chunks fit larger files
/// (the uint16 `chunkCount` caps a transfer at [maxChunkCount] chunks) but
/// produce denser QR codes that are harder for the camera to scan reliably.
const List<int> kChunkSizeOptions = [256, 512, 1024, 2048, 4096];

/// The chunk size used when the user has not chosen one. Matches the value
/// the spike validated as the best throughput / scannability trade-off.
const int kDefaultChunkSize = 512;

/// The recommended chunk size for a file of [fileSize] bytes.
///
/// Small files keep [kDefaultChunkSize] — the size the spike validated as the
/// best throughput / scannability trade-off — rather than dropping to a
/// smaller chunk that would only inflate the frame count. We only scale *up*
/// (never below the default) when the file would overflow the uint16
/// `chunkCount` field at the current size.
///
/// Returns the largest option when even that cannot fit the file — callers
/// must then surface [fileTooLargeError] instead of starting the transfer.
int recommendedChunkSize(int fileSize) {
  for (final size in kChunkSizeOptions) {
    // Never go below the validated default — smaller chunks only add frames.
    if (size < kDefaultChunkSize) continue;
    if (fileSize <= maxFileSizeForChunkSize(size)) return size;
  }
  return kChunkSizeOptions.last;
}

/// A jargon-free error message when [fileSize] cannot be transferred with
/// [chunkSize], or null when it fits. The message states the limit and points
/// at the fix (a larger chunk size) so a non-technical user is not stuck.
String? fileSizeError(int fileSize, int chunkSize) {
  final maxSize = maxFileSizeForChunkSize(chunkSize);
  if (fileSize <= maxSize) return null;
  return 'This file is too large to send with the current chunk size.\n'
      'Maximum: ${formatSizeForMessage(maxSize)}. '
      'Increase the chunk size in Options and try again.';
}

/// The error to show when no available chunk size can fit [fileSize].
String fileTooLargeError(int fileSize) {
  final maxSize = maxFileSizeForChunkSize(kChunkSizeOptions.last);
  return 'This file is too large to send.\n'
      'Maximum: ${formatSizeForMessage(maxSize)}.';
}

/// Human-readable byte size for user-facing messages (e.g. "33.55 MB").
String formatSizeForMessage(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
