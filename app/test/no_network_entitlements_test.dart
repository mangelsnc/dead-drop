/// No build of DeadDrop asks for network access.
///
/// The project's whole argument is that it moves data between two
/// devices and reaches nothing else: the Android manifest removes
/// INTERNET, ACCESS_NETWORK_STATE and RECORD_AUDIO with
/// `tools:node="remove"` so that a reviewer who unzips the APK finds
/// the opposite of a network app.
///
/// macOS said otherwise. `DebugProfile.entitlements` carried
/// `com.apple.security.network.server`, which authorises the app to
/// listen for incoming connections. Flutter's template puts it there so
/// the debugger can attach, and Release never had it — but a reviewer
/// unzipping a debug build finds a privacy tool asking to open a port,
/// and the explanation is one they have no reason to take on trust.
///
/// Checked for every entitlements file there is, because the next one
/// added from a template will carry the same default.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Entitlements that would let the app reach or be reached over a
/// network. None of these belongs in any DeadDrop build.
const _networkEntitlements = [
  'com.apple.security.network.server',
  'com.apple.security.network.client',
];

void main() {
  test('no entitlements file asks for network access', () {
    final files = [
      ...Directory('macos').listSync(recursive: true),
      if (Directory('ios').existsSync())
        ...Directory('ios').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.entitlements'));

    expect(files, isNotEmpty,
        reason: 'the entitlements files moved; this test now checks '
            'nothing');

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final entitlement in _networkEntitlements) {
        expect(source, isNot(contains(entitlement)),
            reason: '${file.path} grants $entitlement, in an app whose '
                'argument is that it needs no network');
      }
    }
  });
}
