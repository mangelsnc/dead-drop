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
///    composition check would accept it. Likewise, a passphrase typed as a
///    plain sentence ("freedomofthepress") has no composition at all to
///    flag but is just as predictable. We instead charge reduced entropy
///    for dictionary words — found anywhere inside an unbroken run of
///    letters, not just when the whole token is one known word — keyboard
///    and alphabet runs, character repeats, and digit/symbol suffixes: the
///    shapes real humans and real crackers both gravitate to.
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
///
/// Plain alphabet walks ("abcdef...", "...zyxwv") are *not* listed here —
/// they are checked separately in [_containsAlphabetRun] because they can
/// start at any letter and run any length, which a fixed substring list
/// cannot express.
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

/// Shortest run length that counts as an alphabet walk (e.g. "abcd" or
/// "zyxw"). Below this, short ascending/descending runs ("ab", "xy") are
/// common enough inside genuine words that flagging them would be noisy
/// without meaningfully helping an attacker.
const int _minAlphabetRunLength = 4;

/// The lowest entropy a run of [_minAlphabetRunLength] consecutive
/// unmatched letters can have before we additionally check whether it's an
/// alphabet walk — see [_scoreToken].
const double _alphabetRunBits = 4;

/// A short list of extremely common whole passphrases/words that are weak
/// even though they are not in [kPassphraseWordlist] (that list favours
/// longer, less common words so it yields good *generation* entropy) and
/// are not general-purpose enough to belong in
/// [kCommonWordsForDetection]. Pulled in specifically because the task's
/// weak examples include "deaddrop" — the product's own name, the single
/// most predictable word a user of this app could choose — plus a handful
/// of the passwords every leaked-password-list study puts at the top.
///
/// Fragments that only existed to patch around the old "whole token only"
/// matching ("dead", "drop", "casa", "micasa") were removed: "dead"/"drop"
/// were never real passphrase-strength signals on their own (they existed
/// only to catch half of "deaddrop", which whole-token matching — and now
/// segmentation too — catches directly against "deaddrop" itself), and
/// "casa"/"micasa" were a Spanish-specific patch for one example
/// (`MiCasa2024`) that is still rejected without them: `_tokenize` splits
/// it into "Mi", "Casa", "2024", and both letter chunks already score low
/// enough on plain per-character entropy (neither is in any bundled
/// English-word list) that the digit suffix cap can't rescue it.
const List<String> _commonWeakWords = [
  'password',
  'passphrase',
  'deaddrop',
  'letmein',
  'admin',
  'welcome',
  'monkey',
  'dragon',
  'master',
  'login',
  'qwerty',
];

/// [kPassphraseWordlist] as a [Set], for O(1) "could this word have come
/// from generatePassphrase?" checks during segmentation (see
/// [_scoreLetterRun]) instead of the O(n) scan a [List] would need.
final Set<String> _eflWordlistSet = kPassphraseWordlist.toSet();

/// Combined dictionary used by [_scoreLetterRun] to recognise words
/// *inside* an unbroken run of letters, not just a whole token. Built once
/// from all three word sources: the small generation-oriented
/// [kPassphraseWordlist], the broad detection-oriented
/// [kCommonWordsForDetection], and the hand-picked [_commonWeakWords]. A
/// [Set] so membership checks (performed for every substring tried during
/// segmentation) are O(1).
final Set<String> _segmentationDictionary = {
  ..._eflWordlistSet,
  ...kCommonWordsForDetection,
  ..._commonWeakWords,
};

/// Longest word length worth trying during segmentation, derived from the
/// dictionary itself so this never silently misses a longer bundled word.
final int _maxDictionaryWordLength = _segmentationDictionary.isEmpty
    ? 0
    : _segmentationDictionary.map((w) => w.length).reduce(math.max);

