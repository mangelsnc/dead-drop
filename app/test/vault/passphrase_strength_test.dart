/// Tests for passphrase strength estimation and generation
/// (app/lib/src/vault/passphrase_strength.dart).
///
/// The headline property under test: entropy is estimated, not composition.
/// `Password1!` satisfies every "uppercase + digit + symbol + 10 chars"
/// rule and must still be rejected, because it is a dictionary word plus
/// the single most predictable capitalisation/digit/symbol choices.
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/passphrase_strength.dart';
import 'package:dead_drop/src/vault/passphrase_wordlist.dart';

void main() {
  group('estimateStrength', () {
    test('rejects known-weak passphrases', () {
      for (final weak in ['Password1!', 'MiCasa2024', '123456', 'deaddrop']) {
        expect(estimateStrength(weak).meetsMinimum, isFalse, reason: weak);
      }
    });

    test('rejects an empty passphrase', () {
      final result = estimateStrength('');
      expect(result.meetsMinimum, isFalse);
      expect(result.entropyBits, equals(0));
    });

    test('a six-digit PIN does not meet the minimum', () {
      final result = estimateStrength('483921');
      expect(result.meetsMinimum, isFalse);
      // Well below the floor — a 6-digit PIN is at most ~20 bits even
      // charged at full log2(10) per digit, and this estimator caps digit
      // runs below that.
      expect(result.entropyBits, lessThan(kMinimumEntropyBits));
    });

    test('rejects a plain keyboard walk', () {
      expect(estimateStrength('qwertyuiop').meetsMinimum, isFalse);
    });

    test('rejects a block of repeated characters', () {
      expect(estimateStrength('aaaaaaaaaaaa').meetsMinimum, isFalse);
    });

    test('rejects an ascending alphabet walk', () {
      expect(
          estimateStrength('abcdefghijklmnopqrstuvwxyz').meetsMinimum, isFalse);
    });

    test('rejects a descending alphabet walk', () {
      expect(
          estimateStrength('zyxwvutsrqponmlkjihgfedcba').meetsMinimum, isFalse);
    });

    test('rejects unbroken-lowercase sentence passphrases', () {
      // Regression test for a critical defect: _tokenize only splits on
      // character-class changes, so a passphrase typed as one continuous
      // lowercase run (no spaces, digits or punctuation) used to be a
      // single token that matched neither _commonWeakWords nor
      // kPassphraseWordlist as a *whole string*, and fell through to the
      // per-character branch — scoring "thisismypassword" as if it were
      // random text, at ~4.7 bits/char. This is the `Password1!` lesson
      // one level up, and it matters more: "use a long sentence" is advice
      // people actually follow. _scoreLetterRun's greedy word segmenter is
      // what's supposed to catch these now.
      for (final weak in [
        'thisismypassword',
        'iloveyouforever',
        'myvaultismine',
        'nooneisabovethelaw',
        'freedomofthepress',
      ]) {
        final result = estimateStrength(weak);
        expect(result.meetsMinimum, isFalse,
            reason: '$weak (~${result.entropyBits} bits)');
      }
    });

    test('accepts a long, unpredictable random string', () {
      // 24 chars drawn from a mixed charset is far above the floor even
      // under this estimator's conservative per-character accounting.
      final result = estimateStrength('xQ7!kP2@mZ9#vL4\$wR8%jN3^');
      expect(result.meetsMinimum, isTrue);
    });

    test('accepts a generated six-word passphrase', () {
      // Independent of generatePassphrase: assembles words directly from
      // the bundled wordlist so this test has no libsodium dependency.
      // Six words at the bundled list's ~10.34 bits/word is what
      // generatePassphrase's default actually produces (~62 bits); five
      // words (~51.7 bits) would not clear the floor, which is exactly why
      // the default word count is six, not five.
      final passphrase = [10, 200, 500, 800, 1100, 1290]
          .map((i) => kPassphraseWordlist[i])
          .join(' ');
      final result = estimateStrength(passphrase);
      expect(result.meetsMinimum, isTrue, reason: passphrase);
    });

    test('a five-word passphrase from the bundled list falls short', () {
      // Documents the exact tradeoff behind the six-word default: five
      // words from this list is expected to land just under the floor.
      final passphrase = [10, 200, 500, 800, 1100]
          .map((i) => kPassphraseWordlist[i])
          .join(' ');
      final result = estimateStrength(passphrase);
      expect(result.meetsMinimum, isFalse, reason: passphrase);
    });
  });

  group('generatePassphrase', () {
    late SodiumSumo sodium;

    setUpAll(() async {
      sodium = await SodiumSumoInit.init();
    });

    test('defaults to 6 words', () {
      final words = generatePassphrase(sodium);
      expect(words, hasLength(6));
    });

    test('returns the requested number of words', () {
      final words = generatePassphrase(sodium, words: 5);
      expect(words, hasLength(5));
    });

    test(
        'every generated six-word passphrase meets the minimum entropy, '
        'regardless of which words are drawn', () {
      // Regression coverage for a real near-miss during review: a word
      // that happens to be both in kPassphraseWordlist (generation) and
      // kCommonWordsForDetection (a broad, everyday-word list used to
      // catch dictionary words typed as part of a sentence) must still be
      // charged the full EFF-list rate when scoring a generated
      // passphrase — about a quarter of the bundled EFF words are also
      // ordinary English words, so if even one word in a 6-word
      // passphrase were charged the cheaper "common word" rate instead,
      // entropy could fall under the 60-bit floor the estimator itself
      // enforces. Generating a large sample and checking every one (not
      // just a single lucky/unlucky draw) is what actually exercises
      // that: a single-sample test could pass or fail depending on which
      // words happened to come out.
      for (var i = 0; i < 100; i++) {
        final words = generatePassphrase(sodium, words: 6);
        final result = estimateStrength(words.join(' '));
        expect(result.meetsMinimum, isTrue,
            reason: '${words.join(' ')} (~${result.entropyBits} bits)');
      }
    });

    test('a generated six-word passphrase clears the minimum with margin', () {
      final words = generatePassphrase(sodium, words: 6);
      final result = estimateStrength(words.join(' '));
      // ~62.0 bits expected (6 * log2(1296)); require strictly more than
      // the floor so this would fail if the wordlist or word count ever
      // regressed to something that only just scrapes by.
      expect(result.entropyBits, greaterThan(kMinimumEntropyBits));
    });

    test('two generated passphrases differ (not a fixed sequence)', () {
      final a = generatePassphrase(sodium, words: 6);
      final b = generatePassphrase(sodium, words: 6);
      expect(a, isNot(equals(b)));
    });

    test(
        'draws from the full wordlist with no degenerate bias '
        '(not dart:math, not an off-by-one, not a broken index)', () {
      // Generating many passphrases and checking the distribution catches
      // what actually matters here, and catches it for the right reason:
      // a `dart:math`-backed implementation seeded identically every call
      // would produce the same passphrase every time; an off-by-one that
      // clamps the index range would never reach the last word(s); a
      // modulo-bias or indexing bug would skew heavily toward a handful of
      // words. Checking the source text for "sodium.randombytes" would
      // miss all of these and would break on an unrelated rename.
      const generations = 200;
      const wordsPerPassphrase = 6;

      final passphrases = <String>{};
      final wordsSeen = <String>{};
      for (var i = 0; i < generations; i++) {
        final words = generatePassphrase(sodium, words: wordsPerPassphrase);
        expect(words, hasLength(wordsPerPassphrase));
        for (final word in words) {
          expect(kPassphraseWordlist, contains(word));
        }
        passphrases.add(words.join(' '));
        wordsSeen.addAll(words);
      }

      // No two of the 200 generated passphrases should collide — at
      // ~62 bits of entropy each, a collision is astronomically unlikely
      // and would indicate a degenerate (non-random, or narrow-range)
      // generator.
      expect(passphrases, hasLength(generations));

      // Across 200 * 6 = 1200 draws from a 1,296-word list, a healthy
      // uniform generator should touch a large fraction of the list, not
      // cluster on a handful of indices (which an off-by-one or a modulo
      // bug would do).
      expect(wordsSeen.length, greaterThan(kPassphraseWordlist.length ~/ 2));
    });
  });
}
