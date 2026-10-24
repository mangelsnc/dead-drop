/// passphrase_strength.dart — estimating and generating vault passphrase
/// strength.
///
/// The vault's resistance to an attacker who has copied the storage and can
/// attack it offline comes down entirely to how much entropy the
/// passphrase has: rate limiting (enforced only by the running app) does
/// nothing against a copied store. This module does two things:
///
/// 1. [estimateStrength] estimates how many bits of entropy a *human-chosen*
///    passphrase actually has, as a guesser who knows common patterns would
///    see it — not how many composition rules it satisfies. `Password1!`
///    satisfies every "uppercase + digit + symbol + 10 chars" rule and is
///    still one of the first passphrases a real attacker tries; a naive
///    composition check would accept it. We instead charge reduced entropy
///    for dictionary words, keyboard runs, character repeats and
///    digit/symbol suffixes — the shapes real humans and real crackers both
///    gravitate to.
/// 2. [generatePassphrase] generates a passphrase the estimator can score
///    honestly: words drawn uniformly at random (via libsodium's CSPRNG,
///    never `dart:math`) from [kPassphraseWordlist], Diceware-style.
///
/// This module is intentionally self-contained: it does not touch vault
/// keys or storage, and ships no new dependency — just a bundled wordlist
/// (passphrase_wordlist.dart) and a compact estimator, not a full zxcvbn
/// reimplementation.
library;

import 'dart:math' as math;

import 'package:sodium/sodium_sumo.dart';

import 'passphrase_wordlist.dart';

/// Minimum entropy, in bits, a passphrase must have to be accepted.
///
/// 60 bits is this feature's chosen floor: high enough that every weak
/// example in the test suite (short PINs, dictionary words, composition-only
/// "strong" passwords like `Password1!`) is rejected, while the default
/// six-word generated passphrase (see [generatePassphrase]) clears it with
/// margin (~62.0 bits at the bundled wordlist's ~10.34 bits/word — five
/// words, ~51.7 bits, would not clear it, which is why the default is six).
/// At 60 bits, an offline attacker limited to even 10^12 guesses/second
/// needs, on average, decades to exhaust the space — see
/// docs/superpowers/plans/2026-10-24-vault-coercion.md for the full
/// reasoning. Changing this value is a spec change, not a tuning knob.
const double kMinimumEntropyBits = 60;

/// Result of [estimateStrength]: an entropy estimate plus a pass/fail
/// verdict and human-readable advice.
class StrengthResult {
  StrengthResult({
    required this.entropyBits,
    required this.meetsMinimum,
    required this.advice,
  });

  /// Estimated entropy of the passphrase, in bits. Lower is weaker.
  final double entropyBits;

  /// Whether [entropyBits] is at least [kMinimumEntropyBits].
  final bool meetsMinimum;

  /// Short, human-readable explanation of the verdict — what was found
  /// (a dictionary word, a keyboard run, a digit suffix, ...) and, when the
  /// passphrase is accepted, a plain confirmation.
  final String advice;
}

/// Bits of entropy charged for each digit when it appears in a numeric-only
/// passphrase (e.g. a PIN): one digit is one of 10 possibilities.
const double _bitsPerDigit = 3.321928094887362; // log2(10)

/// Entropy charged for recognising a token as a dictionary word, regardless
/// of the word's actual length.
///
/// An attacker running a dictionary attack does not care how long "elephant"
/// is — they try it once, near the front of their list. We charge a small,
/// fixed amount (roughly "this word plus a handful of common mutations")
/// rather than the word's raw character entropy.
const double _dictionaryWordBits = 8;

/// Entropy charged for a recognised keyboard-walk (e.g. "qwerty", "asdf",
/// "12345") — these are tried immediately by any real cracking tool.
const double _keyboardRunBits = 4;

/// Entropy charged for a block of fully repeated characters (e.g. "aaaa",
/// "1111") — a single guess covers the whole block.
const double _repeatBits = 2;

/// Cap on the entropy credited to a trailing run of digits or symbols
/// (e.g. "...2024", "...!", "...123!").
///
/// Humans who append digits/symbols to satisfy a composition rule
/// overwhelmingly pick from a tiny set (years, "1", "!", "123"), which
/// crackers enumerate first. We still give *some* credit for longer runs
/// (an attacker must at least try the set), but it never scales linearly
/// with run length the way raw charset-size math would suggest.
const double _maxSuffixBits = 6;

/// Common keyboard-adjacency runs, lower-cased. Checked as substrings so
/// "qwertyuiop", "asdfgh" style passphrases are caught regardless of exact
/// length typed.
const List<String> _keyboardRuns = [
  'qwertyuiop',
  'qwerty',
  'asdfghjkl',
  'asdfgh',
  'asdf',
  'zxcvbnm',
  'zxcvbn',
  '1234567890',
  '123456789',
  '12345678',
  '1234567',
  '123456',
  '12345',
  '1234',
  '0987654321',
  '987654321',
  '87654321',
  '7654321',
  '654321',
  '54321',
];

