/// Tests for [AttemptGuard] — the unlock rate limiter and the optional
/// self-destruct it drives.
///
/// Two of these matter more than the rest. The counter must be *global*,
/// because a per-environment counter would tell an attacker which
/// environment they were targeting and would let them reset their budget by
/// alternating passphrases. And self-destruct must destroy *every* slot when
/// it fires, because a surviving decoy would prove there had been something
/// to erase.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/vault/attempt_guard.dart';

/// In-memory fake for [FlutterSecureStoragePlatform]: the real plugin talks
/// to the OS keychain over a platform channel that does not exist in the
/// `flutter_tester` VM. Same shape as the fake in provider_scoping_test.dart.
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }

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
  }) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorage backend;
  late AttemptGuard guard;

  setUp(() {
    backend = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = backend;
    guard = AttemptGuard(storage: const FlutterSecureStorage());
  });

  Future<void> fail(int times) async {
    for (var i = 0; i < times; i++) {
      await guard.recordFailure();
    }
  }

  test('the first few attempts are not delayed', () async {
    expect(await guard.penaltyBeforeNextAttempt(), Duration.zero);
    await fail(kFreeAttempts - 1);
    expect(await guard.penaltyBeforeNextAttempt(), Duration.zero);
  });

  test('the penalty grows with consecutive failures', () async {
    await fail(kFreeAttempts);
    final first = await guard.penaltyBeforeNextAttempt();
    expect(first, greaterThan(Duration.zero));

    await fail(1);
    final second = await guard.penaltyBeforeNextAttempt();
    expect(second, greaterThan(first));
  });

  test('the penalty is capped', () async {
    await fail(100);
    expect(await guard.penaltyBeforeNextAttempt(), kMaxPenalty);
  });

  test('a success resets the counter', () async {
    await fail(5);
    expect(await guard.failureCount(), 5);

    await guard.recordSuccess();
    expect(await guard.failureCount(), 0);
    expect(await guard.penaltyBeforeNextAttempt(), Duration.zero);
  });

  test('the counter survives a restart', () async {
    await fail(4);
    // A fresh guard over the same backend stands in for a process restart:
    // the count must come from storage, not from in-memory state.
    final revived = AttemptGuard(storage: const FlutterSecureStorage());
    expect(await revived.failureCount(), 4);
  });

  test('the counter is global, not per environment', () async {
    // There is deliberately no environment parameter to pass — a
    // per-environment counter would reveal which environment an attacker
    // was targeting. This test pins that: the count accumulates across
    // every attempt regardless of which passphrase was tried, and exactly
    // one counter key exists in storage.
    await fail(3);
    expect(await guard.failureCount(), 3);

    final counterKeys =
        backend.data.keys.where((k) => k.contains('failures')).toList();
    expect(counterKeys, hasLength(1));
    expect(counterKeys.single, kAttemptCounterStorageKey);
    expect(counterKeys.single, isNot(contains('env')));
  });

  test('recordSuccess writes the key rather than deleting it', () async {
    // A key that vanishes on success and reappears on failure would itself
    // signal unlock activity to anyone inspecting the keychain.
    await guard.recordSuccess();
    expect(backend.data.containsKey(kAttemptCounterStorageKey), isTrue);
  });

  test('with self-destruct off, reaching the threshold does nothing', () async {
    // Off is the default: the preference key is simply absent.
    for (var i = 0; i < kSelfDestructThreshold - 1; i++) {
      expect(await guard.recordFailure(), isFalse);
    }
    expect(await guard.recordFailure(), isFalse,
        reason: 'threshold reached but self-destruct is off');
    expect(await guard.failureCount(), kSelfDestructThreshold);
  });

  test('with self-destruct on, reaching the threshold fires', () async {
    backend.data[kSelfDestructStorageKey] = 'true';

    for (var i = 0; i < kSelfDestructThreshold - 1; i++) {
      expect(await guard.recordFailure(), isFalse,
          reason: 'must not fire before the threshold');
    }
    expect(await guard.recordFailure(), isTrue,
        reason: 'threshold reached with self-destruct on');
  });

  test('an explicit "false" preference is off, like an absent one', () async {
    // settings_page.dart writes the preference on both on and off so its
    // presence leaks nothing; 'false' must behave exactly like absent.
    backend.data[kSelfDestructStorageKey] = 'false';
    await fail(kSelfDestructThreshold - 1);
    expect(await guard.recordFailure(), isFalse);
  });
}
