/// Does every keychain call use one configuration, and does the dialog
/// macOS shows name this app?
///
/// Two failures, both already real:
///
/// The settings page configured its own `FlutterSecureStorage` and omitted
/// `usesDataProtectionKeychain: false`. The other three call sites carry
/// that flag because leaving it at its default made every keychain call
/// fail on macOS in 0.5.4 — an ad-hoc-signed .app cannot carry the
/// entitlement the data protection keychain needs. A fourth copy drifting
/// is what copies do.
///
/// And the prompt read "DeadDrop wants to use confidential information
/// stored in flutter_secure_storage_service in your keychain", because
/// that is the plugin's default service name. A non-technical person
/// cannot tell whether a library name they never installed is their app
/// asking or something else.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/secure_storage.dart';

/// The `kSecureStorage` declaration, with comments stripped.
///
/// The checks below have to read the code and not the prose around it:
/// a comment naming a flag is exactly what this file exists to stop
/// standing in for the flag.
String _storageOptions() {
  final source = File('lib/src/secure_storage.dart').readAsStringSync();
  final start = source.indexOf('const FlutterSecureStorage kSecureStorage');
  expect(start, greaterThan(-1), reason: 'kSecureStorage was renamed');
  final end = source.indexOf('\n);', start);
  expect(end, greaterThan(start), reason: 'the declaration did not close');

  return source
      .substring(start, end)
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

/// Just the `MacOsOptions(...)` arguments, so a flag deleted from them
/// cannot be satisfied by the same words appearing elsewhere.
String _macOsOptions() {
  final options = _storageOptions();
  final start = options.indexOf('mOptions: MacOsOptions(');
  expect(start, greaterThan(-1), reason: 'MacOsOptions is no longer set');
  final end = options.indexOf('),', start);
  expect(end, greaterThan(start));
  return options.substring(start, end);
}

/// Every library file, so a new call site cannot be added without this
/// test seeing it.
List<File> _libraryFiles() {
  final dir = Directory('lib');
  expect(dir.existsSync(), isTrue, reason: 'run from app/');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('the dialog names this app, not the plugin', () {
    test('the service is not the plugin default', () {
      // The string this replaced. Pinned as a literal so that reverting to
      // the default fails here rather than quietly going back.
      //
      // Two things ride on this, and the second is why it is a security
      // test and not a cosmetic one. The prompt named a library instead of
      // the app, which nobody can act on. And the default is the service
      // EVERY Flutter app using this plugin shares, so the device identity
      // — the Ed25519 secret key correspondents verify this device by —
      // was stored under a name any other such app on the machine also
      // reaches for.
      expect(kKeychainService, isNot('flutter_secure_storage_service'));
    });

    test('the service names DeadDrop', () {
      // macOS drops this straight into "… stored in <service> in your
      // keychain", so it is read by a person, not just matched by code.
      expect(kKeychainService, contains('DeadDrop'));
    });

    test('macOS and iOS are told the same service', () {
      // Different services on the two Apple platforms would store the
      // identity in two places, and the device would present a different
      // fingerprint depending on which one it read.
      final source = File('lib/src/secure_storage.dart').readAsStringSync();
      expect('accountName: kKeychainService'.allMatches(source).length, 2,
          reason: 'both MacOsOptions and IOSOptions set it from the same '
              'constant');
    });
  });

  group('one configuration, not four copies', () {
    test('no library file builds its own FlutterSecureStorage', () {
      final offenders = <String>[];
      for (final file in _libraryFiles()) {
        if (file.path.endsWith('secure_storage.dart')) continue;
        if (file.readAsStringSync().contains('FlutterSecureStorage(')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'these construct their own storage instead of using '
              'kSecureStorage, which is how the settings page ended up '
              'without usesDataProtectionKeychain: false');
    });

    test('the shared configuration keeps the flag that 0.5.4 needed', () {
      // Checked against the options block, not the file: this test first
      // searched the whole source, and the mutation that deleted the flag
      // from MacOsOptions passed, because the two comments above still
      // said the words. A grep proves which words appear, never that
      // they are true of the code.
      expect(_macOsOptions(), contains('usesDataProtectionKeychain: false'),
          reason: 'with the default (true) an ad-hoc-signed .app fails '
              'every keychain call and the device identity never loads');
    });

    test('Linux still gets libsecret', () {
      // The eliminatory platform. Dropping lOptions while tidying would
      // not show up on the machine this is usually edited from.
      expect(_storageOptions(), contains('lOptions: LinuxOptions()'));
    });
  });

  test('changing the service name is flagged as a migration', () {
    // Whoever edits kKeychainService next needs to know that it moves
    // where the identity lives: the old one is not found under the new
    // name, the device generates a fresh identity, and everyone who
    // verified its fingerprint sees a stranger.
    final source = File('lib/src/secure_storage.dart').readAsStringSync();
    final doc = source.substring(0, source.indexOf('const String kKeychainService'));

    expect(doc.toLowerCase(), contains('fingerprint'),
        reason: 'the consequence has to be stated where the constant is, '
            'not left for someone to rediscover');
  });
}
