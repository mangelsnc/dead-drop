/// attempt_guard.dart — rate limiting and optional self-destruct for vault
/// unlock attempts.
///
/// What this is NOT
/// ----------------
/// Rate limiting is **not** the vault's defence. It binds only an attacker
/// who works through this app. One who images the device and attacks the
/// copy offline never meets this counter at all — nothing here slows them
/// by a single guess. The real defence against that attacker is passphrase
/// entropy (see `passphrase_strength.dart`, `kMinimumEntropyBits`).
///
/// This matters because the two are easy to confuse. Nobody should ever
/// lower the entropy floor on the grounds that "the rate limiter covers
/// it" — the rate limiter covers a different attacker.
///
/// What it does do
/// ---------------
/// It makes repeated guessing through the UI tedious, and — when the user
/// has explicitly opted in — it can destroy the wrapped keys after enough
/// failures.
///
/// Three design points, each load-bearing:
///
/// 1. **The delay precedes the attempt; it never follows a failure.** A
///    pause after a wrong passphrase is itself observable: it tells an
///    attacker with a stopwatch that the app recognised the failure.
///    Waiting *before* an attempt leaks nothing, because the wait is
///    identical whatever the user is about to type — and identical whether
///    a second environment exists or not.
///
/// 2. **The counter is global, not per environment.** A per-environment
///    counter would reveal which environment an attacker was targeting,
///    and would let them reset their budget by alternating passphrases.
///
/// 3. **Its storage key exists whether or not a vault does.** If the key
///    only appeared once a vault was created, its presence would be the
///    artefact this whole design avoids. [AttemptGuard] therefore writes
///    the counter on success as well as on failure — the same discipline
///    the self-destruct preference follows in `settings_page.dart`.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_storage.dart';

/// Consecutive failures after which self-destruct fires, when the user has
/// enabled it. Follows technical-spec.md §4.8.
const int kSelfDestructThreshold = 10;

/// How many attempts are free before any delay is imposed.
///
/// A person mistyping a six-word passphrase will plausibly do it two or
/// three times; making them wait for that would punish the honest case to
/// no benefit, since an attacker's cost is dominated by the later, longer
/// delays.
const int kFreeAttempts = 3;

/// The delay added per failed attempt beyond [kFreeAttempts], capped by
/// [kMaxPenalty]. Linear rather than exponential: by the self-destruct
/// threshold an exponential curve would reach hours, which punishes a
/// locked-out owner far more than it inconveniences an attacker who can
/// simply walk away and come back.
const Duration kPenaltyStep = Duration(seconds: 5);

/// Ceiling on the per-attempt delay.
const Duration kMaxPenalty = Duration(seconds: 60);

/// Storage key for the failure counter.
///
/// Deliberately written on success as well as failure so the key's mere
/// presence reveals nothing — see this library's doc comment.
const String kAttemptCounterStorageKey = 'deaddrop_unlock_failures';

/// Storage key for the self-destruct preference.
///
/// Shared with `settings_page.dart`, which writes it. Defined here because
/// this is the module that enforces it; a second key would let the setting
/// and the enforcement drift apart.
const String kSelfDestructStorageKey = 'deaddrop_self_destruct_enabled';

/// Whether this binary reaches self-destruct in three attempts with no
/// delays, so its owner can watch it fire.
///
/// Off unless built with `--dart-define=DEADDROP_SELF_DESTRUCT_REHEARSAL=true`,
/// and `const`, so an ordinary build resolves it to a compile-time
/// `false` and the production constants below are the only ones left in
/// the tree. Nothing to remember to take out before a release, which
/// matters more here than for the other diagnostic flags: a release that
/// erased a vault on the third mistyped passphrase would destroy the
/// files of exactly the person the feature exists to protect.
/// vault/self_destruct_rehearsal_test.dart fails if a build is about to
/// ship with it on.
///
/// ## Why it exists
///
/// Self-destruct cannot be checked by hand in a sitting. Ten failures,
/// and the penalties before them add up to two minutes and twenty
/// seconds of real waiting — so an owner asked to trust it with
/// something irreplaceable has never seen it work. A build that reaches
/// it in three attempts is the only honest way to answer "does this
/// actually fire?".
///
/// It changes when the wipe happens, never what it does: the counting,
/// the preference check and the destruction of every slot are the
/// production paths, unchanged.
const bool selfDestructRehearsal =
    bool.fromEnvironment('DEADDROP_SELF_DESTRUCT_REHEARSAL');

/// Failures after which self-destruct fires in this build.
const int selfDestructThreshold =
    selfDestructRehearsal ? 3 : kSelfDestructThreshold;

/// Attempts allowed before any delay in this build.
///
/// One in a rehearsal, not zero. With no free attempt the penalty is
/// always zero, the wait message never appears, and the rehearsal
/// exercises a sequence that cannot happen in production — where the
/// delays always precede the threshold. One free attempt puts a real
/// wait between the second failure and the third, which is the one
/// that fires.
const int freeAttempts = selfDestructRehearsal ? 1 : kFreeAttempts;