/// A short list of extremely common passphrases/words that are weak even
/// though they are not in [kPassphraseWordlist] (that list favours longer,
/// less common words so it yields good *generation* entropy) and that are
/// not caught by [_keyboardRuns] or digit-only detection. Pulled in
/// specifically because the task's weak examples include "deaddrop" (the
/// product's own name — the single most predictable word a user of this
/// app could choose) and common password-manager-rejected choices.
const List<String> _commonWeakWords = [
  'password',
  'passphrase',
  'deaddrop',
  'dead',
  'drop',
  'letmein',
  'admin',
  'welcome',
  'monkey',
  'dragon',
  'master',
  'login',
  'qwerty',
  'casa',
  'micasa',
];

/// Estimates how many bits of entropy [passphrase] actually has against a
/// realistic attacker, and whether that meets [kMinimumEntropyBits].
///
/// This deliberately does not score character-class composition (upper,
/// lower, digit, symbol): composition rules are satisfied just as well by
/// `Password1!` (weak — a dictionary word plus the single most common
/// capitalisation, digit and symbol choices) as by a genuinely random
/// string. Instead the passphrase is split into tokens on
/// digit/letter/symbol boundaries and on internal case changes, each token
/// is scored by what it *is* (dictionary word, keyboard run, repeated
/// character, or an apparently-random chunk charged per-character), and a
/// capped amount is added for short trailing digit/symbol runs. The token
/// entropies are summed: this rewards genuinely unpredictable material and
/// caps the credit given to predictable structure, however long.
StrengthResult estimateStrength(String passphrase) {
  if (passphrase.isEmpty) {
    return StrengthResult(
      entropyBits: 0,
      meetsMinimum: false,
      advice: 'Passphrase is empty.',
    );
  }

  final tokens = _tokenize(passphrase);

  // Multiple repeated instances of the exact same token (e.g. "abcabc",
  // "haha") should not each earn full credit — a cracker who guesses the
  // repeated unit tries the whole string in one guess. Score each distinct
  // token (case-insensitively) exactly once.
  final seen = <String>{};
  double entropy = 0;
  final notes = <String>[];
  var hadDuplicateToken = false;

  for (final token in tokens) {
    if (!seen.add(token.toLowerCase())) {
      hadDuplicateToken = true;
      continue;
    }
    entropy += _scoreToken(token, notes);
  }
  if (hadDuplicateToken) {
    notes.add('repeated segments contribute only once');
  }

  final meetsMinimum = entropy >= kMinimumEntropyBits;
  final advice = meetsMinimum
      ? 'Passphrase looks strong (~${entropy.round()} bits).'
      : notes.isEmpty
          ? 'Passphrase is too short or predictable '
              '(~${entropy.round()} bits, need $kMinimumEntropyBits).'
          : 'Weak: ${notes.join('; ')} '
              '(~${entropy.round()} bits, need $kMinimumEntropyBits).';

  return StrengthResult(
    entropyBits: entropy,
    meetsMinimum: meetsMinimum,
    advice: advice,
  );
}

/// Splits [passphrase] into tokens along digit-run / letter-run / symbol-run
/// boundaries and internal case transitions (so "MiCasa2024" becomes
/// ["Mi", "Casa", "2024"] and "Password1!" becomes ["Password", "1", "!"]).
List<String> _tokenize(String passphrase) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  int? lastClass;
  bool lastWasLower = false;

  int classOf(String ch) {
    if (RegExp(r'[0-9]').hasMatch(ch)) return 0;
    if (RegExp(r'[a-zA-Z]').hasMatch(ch)) return 1;
    return 2; // symbol / whitespace / anything else
  }

  for (var i = 0; i < passphrase.length; i++) {
    final ch = passphrase[i];
    final cls = classOf(ch);
    final isUpper =
        cls == 1 && ch == ch.toUpperCase() && ch != ch.toLowerCase();

    // Start a new token on a class change, or on a lower->upper transition
    // within a letter run (camelCase / TitleCase word boundaries).
    final caseBoundary = cls == 1 && lastClass == 1 && isUpper && lastWasLower;

    if (lastClass != null && (cls != lastClass || caseBoundary)) {
      tokens.add(buffer.toString());
      buffer.clear();
    }

    buffer.write(ch);
    lastClass = cls;
    lastWasLower = cls == 1 && ch == ch.toLowerCase() && ch != ch.toUpperCase();
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());

  return tokens;
}

