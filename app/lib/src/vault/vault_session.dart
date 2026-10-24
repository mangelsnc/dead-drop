/// vault_session.dart — unlocking a vault without revealing which
/// environment (if any) a passphrase opened.
///
/// A vault holds [kVaultEnvironmentSlots] environment slots: one real, one
/// decoy. Both are unlocked by typing a passphrase; which environment (or
/// none) that passphrase opens must never be observable from the outside.
/// Concretely, that means every call to [tryUnlock] performs exactly the
/// same amount of Argon2id work — one derivation per slot, always — whether
/// the passphrase is the real one, the decoy one, wrong, or a slot is empty.
/// Argon2id is the dominant cost in this function by design (see
/// pwhash.dart), so equalising derivation *count* is what equalises
/// wall-clock cost. A user under coercion must be able to type the decoy
/// passphrase without an attacker learning anything from timing.
library;

import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'pwhash.dart';
import 'vault_keys.dart' as vault_keys;
import 'vault_keys.dart' show WrappedKey;

/// Number of environment slots a vault has: one real, one decoy.
///
/// Fixed by the design — the coercion-resistance property only needs two
/// environments — and [tryUnlock] always processes exactly this many slots,
/// filled or not.
const int kVaultEnvironmentSlots = 2;

/// Outcome of a [tryUnlock] attempt.
///
/// [slotIndex] and [dataKey] are both null together (no match) or both
/// non-null together (a match). [ok] is a readability helper over that
/// invariant.
class UnlockResult {
  UnlockResult({this.slotIndex, this.dataKey});

  /// Index of the slot the passphrase unlocked, or null if none matched.
  final int? slotIndex;

  /// The recovered data key, or null if no slot matched.
  final Uint8List? dataKey;

  /// Whether the passphrase matched a slot.
  bool get ok => dataKey != null;
}

/// Signature of [unwrapDataKey], extracted so tests can substitute a
/// counting wrapper to verify the constant-derivation-count property
/// exactly, without relying on noisy wall-clock timing.
typedef UnwrapDataKey = Uint8List? Function(
  SodiumSumo sodium,
  String passphrase,
  WrappedKey wrapped,
);

/// A fixed, never-matching [WrappedKey] substituted for empty slots.
///
/// Its salt, nonce and ciphertext are generated once from real randomness
/// (not all-zero bytes, which could be special-cased by an implementation
/// or look suspicious under inspection) so that deriving against an empty
/// slot costs exactly what deriving against a filled one costs. The
/// ciphertext is sized to a real secretbox's minimum (MAC length, 32 bytes
/// of data-key-sized "plaintext" plus the MAC) purely so
/// `secretBox.openEasy` has a well-formed buffer to reject; being random,
/// it never authenticates, so the failure it produces is indistinguishable
/// from a wrong passphrase on a real slot.
WrappedKey? _dummySlot;

WrappedKey _dummySlotFor(SodiumSumo sodium) {
  // 32 bytes matches the real data key size (see vault_keys.dart); the
  // exact size doesn't matter for cost (secretBox.openEasy's MAC check
  // dominates regardless of plaintext length), but matching it keeps the
  // dummy ciphertext indistinguishable in shape from a real one.
  const dummyPlaintextBytes = 32;
  return _dummySlot ??= WrappedKey(
    salt: newSalt(sodium),
    nonce: sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes),
    ciphertext: sodium.randombytes
        .buf(dummyPlaintextBytes + sodium.crypto.secretBox.macBytes),
  );
}

/// Attempts to unlock a vault with [passphrase] against [slots].
///
/// [slots] has exactly [kVaultEnvironmentSlots] entries; a null entry means
/// that environment has not been provisioned (e.g. no decoy configured).
/// Every slot — empty or filled, matching or not — is derived against
/// exactly once, and the loop never returns early: short-circuiting the
/// moment a match is found would make the real passphrase measurably
/// cheaper than the decoy one, which is the exact tell this function exists
/// to prevent. The first match (there should be at most one) is returned
/// only after all slots have been processed.
///
/// [unwrapDataKey] is exposed as a parameter purely so tests can inject a
/// counting wrapper and assert the derivation count directly, rather than
/// measuring wall time (noisy, especially in CI). Production callers should
/// never pass it.
UnlockResult tryUnlock(
  SodiumSumo sodium,
  String passphrase,
  List<WrappedKey?> slots, {
  UnwrapDataKey unwrapDataKey = vault_keys.unwrapDataKey,
}) {
  assert(slots.length == kVaultEnvironmentSlots);

  int? matchedSlot;
  Uint8List? matchedKey;

  for (var i = 0; i < kVaultEnvironmentSlots; i++) {
    final slot = slots[i] ?? _dummySlotFor(sodium);
    final result = unwrapDataKey(sodium, passphrase, slot);

    // Do not return here: every slot must be derived against regardless of
    // whether this one matched, so the loop's total cost never depends on
    // where (or whether) the match occurred.
    if (result != null && matchedKey == null) {
      matchedSlot = i;
      matchedKey = result;
    }
  }

  return UnlockResult(slotIndex: matchedSlot, dataKey: matchedKey);
}