/// The delay added per failed attempt in this build.
///
/// Kept, shortened. The wait is part of what an owner is rehearsing:
/// a pause arriving before the attempt that destroys the vault is
/// exactly the moment they need to recognise.
const Duration penaltyStep = selfDestructRehearsal
    ? Duration(seconds: 3)
    : kPenaltyStep;

/// [penaltyStep] under another name, so the constructor's parameter of
/// that name does not shadow it in the initialiser list.
const Duration _buildPenaltyStep = penaltyStep;

const FlutterSecureStorage _defaultStorage = kSecureStorage;

/// Tracks consecutive failed unlock attempts and, if the user opted in,
/// triggers self-destruct once [kSelfDestructThreshold] is reached.
class AttemptGuard {
  /// [storage] is injectable so tests can supply an in-memory backend;
  /// production uses the platform keychain.
  ///
  /// [penaltyStep] exists so a test that must cross [kSelfDestructThreshold]
  /// can do so without serving the real delays — eleven attempts at the
  /// production curve is nearly four minutes of genuine waiting. Overriding
  /// it changes only how long the caller waits, never whether self-destruct
  /// fires, so a test that sets it to zero still exercises the real
  /// counting and wipe logic.
  AttemptGuard({
    FlutterSecureStorage? storage,
    Duration? penaltyStep,
  })  : _storage = storage ?? _defaultStorage,
        _penaltyStep = penaltyStep ?? _buildPenaltyStep;

  final FlutterSecureStorage _storage;
  final Duration _penaltyStep;

  /// How long the caller must wait before the next attempt is allowed.
  ///
  /// Call this *before* attempting an unlock and wait for the returned
  /// duration. Returns [Duration.zero] for the first [kFreeAttempts].
  Future<Duration> penaltyBeforeNextAttempt() async {
    final failures = await failureCount();
    if (failures < freeAttempts) return Duration.zero;

    final steps = failures - freeAttempts + 1;
    final penalty = _penaltyStep * steps;
    return penalty > kMaxPenalty ? kMaxPenalty : penalty;
  }

  /// Current consecutive-failure count. Zero when never set.
  ///
  /// Returns zero when the keychain cannot be reached at all. That is the
  /// deliberate choice: rate limiting is a convenience layer, not the
  /// vault's defence (see this library's doc comment), so a platform
  /// without secure storage must still be able to open its vault. Failing
  /// closed here would lock a user out of their own files to enforce a
  /// limit that never bound a serious attacker in the first place.
  Future<int> failureCount() async {
    try {
      final raw = await _storage.read(key: kAttemptCounterStorageKey);
      if (raw == null) return 0;
      return int.tryParse(raw) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Record a failed unlock attempt.
  ///
  /// Returns `true` when this failure reached [kSelfDestructThreshold] *and*
  /// the user enabled self-destruct, meaning the caller must now destroy
  /// every slot. Returns `false` otherwise — including when the threshold
  /// is reached with self-destruct off, which by design does nothing.
  Future<bool> recordFailure() async {
    final failures = await failureCount() + 1;
    try {
      await _storage.write(
        key: kAttemptCounterStorageKey,
        value: failures.toString(),
      );
    } catch (_) {
      // Unreachable keychain: see [failureCount].
    }
    if (failures < selfDestructThreshold) return false;
    return _selfDestructEnabled();
  }

  /// Record a successful unlock, clearing the counter.
  ///
  /// Writes `'0'` rather than deleting the key: a key that vanishes on
  /// success and reappears on failure would itself signal unlock activity
  /// to anyone inspecting the keychain.
  Future<void> recordSuccess() async {
    try {
      await _storage.write(key: kAttemptCounterStorageKey, value: '0');
    } catch (_) {
      // Unreachable keychain: see [failureCount].
    }
  }

  /// Forgets everything this guard holds: the failure counter and the
  /// self-destruct preference.
  ///
  /// Called when the vault itself is erased. Leaving the preference behind
  /// would mean a vault created later silently inherits self-destruct from
  /// one its owner deleted — a destructive setting nobody turned on for it.
  /// Writes rather than deletes, for the reason [recordSuccess] gives.
  Future<void> reset() async {
    try {
      await _storage.write(key: kAttemptCounterStorageKey, value: '0');
      await _storage.write(key: kSelfDestructStorageKey, value: 'false');
    } catch (_) {
      // Unreachable keychain: see [failureCount].
    }
  }

  Future<bool> _selfDestructEnabled() async {
    try {
      final raw = await _storage.read(key: kSelfDestructStorageKey);
      return raw == 'true';
    } catch (_) {
      // Unreadable preference is treated as off — self-destruct is
      // destructive and opt-in, so an uncertain answer must never fire it.
      return false;
    }
  }
}
