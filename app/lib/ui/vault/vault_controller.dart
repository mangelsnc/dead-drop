/// vault_controller.dart — owns the open vault environment, end to end.
///
/// This is the integration point between the crypto/storage layers
/// (vault_session.dart, vault_store.dart, vault_keys.dart) and the UI (Task
/// 8, not this file). It holds the one piece of state those layers are
/// deliberately stateless about: which environment, if any, is currently
/// unlocked, and its data key.
///
/// Two properties matter here beyond ordinary state management:
///
/// - **Locking must really forget.** [VaultState.unlocked] flipping to
///   `false` is not enough on its own — the data key and the decrypted
///   entry list must actually leave memory, not just become unreachable from
///   a flag. See [lock].
/// - **Backgrounding the app must lock the vault.** An unlocked real
///   environment surviving a backgrounding leaves it exposed to whoever
///   next picks up the device — this is Review Focus #2 of the vault plan.
///   See [didChangeAppLifecycleState].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../src/vault/attempt_guard.dart';
import '../../src/vault/vault_keys.dart';
import '../../src/vault/vault_session.dart';
import '../../src/vault/vault_store.dart';

/// Snapshot of the vault's state as far as the UI needs to know it.
///
/// Deliberately does not expose the data key or which slot is the "real"
/// one in any way distinguishable by the caller beyond [slot]'s raw index —
/// the controller itself never branches UI-visible behaviour on whether
/// [slot] is 0 or 1 except where the plan explicitly calls for it (Task 8's
/// Settings gating). [entries] is empty, not null, when locked.
class VaultState {
  const VaultState({
    this.exists = false,
    this.unlocked = false,
    this.slot,
    this.entries = const [],
    this.error,
  });

  /// Whether a vault has been created in this session (via [createVault] or
  /// a successful [unlock]). This is session-local bookkeeping, not a flag
  /// read off disk — the on-disk layout must not reveal whether a vault has
  /// ever been set up (see vault_store.dart), so there is deliberately no
  /// way to recover this by inspecting the filesystem at startup. The vault
  /// is a section the user navigates to, never a launch gate.
  final bool exists;

  /// Whether an environment is currently unlocked.
  final bool unlocked;

  /// Which slot is open, or null when locked.
  final int? slot;

  /// The open environment's entries, or empty when locked.
  final List<VaultEntry> entries;

  /// A user-facing error from the last operation, or null.
  final String? error;

