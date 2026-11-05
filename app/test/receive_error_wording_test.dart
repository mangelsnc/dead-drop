/// The receive screen says what to do, not what the parser found.
///
/// Both of these reached a real user on 2026-11-05. "Session rejected:
/// Unsupported version" is what the screen showed when the other device
/// was running an older build — true, and useless: it names a field in
/// a header rather than the thing to fix. "Session not addressed to
/// this receiver" is the same shape, and arrives when the sender
/// scanned somebody else's key, or an older copy of this one.
///
/// A person who cannot act on an error is a person watching a transfer
/// that does not start, which is what happened.
library;

import 'package:dead_drop/ui/receive/receive_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a rejected session explains itself', () {
    test('a version mismatch names the fix, not the field', () {
      final text = sessionRejectionMessage('Unsupported version');

      expect(text, contains('version'));
      // The actionable part: both devices need the same build.
      expect(text.toLowerCase(), contains('update'));
      expect(
        text,
        isNot(contains('Unsupported version')),
        reason: 'the raw parser message is not an instruction',
      );
    });

    test('a key mismatch says whose key to scan', () {
      final text =
          sessionRejectionMessage('Session not addressed to this receiver');

      expect(text.toLowerCase(), contains('scan'));
      expect(text.toLowerCase(), contains('key'));
    });

    test('an unrecognised reason is still shown', () {
      // Never swallow a message we did not anticipate: an error with no
      // text is worse than a technical one.
      final text = sessionRejectionMessage('Signature check failed');

      expect(text, contains('Signature check failed'));
    });
  });
}
