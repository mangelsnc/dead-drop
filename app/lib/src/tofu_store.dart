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
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks which sender fingerprints this device has seen before.
class TofuStore {
  static const _storageKey = 'deaddrop_tofu_known_senders';
  static const _storage = FlutterSecureStorage(
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(),
  );

  Set<String>? _cached;

  /// Check whether a sender fingerprint has been seen before.
  ///
  /// Returns `true` if the fingerprint is known (trusted from a previous
  /// session), `false` if this is the first time.
  Future<bool> isKnown(String fingerprint) async {
    final known = await _load();
    return known.contains(fingerprint);
  }

  /// Mark a sender fingerprint as known/trusted.
  ///
  /// Called after the user acknowledges the TOFU warning or after a
  /// successful transfer completes.
  Future<void> markKnown(String fingerprint) async {
    final known = await _load();
    known.add(fingerprint);
    await _save(known);
  }

  /// Remove all known sender fingerprints.
  Future<void> reset() async {
    await _storage.delete(key: _storageKey);
    _cached = null;
  }

  /// Number of known senders.
  Future<int> get count async => (await _load()).length;

  Future<Set<String>> _load() async {
    if (_cached != null) return _cached!;
    final stored = await _storage.read(key: _storageKey);
    if (stored == null) {
      _cached = <String>{};
      return _cached!;
    }
    try {
      final list = jsonDecode(stored) as List<dynamic>;
      _cached = list.cast<String>().toSet();
    } catch (_) {
      _cached = <String>{};
    }
    return _cached!;
  }

  Future<void> _save(Set<String> known) async {
    _cached = known;
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(known.toList()),
    );
  }
}