/// Shortest word length [_scoreLetterRun]'s segmenter will match. Two-letter
/// "words" in a frequency-ranked word list are overwhelmingly noise
/// (abbreviations, scanning artefacts) rather than genuine low-entropy
/// picks, and matching them would let a segmenter claim credit for
/// essentially nothing (e.g. treating "ab" as a recognised word inside an
/// alphabet walk).
const int _minSegmentWordLength = 3;

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

  // Every token is scored independently, including tokens that repeat
  // elsewhere in the passphrase (e.g. the same word chosen twice by
  // generatePassphrase, or "ab" appearing twice in "ababab"). This is
  // deliberate: a dictionary word or a random chunk at one position is an
  // independent draw from an attacker's perspective, and knowing position
  // N is "growl" tells a cracker nothing about position M — so each
  // occurrence still costs its own search. (An earlier version of this
  // function deduplicated repeated tokens to avoid over-crediting
  // genuinely structural repeats like "aaaa"; those are already caught
  // separately by the repeated-character check in [_scoreToken], so the
  // extra token-level dedup was removed after it was found to
  // under-credit generatePassphrase output whenever the CSPRNG happened
  // to draw the same word twice.)
  double entropy = 0;
  final notes = <String>[];

  for (final token in tokens) {
    entropy += _scoreToken(token, notes);
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
  final isLetters = RegExp(r'^[a-zA-Z]+$').hasMatch(token);

  if (token.trim().isEmpty) {
    // Whitespace-only token (the separator between words in e.g. a
    // generatePassphrase passphrase, or any human-typed "word word word"
    // passphrase). A space between words is a free, expected structural
    // choice, not a secret an attacker has to guess — a dictionary/Diceware
    // cracker already assumes words are space-separated. Charging it as
    // generic symbol entropy would inflate every multi-word passphrase's
    // score by a few bits per gap for no real security reason, which
    // matters here: it previously masked a real accounting bug (see the
    // five-word regression test) by adding unearned entropy on top of the
    // genuine per-word cost.
    return 0;
  }

  for (final run in _keyboardRuns) {
    if (lower.contains(run)) {
      notes.add('"$token" is a keyboard pattern');
      return _keyboardRunBits;
    }
  }

  if (isLetters && _containsAlphabetRun(lower)) {
    notes.add('"$token" contains an alphabet sequence');
    return _alphabetRunBits;
  }

  if (RegExp(r'^(.)\1*$').hasMatch(token) && token.length > 1) {
    notes.add('"$token" is a repeated character');
    return _repeatBits;
  }

  if (isLetters) {
    // Letters-only: segment the whole run against the combined dictionary
    // instead of only checking whether the *entire* token is one known
    // word. Typed as one continuous run (no punctuation/case/digit
    // boundaries for _tokenize to split on), a phrase like
    // "thisismypassword" or "freedomofthepress" is a single token here —
    // without segmentation it would fall straight through to the
    // per-character branch below and be scored as if it were random,
    // which is exactly the `Password1!` mistake one level up: a passphrase
    // built entirely from predictable dictionary words must not score as
    // high as truly random text of the same length.
    return _scoreLetterRun(token, notes);
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

  // Mixed token (e.g. letters + digits with no boundary _tokenize caught,
  // which shouldn't normally happen but is handled defensively): treat as
  // unpredictable and charge per-character entropy based on the character
  // classes actually used.
  return _perCharacterBits(token) * token.length;
}

/// Scores a letters-only [token] by greedily segmenting it into known
/// dictionary words (longest match first) and charging the unmatched
/// leftover characters at plain per-character entropy.
///
/// Matches against [_segmentationDictionary] win over nothing at all: a
/// matched word is charged log2([kPassphraseWordlist] length) whenever the
/// matched substring is actually *in* [kPassphraseWordlist] — i.e.
/// whenever it's a word [generatePassphrase] could have produced — and
/// [_dictionaryWordBits] (a cheaper flat charge) otherwise, while every
/// character that cannot be attributed to a known word keeps its full
/// per-character cost.
///
/// The "is it in kPassphraseWordlist" check, not "is it common", is what
/// has to decide the rate. About a quarter of the EFF list's words are
/// also everyday English words ("drive", "same", "rock", ...), so charging
/// the cheaper common-word rate whenever a word happens to be common would
/// make a generated passphrase's entropy depend on which words the CSPRNG
/// happened to pick — and with 6 words at ~10.34 bits each and only ~2
/// bits of margin over [kMinimumEntropyBits], even a single word getting
/// the cheaper ~8-bit rate could push a genuinely-random 6-word passphrase
/// below the floor generatePassphrase is supposed to guarantee. Keying the
/// rate on wordlist membership instead means every [kPassphraseWordlist]
/// word always costs the same, regardless of whether a human or the
/// CSPRNG chose it, so generatePassphrase's output is never penalised —
/// while a sentence built from ordinary words that never cross into
/// [kPassphraseWordlist] (e.g. "the", "one", "above", "law") still gets
/// the cheap rate that reflects how early a real cracker tries them.
///
/// A passphrase that is entirely recognised words (any mix of the
/// dictionaries) is charged only for those words, however long it is; a
/// passphrase with no recognisable words falls back to exactly the
/// per-character scoring a letters-only token without this segmentation
/// step would have received.
double _scoreLetterRun(String token, List<String> notes) {
  final lower = token.toLowerCase();
  final n = lower.length;
  var i = 0;
  var bits = 0.0;
  var unmatchedChars = 0;
  var matchedWords = 0;
  final eflWordBits = _log2(kPassphraseWordlist.length.toDouble());

  while (i < n) {
    String? match;
    final maxLen = math.min(_maxDictionaryWordLength, n - i);
    for (var len = maxLen; len >= _minSegmentWordLength; len--) {
      final candidate = lower.substring(i, i + len);
      if (_segmentationDictionary.contains(candidate)) {
        match = candidate;
        break;
      }
    }

    if (match != null) {
      matchedWords++;
      bits +=
          _eflWordlistSet.contains(match) ? eflWordBits : _dictionaryWordBits;
      i += match.length;
    } else {
      unmatchedChars++;
      i++;
    }
  }

  if (unmatchedChars > 0) {
    bits += unmatchedChars * _perCharacterBits(token);
  }

  if (matchedWords > 0) {
    notes.add(matchedWords == 1
        ? '"$token" contains a dictionary word'
        : '"$token" is made of $matchedWords dictionary words');
  }

  return bits;
}

/// Per-character entropy for [token], based on which character classes it
/// actually uses (upper/lower letters, digits, symbols) — a conservative
/// stand-in for a full Markov/zxcvbn model, used for whatever text isn't
/// attributable to a recognised word, run, or pattern.
double _perCharacterBits(String token) {
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

  return _log2(charsetSize.toDouble());
}

/// Whether lower-cased [lower] contains an ascending or descending run of
/// [_minAlphabetRunLength] or more consecutive alphabet letters (e.g.
/// "abcd", "zyxw") anywhere inside it. Unlike [_keyboardRuns] (a fixed
/// list of substrings), an alphabet walk can start at any letter, so it
/// needs an actual scan rather than a substring check.
bool _containsAlphabetRun(String lower) {
  var ascRun = 1;
  var descRun = 1;
  for (var i = 1; i < lower.length; i++) {
    final prev = lower.codeUnitAt(i - 1);
    final curr = lower.codeUnitAt(i);
    ascRun = (curr == prev + 1) ? ascRun + 1 : 1;
    descRun = (curr == prev - 1) ? descRun + 1 : 1;
    if (ascRun >= _minAlphabetRunLength || descRun >= _minAlphabetRunLength) {
      return true;
    }
  }
  return false;
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
