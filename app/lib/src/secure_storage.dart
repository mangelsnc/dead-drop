/// secure_storage.dart — One configuration for every keychain call.
///
/// Four call sites each carried their own copy of these options, and one of
/// them had already drifted: the settings page omitted
/// `usesDataProtectionKeychain: false`, the flag the other three carry
/// precisely because leaving it at its default broke every keychain call on
/// macOS in 0.5.4.
///
/// What the user is shown also comes from here. macOS names the keychain
/// service in its permission dialog, and the plugin's default is
/// `flutter_secure_storage_service`, so the prompt read "DeadDrop wants to
/// use confidential information stored in flutter_secure_storage_service in
/// your keychain". Someone who did not install a library by that name has no
/// way to judge whether that is their app asking.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The keychain service every DeadDrop secret is stored under, and the name
/// macOS shows the user when it asks permission.
///
/// Changing this string moves where secrets live: the device identity stored
/// under the old name is not found under the new one, so the device
/// generates a fresh identity and every correspondent who verified its
/// fingerprint sees a stranger. Treat it as a storage migration, not a
/// label.
const String kKeychainService = 'DeadDrop device identity';

/// The configuration every call site uses.
///
/// `usesDataProtectionKeychain` is off because it needs entitlements only a
/// build signed with a real Apple Developer identity can carry. DeadDrop
/// ships an ad-hoc-signed .app, so with the default (true) every keychain
/// call fails and the device identity never loads.
const FlutterSecureStorage kSecureStorage = FlutterSecureStorage(
  // Linux: libsecret, present on every desktop distribution.
  lOptions: LinuxOptions(),
  mOptions: MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: kKeychainService,
  ),
  iOptions: IOSOptions(accountName: kKeychainService),
);
