/// Can a receiver that arrives late ever join a running transfer?
///
/// The bootstrap code carries the session header, and a receiver cannot
/// decode anything without it. It used to be shown once, for four
/// seconds at the start, and never again: a receiver that was still
/// focusing, aimed slightly wrong, or simply started a moment later
/// would read hundreds of data codes and never begin. Nothing on
/// either screen said why -- the camera reported frames decoding, and
/// the progress bar stayed hidden, because the session had never
/// opened.
///
/// Reported from a desktop receiver sitting at "read 55" with no
/// progress while the sender was already at code 234.
///
/// That also contradicts what the loop is for: the codes repeat so a
/// transfer can be picked up at any point. The header has to repeat
/// with them.
library;

import 'dart:typed_data';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/identity_store.dart';
import 'package:dead_drop/ui/send/send_page.dart';

/// `flutter_secure_storage` talks to the OS keychain over a platform
/// channel that does not exist in the `flutter_tester` VM, and
/// startEmitting loads the device identity through it.
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      data[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      data[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();
}

Uint8List _file() =>
    Uint8List.fromList(List.generate(8192, (i) => i % 256));

Uint8List _receiverKey() => Uint8List.fromList(List.filled(32, 9));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  test('the bootstrap comes round again while the transfer runs', () async {
    final notifier = SendNotifier(sodium, IdentityStore(sodium));
    addTearDown(notifier.dispose);

    notifier.loadBytes('payload.bin', _file());
    notifier.setReceiverPk(_receiverKey());
    await notifier.startEmitting();

    // Walk past the opening bootstrap into the data stream.
    notifier.debugEmitFrames(1);
    expect(notifier.state.showingBootstrap, isFalse,
        reason: 'the data phase should have started');

    // Now watch a long run of codes. A receiver joining here must get
    // another header, or it can never start.
    var bootstraps = 0;
    for (var i = 0; i < kBootstrapRepeatEvery * 3; i++) {
      notifier.debugEmitFrames(1);
      if (notifier.state.showingBootstrap) bootstraps++;
    }

    expect(bootstraps, greaterThanOrEqualTo(2),
        reason: 'a receiver that arrives after the first four seconds '
            'must still be able to join. Showing the header once means '
            'a late receiver reads codes forever and never begins, '
            'which is what the repeating loop is supposed to prevent.');
  });

  test('repeating the header costs little of the stream', () async {
    // The counterpart: the header must not crowd out the payload.
    // Every bootstrap shown is a data code not shown.
    final notifier = SendNotifier(sodium, IdentityStore(sodium));
    addTearDown(notifier.dispose);

    notifier.loadBytes('payload.bin', _file());
    notifier.setReceiverPk(_receiverKey());
    await notifier.startEmitting();
    notifier.debugEmitFrames(1);

    const sample = 600;
    var bootstraps = 0;
    for (var i = 0; i < sample; i++) {
      notifier.debugEmitFrames(1);
      if (notifier.state.showingBootstrap) bootstraps++;
    }

    expect(bootstraps / sample, lessThan(0.05),
        reason: 'the header should be a small tax on the stream, not a '
            'significant share of it');
  });
}