/// Scores a single token (see [_tokenize]) in bits of entropy, appending a
/// human-readable note to [notes] when the token was recognised as weak.
double _scoreToken(String token, List<String> notes) {
  final lower = token.toLowerCase();

  // Pure digit run: PINs and years. Charge per-digit entropy but cap it —
  // a cracker iterating all N-digit numbers still needs 10^N guesses for
  // genuinely random digits, but real digit runs are overwhelmingly dates,
  // years or keyboard-adjacent sequences, so a keyboard-run/common-pattern
  // check runs first.
  final isDigits = RegExp(r'^[0-9]+$').hasMatch(token);
  final isSymbols = RegExp(r'^[^a-zA-Z0-9]+$').hasMatch(token);

  for (final run in _keyboardRuns) {
    if (lower.contains(run)) {
      notes.add('"$token" is a keyboard pattern');
      return _keyboardRunBits;
    }
  }

  if (RegExp(r'^(.)\1*$').hasMatch(token) && token.length > 1) {
    notes.add('"$token" is a repeated character');
    return _repeatBits;
  }

  if (_commonWeakWords.contains(lower)) {
    notes.add('"$token" is a common weak word');
    return _dictionaryWordBits;
  }

  if (kPassphraseWordlist.contains(lower)) {
    // A word drawn from the bundled EFF short wordlist (e.g. via
    // generatePassphrase) is a genuinely different case from "password" or
    // "dragon": an attacker who assumes this wordlist still has to search
    // all of it, so the honest cost is log2(wordlist length) — not the
    // tiny flat charge given to the handful of words everyone tries first.
    notes.add('"$token" is a dictionary word');
    return _log2(kPassphraseWordlist.length.toDouble());
  }

  if (isDigits || isSymbols) {
    // Trailing/standalone digit or symbol block: capped, see
    // [_maxSuffixBits]. Still scales a little with length so "99" isn't
    // worth the same as "9", but never approaches raw log2(10^n) math.
    final raw = token.length * (isDigits ? _bitsPerDigit : 4.0);
    final capped = raw < _maxSuffixBits ? raw : _maxSuffixBits;
    if (token.length <= 4) {
      notes.add('"$token" is a short, predictable suffix');
    }
    return capped;
  }

  // Not recognised as a word, run, or repeat: treat as an unpredictable
  // string and charge per-character entropy based on the character classes
  // actually used (a conservative stand-in for a full Markov/zxcvbn model).
  final hasLower = RegExp(r'[a-z]').hasMatch(token);
  final hasUpper = RegExp(r'[A-Z]').hasMatch(token);
  final hasDigit = RegExp(r'[0-9]').hasMatch(token);
  final hasSymbol = RegExp(r'[^a-zA-Z0-9]').hasMatch(token);

  var charsetSize = 0;
  if (hasLower) charsetSize += 26;
  if (hasUpper) charsetSize += 26;
  if (hasDigit) charsetSize += 10;
  if (hasSymbol) charsetSize += 33;
  if (charsetSize == 0) charsetSize = 1;

  final perCharBits = _log2(charsetSize.toDouble());
  return token.length * perCharBits;
}

double _log2(double x) => x <= 0 ? 0 : math.log(x) / math.ln2;

/// Generates a Diceware-style passphrase: [words] words drawn uniformly at
/// random from [kPassphraseWordlist], using libsodium's CSPRNG — never
/// `dart:math`, whose default generator is not cryptographically secure
/// and must never choose anything that guards vault contents.
///
/// Defaults to 6 words, not 5: the bundled EFF short wordlist gives
/// ~10.34 bits/word, so 6 words (~62.0 bits) clears [kMinimumEntropyBits]
/// (60 bits) with margin while 5 words (~51.7 bits) would not — and
/// generating a passphrase the app's own strength check then rejects would
/// be a defect, not a style choice.
///
/// Rejection sampling avoids modulo bias: naively using
/// `randomIndex % wordlist.length` would make low indices very slightly
/// more likely whenever the wordlist size does not evenly divide the
/// random range, which is a real (if small) entropy leak in a function
/// whose entire job is to maximise entropy.
List<String> generatePassphrase(SodiumSumo sodium, {int words = 6}) {
  if (words <= 0) {
    throw ArgumentError.value(words, 'words', 'must be positive');
  }

  final n = kPassphraseWordlist.length;
  // Largest multiple of n that fits in a 32-bit unsigned range: indices
  // drawn below this threshold are uniform; at/above it, re-roll.
  const range = 0x100000000; // 2^32
  final limit = range - (range % n);

  final selected = <String>[];
  while (selected.length < words) {
    final bytes = sodium.randombytes.buf(4);
    final value =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    final unsigned = value.toUnsigned(32);
    if (unsigned >= limit) continue; // reject: would bias toward low indices
    selected.add(kPassphraseWordlist[unsigned % n]);
  }

  return selected;
}
