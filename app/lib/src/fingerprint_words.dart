/// fingerprint_words.dart — a fingerprint in words a person can say.
///
/// TOFU asks the user to check a sender's fingerprint through another
/// channel, which in practice means reading it to them and hearing it
/// read back. Sixteen hex characters is a poor thing to read aloud:
/// `6bcdd4fd124dfacd` has no rhythm, `b` and `d` are hard to tell apart
/// by ear, and two fingerprints differing in one place sound alike.
/// A check nobody performs is not a check.
///
/// The same bits rendered as three words from the EFF short list —
/// already bundled for passphrase generation, and curated for exactly
/// this: short, concrete, unambiguous to spell, no near-homophones.
///
/// This renders the fingerprint; it does not replace it. The hex stays
/// on screen, the words sit beside it, and what is verified is
/// unchanged. Like [fingerprintOf], both devices must produce the same
/// words for the same key or the comparison is worse than useless, so
/// the derivation lives here rather than at each screen.
library;

import 'utils.dart';
import 'vault/passphrase_wordlist.dart';

/// How many words a fingerprint renders as.
///
/// Three words from a 1296-word list carry about 31 bits, against the
/// fingerprint's 64. That is a deliberate reduction: the words are what
/// a person compares out loud, and a ten-word recital is one nobody
/// finishes. The full hex remains on screen for anyone who wants to
/// compare every bit, and the words are derived from all of it (see
/// the test that changes each character in turn), so two keys sounding
/// alike takes a deliberate search rather than bad luck.
const int kFingerprintWordCount = 3;

/// [fingerprint] rendered as [kFingerprintWordCount] words, or null when
/// it is not a whole fingerprint.
///
/// Nothing short of [fingerprintLength] renders: words derived from a
/// truncated fingerprint would be read aloud as though they stood for
/// the whole key, and sound exactly as convincing.
String? fingerprintWords(String fingerprint) {
  if (fingerprint.length < fingerprintLength) return null;

  // FNV-1a over the whole string, so every character reaches every
  // word: a rendering that read one slice per word would let two keys
  // agreeing on a slice read the same there, and a listener comparing
  // by ear would hear a partial match as a match.
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0xFFFFFFFFFFFFFFFF;
  for (final unit in fingerprint.codeUnits) {
    hash = (hash ^ unit) & mask;
    hash = (hash * prime) & mask;
  }

  final words = <String>[];
  for (var i = 0; i < kFingerprintWordCount; i++) {
    // Re-mix between words rather than slicing the one hash, for the
    // same reason: a changed character must be able to move any word,
    // not only the one its slice fell in.
    hash = (hash ^ (0x9e3779b97f4a7c15 + i)) & mask;
    hash = (hash * prime) & mask;
    final word = kPassphraseWordlist[(hash >>> 11) % kPassphraseWordlist.length];
    words.add('${word[0].toUpperCase()}${word.substring(1)}');
  }
  return words.join(' ');
}

/// The name to offer for a sender nobody has named, or null when the
/// fingerprint cannot be rendered.
///
/// The words, because they are what the two people just read to each
/// other: the name is then the thing that was actually agreed, rather
/// than a label invented afterwards. A sender accepted without one used
/// to appear as sixteen hex characters, which says nothing about who
/// sent the file.
///
/// A suggestion, never a requirement. Someone receiving under pressure
/// should not have to fill in a form to accept a file, and the name is
/// a local label rather than an authenticated claim — see TofuStore.
String? suggestedSenderName(String fingerprint) =>
    fingerprintWords(fingerprint);
