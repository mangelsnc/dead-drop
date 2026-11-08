/// How many times one unlock attempt touches the keychain.
///
/// On an unsigned macOS build the system asks the owner to authorise
/// each keychain item, so every avoidable access is a password prompt in
/// front of someone who is already having a bad time. Reported from a
/// macOS build: "with each attempt macOS asks me twice for the keychain
/// password".
///
/// One failed attempt used to touch the counter three times — a read to
/// work out the penalty, a second read inside recordFailure, and the
/// write — where two of those were the same question asked twice.
///
/// The counter still lives in the keychain. It has to: a count held only
/// in memory would reset when the app closes, and self-destruct would
/// never fire against someone who simply relaunches between guesses.
/// That is pinned here too, because caching is exactly the change that
/// could quietly break it.
library;

import 'package:dead_drop/src/vault/attempt_guard.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every operation, which is what a macOS prompt corresponds to.
class _CountingStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};
  final List<String> ops = [];

  List<String> get counterOps =>
      ops.where((o) => o.endsWith(kAttemptCounterStorageKey)).toList();

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    ops.add('write:$key');
    data[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    ops.add('read:$key');
    return data[key];
  }

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
  }) async {
    ops.add('delete:$key');
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingStorage storage;

  AttemptGuard buildGuard() => AttemptGuard(
        storage: const FlutterSecureStorage(),
        penaltyStep: Duration.zero,
      );

  setUp(() {
    storage = _CountingStorage();
    FlutterSecureStoragePlatform.instance = storage;
  });

  test('a failed attempt reads the counter at most once', () async {
    final guard = buildGuard();

    await guard.penaltyBeforeNextAttempt();
    await guard.recordFailure();

    final reads =
        storage.counterOps.where((o) => o.startsWith('read:')).length;
    expect(reads, lessThanOrEqualTo(1),
        reason: 'the penalty check and recordFailure asked the same '
            'question twice, and macOS prompted for each');
  });

  test('later attempts do not read it again at all', () async {
    final guard = buildGuard();
    await guard.penaltyBeforeNextAttempt();
    await guard.recordFailure();
    storage.ops.clear();

    await guard.penaltyBeforeNextAttempt();
    await guard.recordFailure();

    expect(storage.counterOps.where((o) => o.startsWith('read:')), isEmpty,
        reason: 'this process already knows the count it just wrote');
  });

  test('the count still reaches the threshold', () async {
    // Caching must not cost the thing the counter exists for.
    final guard = buildGuard();
    for (var i = 1; i < selfDestructThreshold; i++) {
      expect(await guard.recordFailure(), isFalse,
          reason: 'must not fire early, at attempt $i');
    }
    expect(await guard.failureCount(), selfDestructThreshold - 1);
  });

  test('the count survives the app closing', () async {
    // The property a cache could silently destroy: a new guard over the
    // same keychain must see the failures the old one recorded, or
    // relaunching between guesses would defeat self-destruct.
    final first = buildGuard();
    await first.recordFailure();
    await first.recordFailure();

    final afterRelaunch = buildGuard();

    expect(await afterRelaunch.failureCount(), 2,
        reason: 'a counter held only in memory would read zero here');
  });

  test('a successful unlock clears it for the next reader', () async {
    final guard = buildGuard();
    await guard.recordFailure();
    await guard.recordSuccess();

    expect(await guard.failureCount(), 0);
    expect(await buildGuard().failureCount(), 0,
        reason: 'and the keychain agrees, not just the cache');
  });

  test('reset clears it for the next reader too', () async {
    final guard = buildGuard();
    await guard.recordFailure();
    await guard.reset();

    expect(await guard.failureCount(), 0);
    expect(await buildGuard().failureCount(), 0);
  });
}
