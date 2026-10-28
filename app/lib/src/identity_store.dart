/// identity_store.dart — Persistent Ed25519 identity for DeadDrop.
///
/// The sender identity is a long-term Ed25519 keypair that authenticates
/// every transfer from this device. It is generated once on first run and
/// stored in the platform's secure storage (Keychain on iOS/macOS, Keystore
/// on Android, libsecret on Linux, Credential Manager on Windows).
///
/// The identity proves "this file came from the same DeadDrop installation"
/// — it does NOT prove who the user is (no personal information is attached).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium/sodium.dart';

import 'crypto.dart';

/// Loads, stores, and provides the device's persistent Ed25519 identity.
class IdentityStore {
  static const _unscopedStorageKey = 'deaddrop_identity_ed25519';
  static const _storage = FlutterSecureStorage(
    // On Linux, use libsecret (available on all desktop distros).
    lOptions: LinuxOptions(),
    // On macOS, use the system Keychain.
    //
    // usesDataProtectionKeychain is off because it requires entitlements
    // that only a build signed with a real Apple Developer identity can
    // carry. DeadDrop ships an ad-hoc-signed .app, so with the default
    // (true) every keychain call fails and the device identity never
    // loads — which is exactly how it failed on macOS 0.5.4.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  final Sodium _sodium;
  final String _storageKey;
  Identity? _cached;

  /// [environmentSlot] scopes the identity to a vault environment (real or
  /// decoy) so each one gets its own signing identity and cannot be
  /// correlated with the others. Leaving it `null` is the no-vault case and
  /// keeps the original, unsuffixed storage key byte-for-byte — there are no
  /// vaults in the wild yet, so existing installs must see no behaviour
  /// change at all.
  IdentityStore(this._sodium, {int? environmentSlot})
      : _storageKey = environmentSlot == null
            ? _unscopedStorageKey
            : '${_unscopedStorageKey}_env$environmentSlot';

  /// Load the persisted identity, or generate and persist a new one on
  /// first run.
  ///
  /// Subsequent calls return the cached instance.
  Future<Identity> loadOrGenerate() async {
    if (_cached != null) return _cached!;

    final stored = await _storage.read(key: _storageKey);
    if (stored != null) {
      try {
        final bytes = base64Decode(stored);
        _cached = Identity.fromSecretKeyBytes(_sodium, bytes);
        return _cached!;
      } catch (_) {
        // Corrupted stored identity — regenerate below.
      }
    }

    // First run or corrupted data: generate a fresh identity.
    final identity = await Identity.generate(_sodium);
    await _persist(identity);
    _cached = identity;
    return identity;
  }

  /// The identity's public key fingerprint (first 16 hex chars).
  ///
  /// Suitable for display in the UI for out-of-band verification.
  Future<String> fingerprint() async {
    final identity = await loadOrGenerate();
    return identity.fingerprint;
  }

  /// The identity's full Ed25519 public key.
  Future<Uint8List> verifyKey() async {
    final identity = await loadOrGenerate();
    return identity.verifyKey;
  }

  /// Delete the stored identity. The next call to [loadOrGenerate] will
  /// create a fresh one. Use with caution — all previously sent files
  /// will appear to come from a different identity.
  Future<void> reset() async {
    await _storage.delete(key: _storageKey);
    _cached = null;
  }

  Future<void> _persist(Identity identity) async {
    final bytes = identity.secretKeyBytes;
    await _storage.write(key: _storageKey, value: base64Encode(bytes));
  }
}
