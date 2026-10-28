/// tofu_store.dart — Trust On First Use (TOFU) for sender identities.
///
/// When the receiver sees a sender's Ed25519 fingerprint for the first time,
/// a warning is shown: "New sender — verify fingerprint through another
/// channel". Once the user confirms (or the transfer completes), the
/// fingerprint is stored and subsequent transfers from the same sender
/// are recognized silently.
///
/// This is the same model used by SSH (`known_hosts`) and Signal
/// (safety numbers): trust is established out-of-band the first time,
/// then verified automatically.
///
/// A known sender may also carry a **name** the user gave it. A device's
/// Ed25519 identity is persistent (see IdentityStore), so the same sender
/// shows the same fingerprint on every transfer — which makes a name worth
/// storing and worth trusting. "From: Ana" is something a person can check
/// against their own memory; sixteen hex characters is not.
///
/// The name is a local label, not an authenticated claim. It is whatever
/// this user typed, visible only on this device (and only in the vault
/// environment it was recorded in). It says "this is the key I decided was
/// Ana's", never "this key belongs to Ana".
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks which sender fingerprints this device has seen before.
class TofuStore {
  static const _unscopedStorageKey = 'deaddrop_tofu_known_senders';
  static const _storage = FlutterSecureStorage(
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  final String _storageKey;

  /// fingerprint -> the name the user gave it, or null for a sender they
  /// accepted without naming.
  Map<String, String?>? _cached;

  /// [environmentSlot] scopes the known-senders list to a vault environment
  /// (real or decoy). Without scoping, opening the decoy would show the
  /// real environment's TOFU history — a populated sender list next to a
  /// still-empty decoy file list (or vice versa) is internally incoherent
  /// and a tell to an attacker. `null` is the no-vault case and keeps the
  /// original, unsuffixed storage key byte-for-byte — there are no vaults
  /// in the wild yet, so existing installs must see no behaviour change.
  TofuStore({int? environmentSlot})
      : _storageKey = environmentSlot == null
            ? _unscopedStorageKey
            : '${_unscopedStorageKey}_env$environmentSlot';

  /// Check whether a sender fingerprint has been seen before.
  ///
  /// Returns `true` if the fingerprint is known (trusted from a previous
  /// session), `false` if this is the first time.
  Future<bool> isKnown(String fingerprint) async {
    final known = await _load();
    return known.containsKey(fingerprint);
  }

  /// Mark a sender fingerprint as known/trusted, optionally under [name].
  ///
  /// Called after the user acknowledges the TOFU warning. Re-marking a
  /// sender already known without a name keeps the existing name rather
  /// than clearing it: accepting the same sender again must not silently
  /// erase a label the user chose.
  Future<void> markKnown(String fingerprint, {String? name}) async {
    final known = await _load();
    final cleaned = _clean(name);
    known[fingerprint] = cleaned ?? known[fingerprint];
    await _save(known);
  }

  /// The name the user gave [fingerprint], or null if unnamed or unknown.
  Future<String?> nameFor(String fingerprint) async =>
      (await _load())[fingerprint];

  /// Sets, changes or (with a null or blank [name]) removes a sender's name.
  ///
  /// Naming an unknown fingerprint also marks it known — the only way to
  /// reach this is from a sender the user has in front of them.
  Future<void> setName(String fingerprint, String? name) async {
    final known = await _load();
    known[fingerprint] = _clean(name);
    await _save(known);
  }

  /// Every known sender, as fingerprint -> name (null when unnamed).
  ///
  /// Ordered with named senders first, then by name, so the address book
  /// reads as a list of people rather than a list of hex.
  Future<Map<String, String?>> all() async {
    final known = await _load();
    final entries = known.entries.toList()
      ..sort((a, b) {
        if (a.value == null && b.value == null) return a.key.compareTo(b.key);
        if (a.value == null) return 1;
        if (b.value == null) return -1;
        return a.value!.toLowerCase().compareTo(b.value!.toLowerCase());
      });
    return Map.fromEntries(entries);
  }

  /// Forget a single sender. The next transfer from them is a first
  /// contact again, warning and all.
  Future<void> forget(String fingerprint) async {
    final known = await _load();
    known.remove(fingerprint);
    await _save(known);
  }

  /// Remove all known sender fingerprints.
  Future<void> reset() async {
    await _storage.delete(key: _storageKey);
    _cached = null;
  }

  /// Number of known senders.
  Future<int> get count async => (await _load()).length;

  /// Trims a user-supplied name and turns blank into null, so a name that
  /// is only whitespace is stored as "unnamed" rather than as a label that
  /// renders empty.
  static String? _clean(String? name) {
    final trimmed = name?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Reads the store, accepting both the current and the original format.
  ///
  /// The original format was a JSON array of fingerprints. Names need a
  /// map, so the current format is a JSON object of fingerprint -> name.
  /// An array found on disk is read as a set of unnamed senders and
  /// rewritten as an object on the next save: a user who already trusts
  /// senders must not be asked to re-approve them because the file layout
  /// changed. Both shapes are covered by tests.
  Future<Map<String, String?>> _load() async {
    if (_cached != null) return _cached!;

    final stored = await _storage.read(key: _storageKey);
    if (stored == null) {
      _cached = <String, String?>{};
      return _cached!;
    }

    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        _cached = {
          for (final e in decoded.entries)
            e.key as String: e.value is String ? e.value as String : null,
        };
      } else if (decoded is List) {
        // Original format: fingerprints with no names.
        _cached = {for (final f in decoded) f as String: null};
      } else {
        _cached = <String, String?>{};
      }
    } catch (_) {
      // Unreadable store. Treating it as empty means every sender looks
      // new and gets the first-contact warning again, which is the safe
      // direction to fail in: the alternative is trusting something we
      // could not parse.
      _cached = <String, String?>{};
    }
    return _cached!;
  }

  Future<void> _save(Map<String, String?> known) async {
    _cached = known;
    await _storage.write(key: _storageKey, value: jsonEncode(known));
  }
}