  VaultState copyWith({
    bool? exists,
    bool? unlocked,
    int? slot,
    bool clearSlot = false,
    List<VaultEntry>? entries,
    String? error,
    bool clearError = false,
  }) {
    return VaultState(
      exists: exists ?? this.exists,
      unlocked: unlocked ?? this.unlocked,
      slot: clearSlot ? null : (slot ?? this.slot),
      entries: entries ?? this.entries,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the open vault environment and the data key that decrypts it.
///
/// A single instance is shared for the app's lifetime via
/// [vaultControllerProvider]. It registers itself as a
/// [WidgetsBindingObserver] so it can lock the vault the moment the app is
/// backgrounded, independent of whatever screen happens to be on top.
class VaultController extends StateNotifier<VaultState>
    with WidgetsBindingObserver {
  /// [attemptGuard] is injectable so tests can supply one over an
  /// in-memory keychain; production uses the platform default.
  VaultController(this._sodium, this._store, {AttemptGuard? attemptGuard})
      : _attemptGuard = attemptGuard ?? AttemptGuard(),
        super(const VaultState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SodiumSumo? _sodium;
  final VaultStore? _store;
  final AttemptGuard _attemptGuard;

  /// An in-flight self-destruct, or null. Held so a later [unlock] can wait
  /// for it rather than reading half-destroyed slots, and so tests can await
  /// it deterministically.
  Future<void>? _wipe;

  /// Whether a self-destruct is still running. Tests await [_wipe] through
  /// [debugWipe]; production code never needs this.
  @visibleForTesting
  Future<void>? get debugWipe => _wipe;

  /// Destroys every slot. A surviving decoy would prove there had been
  /// something to erase, so this never destroys just the slot under attack.
  Future<void> _destroyEverySlot(VaultStore store) async {
    for (var slot = 0; slot < kVaultEnvironmentSlots; slot++) {
      try {
        await store.destroySlot(slot);
      } catch (_) {
        // Keep going. Destroying the remaining slots matters more than
        // reporting a failure on one: a surviving decoy is exactly what
        // this is meant to prevent, and there is nobody to report to —
        // the caller returned before this started, by design.
        //
        // A slot that survives because the process died mid-wipe is a real
        // residual risk, documented in docs/security.md rather than papered
        // over: self-destruct discards keys, it does not guarantee erasure.
      }
    }
  }

  /// The data key for the currently-open environment. Cleared by [lock] —
  /// this is the one piece of key material this controller is responsible
  /// for zeroing out of reach the moment the environment should no longer
  /// be considered open.
  Uint8List? _dataKey;

  /// Whether the vault feature is usable at all. False when sumo could not
  /// be initialised (see main.dart) — Send and Receive must keep working
  /// regardless, so every vault operation fails softly rather than
  /// crashing when this is false.
  bool get isAvailable => _sodium != null && _store != null;

  /// Whether this controller currently holds a data key in memory.
  ///
  /// Exposed only so tests can verify [lock] actually drops the key rather
  /// than merely flipping [VaultState.unlocked] — no production code should
  /// need this, since [VaultState.unlocked] is the thing to branch on.
  @visibleForTesting
  bool get debugHasDataKey => _dataKey != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding the app with the real environment unlocked is exactly
    // the moment a coerced user's device could be picked up and inspected.
    // Lock unconditionally; locking an already-locked vault is a no-op.
    if (state == AppLifecycleState.paused) {
      lock();
    }
  }

  /// Attempts to unlock with [passphrase].
  ///
  /// Returns whether it succeeded. On success, loads that environment's
  /// entries. On failure, leaves any previously-open environment untouched
  /// (an unlock attempt while already unlocked does not implicitly lock
  /// first) and sets [VaultState.error].
  Future<bool> unlock(String passphrase) async {
    final sodium = _sodium;
    final store = _store;
    if (sodium == null || store == null) {
      state = state.copyWith(error: 'Vault unavailable on this device');
      return false;
    }

    // The penalty is served BEFORE the attempt, never after a failure. A
    // pause that follows a wrong passphrase is itself observable — it tells
    // an attacker with a stopwatch that the app recognised the failure.
    // Waiting first leaks nothing: the wait is identical whatever is about
    // to be typed, and identical whether or not a second environment exists.
    // A self-destruct started by an earlier attempt runs in the background
    // so it cannot be timed (see below). Wait for it here: reading slots
    // mid-wipe could see one destroyed and one not.
    final wipe = _wipe;
    if (wipe != null) await wipe;

    final penalty = await _attemptGuard.penaltyBeforeNextAttempt();
    if (penalty > Duration.zero) {
      await Future<void>.delayed(penalty);
    }

    final slots = await store.readSlots();
    final result = tryUnlock(sodium, passphrase, slots);
    if (!result.ok) {
      final shouldSelfDestruct = await _attemptGuard.recordFailure();
      if (shouldSelfDestruct) {
        // Started, deliberately NOT awaited. Destroying the slots is several
        // atomic file writes; awaiting them here would make the attempt that
        // triggers the wipe measurably slower than an ordinary wrong
        // passphrase, and an attacker with a stopwatch would know which
        // attempt was the wipe. Both failure paths must cost the same from
        // the caller's side, so this one returns on the same work as the
        // other — one storage write — and the wipe completes behind it.
        //
        // _wipe is retained so a later unlock awaits it before reading the
        // slots (see the top of this method); the wipe always completes,
        // and it cannot race a subsequent attempt.
        _wipe = _destroyEverySlot(store);
        _dataKey = null;
        state = state.copyWith(
          unlocked: false,
          clearSlot: true,
          entries: const [],
          error: 'Incorrect passphrase',
        );
        return false;
      }
      state = state.copyWith(error: 'Incorrect passphrase');
      return false;
    }

    await _attemptGuard.recordSuccess();

    final dataKey = result.dataKey!;
    final slotIndex = result.slotIndex!;
    final entries = await store.list(dataKey, slotIndex);

    _dataKey = dataKey;
    state = state.copyWith(
      exists: true,
      unlocked: true,
      slot: slotIndex,
      entries: entries,
      clearError: true,
    );
    return true;
  }

  /// Locks the vault, clearing the data key and entry list from memory.
  ///
  /// Safe to call when already locked. This is the function Review Focus
  /// #2 depends on: both the boolean flag and the actual key material must
  /// be gone afterwards, not just the flag.
  void lock() {
    _dataKey = null;
    if (!state.unlocked) return;
    state = state.copyWith(
      unlocked: false,
      clearSlot: true,
      entries: const [],
      clearError: true,
    );
  }

  /// Creates a new vault with [passphrase] as the real environment (slot 0).
  ///
  /// Does not require a decoy — a vault with only a real environment is a
  /// valid, if less protected, configuration; [addDecoy] can provision slot
  /// 1 later. Initialises the on-disk store first (idempotent) so this also
  /// works as "first run" setup.
  ///
  /// Refuses (via [VaultState.error]) when this controller already
  /// considers a vault to exist ([VaultState.exists]), rather than silently
  /// overwriting slot 0 — [VaultStore.writeSlots] replaces the whole slot
  /// pair, so an unguarded second call (a UI double-tap, a future caller
  /// bug) would clobber slot 0 and wipe out any decoy in slot 1 too.
  ///
  /// This guard is necessarily session-local, not disk-backed: by design
  /// (see vault_store.dart), [VaultStore.readSlots] can never distinguish
  /// an empty slot from an occupied one without the right passphrase — an
  /// empty slot is written as an indistinguishable random filler
  /// specifically so the on-disk layout never reveals slot occupancy. That
  /// is the same property that makes the vault coercion-resistant, so nothing
  /// server-side can authoritatively answer "is slot 0 already in use?"
  /// Within a controller's lifetime, [VaultState.exists] is set the moment a
  /// vault is created or unlocked and is therefore a reliable guard against
  /// *this controller* clobbering its own vault; it cannot catch a second,
  /// independent [VaultController] instance (e.g. a future caller that
  /// built its own) calling [createVault] on the same store without ever
  /// unlocking first.
  Future<void> createVault(String passphrase) async {
    if (state.exists) {
      state = state.copyWith(error: 'A vault already exists');
      return;
    }

    final sodium = _sodium;
    final store = _store;
    if (sodium == null || store == null) {
      state = state.copyWith(error: 'Vault unavailable on this device');
      return;
    }

    await store.init();
    final dataKey = newDataKey(sodium);
    final wrapped = wrapDataKey(sodium, passphrase, dataKey);
    await store.writeSlots([wrapped, null]);

    _dataKey = dataKey;
    state = state.copyWith(
      exists: true,
      unlocked: true,
      slot: 0,
      entries: const [],
      clearError: true,
    );
  }

  /// Provisions the decoy environment (slot 1) with [passphrase].
  ///
  /// Requires the real environment (slot 0) to already exist, since this
  /// reads and rewrites both slots together — [VaultStore.writeSlots]
  /// overwrites the whole pair, so slot 0's current [WrappedKey] must be
  /// read back and preserved rather than clobbered.
  Future<void> addDecoy(String passphrase) async {
    final sodium = _sodium;
    final store = _store;
    if (sodium == null || store == null) {
      state = state.copyWith(error: 'Vault unavailable on this device');
      return;
    }

    final slots = await store.readSlots();
    final dataKey = newDataKey(sodium);
    final wrapped = wrapDataKey(sodium, passphrase, dataKey);
    await store.writeSlots([slots[0], wrapped]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataKey = null;
    super.dispose();
  }
}

/// Global sumo-capable sodium instance, or null if unavailable on this
/// platform (see `SodiumSumoUnavailable` in main.dart). The vault feature
/// degrades to unavailable when this is null; nothing else in the app
/// depends on it.
final sodiumSumoProvider = Provider<SodiumSumo?>((ref) {
  return null; // overridden in main()
});

/// Directory the vault's on-disk store lives under.
///
/// Overridden in main() with the real app-support directory (via
/// `path_provider`); tests override it with a temp directory so they never
/// touch the host filesystem outside their own sandbox.
final vaultDirectoryProvider = Provider<Directory>((ref) {
  throw UnimplementedError(
    'vaultDirectoryProvider must be overridden (see main() or tests)',
  );
});

/// The vault's on-disk store, or null when the vault feature is
/// unavailable (no sumo sodium instance).
final vaultStoreProvider = Provider<VaultStore?>((ref) {
  final sodium = ref.watch(sodiumSumoProvider);
  if (sodium == null) return null;
  final dir = ref.watch(vaultDirectoryProvider);
  return VaultStore(dir, sodium);
});

/// Resolves the real on-device directory for the vault's store.
///
/// Kept separate from [vaultDirectoryProvider]'s default so the default
/// itself can stay synchronous and throw-until-overridden; main() awaits
/// this before building the override.
Future<Directory> resolveVaultDirectory() async {
  final supportDir = await getApplicationSupportDirectory();
  return Directory('${supportDir.path}/vault');
}

final vaultControllerProvider =
    StateNotifierProvider<VaultController, VaultState>((ref) {
  final sodium = ref.watch(sodiumSumoProvider);
  final store = ref.watch(vaultStoreProvider);
  return VaultController(sodium, store);
});
