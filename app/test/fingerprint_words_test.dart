/// A fingerprint a person can read aloud.
///
/// TOFU asks the user to check a sender's fingerprint "through another
/// channel" — in practice, reading it to the other person over the phone
/// and hearing it read back. Sixteen hex characters is a poor thing to
/// read aloud: `6bcdd4fd124dfacd` has no rhythm, no way to tell `b` from
/// `d` by ear, and nothing to notice if two differ in one place.
///
/// The same bits as words from the EFF short list are read aloud,
/// spelled and compared by people without effort, which is the only way
/// the check ever actually happens.
///
/// This is a rendering of the fingerprint, not a replacement: the hex
/// stays on screen, and nothing about what is verified changes.
library;

import 'package:dead_drop/src/fingerprint_words.dart';
import 'package:dead_drop/src/vault/passphrase_wordlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fingerprintWords', () {
    test('is stable for the same fingerprint', () {
      // Both devices render the same key the same way, or the
      // comparison the user is asked to make is meaningless — the same
      // reason fingerprintOf lives in one place.
      expect(fingerprintWords('6bcdd4fd124dfacd'),
          fingerprintWords('6bcdd4fd124dfacd'));
    });

    test('differs when the fingerprint differs', () {
      expect(fingerprintWords('6bcdd4fd124dfacd'),
          isNot(fingerprintWords('6bcdd4fd124dface')));
    });

    test('is three words from the bundled list', () {
      final words = fingerprintWords('6bcdd4fd124dfacd')!.split(' ');

      expect(words, hasLength(3));
      for (final word in words) {
        expect(kPassphraseWordlist, contains(word.toLowerCase()),
            reason: '$word is not a word anyone can be asked to spell');
      }
    });

    test('a changed character anywhere changes the words', () {
      // A rendering that only reflected part of the fingerprint would
      // let two different senders read the same words aloud, which is
      // worse than no rendering at all: it would make a mismatch sound
      // like a match.
      const base = '0123456789abcdef';
      final rendered = fingerprintWords(base);
      for (var i = 0; i < base.length; i++) {
        final altered = base.replaceRange(
            i, i + 1, base[i] == '0' ? '1' : '0');
        expect(fingerprintWords(altered), isNot(rendered),
            reason: 'changing character $i left the words unchanged, so '
                'two different keys would read aloud the same');
      }
    });

    test('a short or empty fingerprint renders nothing', () {
      expect(fingerprintWords(''), isNull);
      expect(fingerprintWords('abc'), isNull);
    });
  });

  _nameFallbackTests();
}

/// The words also stand in for a name nobody typed.
///
/// A sender accepted without a name was shown later as sixteen hex
/// characters, which tells the recipient nothing about who sent them a
/// file. The words are already what the two people read to each other,
/// so they are the name that was in fact agreed — and a better default
/// than a blank.
void _nameFallbackTests() {
  group('suggestedSenderName', () {
    test('is the words, so it matches what was read aloud', () {
      const fp = '6bcdd4fd124dfacd';
      expect(suggestedSenderName(fp), fingerprintWords(fp));
    });

    test('is null when there is no whole fingerprint to render', () {
      expect(suggestedSenderName('abc'), isNull);
    });
  });
}
