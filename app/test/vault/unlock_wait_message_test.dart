/// A wait the user cannot see reads as a broken app.
///
/// The unlock path serves its rate-limiting penalty inside `unlock()`,
/// before the attempt. On the fourth wrong passphrase that is five
/// seconds of a spinner and nothing else; on the fifth, ten. Reported
/// on 2026-11-05 by someone who knows the code and still read it as
/// the app having hung — which is the moment a person force-quits, and
/// force-quitting is exactly what the pause exists to discourage.
///
/// So the wait is announced. What is announced is only the wait:
/// nothing here says a self-destruct is approaching, because the
/// threat model includes coercion and a countdown to erasure tells
/// whoever is standing over the owner when to stop.
library;

import 'package:dead_drop/src/vault/attempt_guard.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the wait message', () {
    test('says nothing before the free attempts are spent', () {
      expect(unlockWaitMessage(Duration.zero), isNull);
    });

    test('names the wait in seconds', () {
      final text = unlockWaitMessage(const Duration(seconds: 10));

      expect(text, isNotNull);
      expect(text, contains('10'));
      expect(text!.toLowerCase(), contains('second'));
    });

    test('says nothing about self-destruct, at any penalty', () {
      // Every penalty the guard can produce, including the last one
      // before the threshold. A countdown to erasure would tell a
      // coercer when to stop.
      for (var failures = kFreeAttempts;
          failures <= kSelfDestructThreshold;
          failures++) {
        final steps = failures - kFreeAttempts + 1;
        final raw = kPenaltyStep * steps;
        final penalty = raw > kMaxPenalty ? kMaxPenalty : raw;
        final text = unlockWaitMessage(penalty)!.toLowerCase();

        for (final word in ['destruct', 'destroy', 'erase', 'wipe',
            'delete', 'attempts left', 'remaining']) {
          expect(text, isNot(contains(word)),
              reason: 'the wait message must not hint at self-destruct, '
                  'and at $failures failures it said: $text');
        }
      }
    });

    test('rounds a sub-second remainder up rather than to zero', () {
      // A countdown ticking to "0 seconds" while the field is still
      // disabled is the same confusion in miniature.
      expect(unlockWaitMessage(const Duration(milliseconds: 1)),
          contains('1'));
    });
  });
}
