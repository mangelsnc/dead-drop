/// The self-destruct rehearsal build, and the fact it is not the default.
///
/// Self-destruct cannot be verified by hand in a reasonable time: the
/// threshold is ten failures and the penalties before them add up to two
/// minutes and twenty seconds of genuine waiting. So a build can be made
/// that reaches it in three attempts with no delays, which is the only
/// way an owner gets to watch the thing fire before trusting it with
/// something real.
///
/// What this file pins is that the shortcut is OFF unless the binary was
/// built for it. A release that silently destroyed a vault on the third
/// mistyped passphrase would be the worst bug this project could ship:
/// the honest user mistypes, and the feature meant to defeat coercion
/// erases their files instead.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/vault/attempt_guard.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('an ordinary build is not a rehearsal build', () {
    // `make test` passes no dart-define, so this is what a release
    // resolves to. If this ever fails, a rehearsal build is about to be
    // published.
    expect(selfDestructRehearsal, isFalse);
  });

  test('the production thresholds are what an ordinary build uses', () {
    expect(selfDestructThreshold, kSelfDestructThreshold);
    expect(selfDestructThreshold, 10);
    expect(freeAttempts, kFreeAttempts);
    expect(penaltyStep, kPenaltyStep);
  });

  test('an ordinary build does not fire before its own threshold',
      () async {
    // The counting is the production path either way; what the flag
    // changes is the number it is compared against. With the flag off
    // that number is ten, and nine failures must do nothing — this is
    // the assertion a release depends on.
    final backend = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = backend;
    backend.data[kSelfDestructStorageKey] = 'true';
    final guard = AttemptGuard(
      storage: const FlutterSecureStorage(),
      penaltyStep: Duration.zero,
    );

    for (var i = 1; i < selfDestructThreshold; i++) {
      expect(await guard.recordFailure(), isFalse,
          reason: 'failure $i of $selfDestructThreshold must not fire');
    }
    expect(await guard.recordFailure(), isTrue,
        reason: 'the threshold itself must fire');
  });

  test('the rehearsal changes when it fires, never whether it is opt-in',
      () async {
    // With the preference off, no threshold fires — in either build.
    // A rehearsal build that destroyed a vault nobody armed would be
    // the same bug as a release doing it.
    final backend = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = backend;
    final guard = AttemptGuard(
      storage: const FlutterSecureStorage(),
      penaltyStep: Duration.zero,
    );

    for (var i = 0; i <= selfDestructThreshold + 1; i++) {
      expect(await guard.recordFailure(), isFalse,
          reason: 'self-destruct is opt-in; nothing armed it');
    }
  });

  test('a rehearsal still serves a wait before the attempt that fires',
      () async {
    // The point of rehearsing is to watch the real sequence. In
    // production a delay always precedes the threshold, so a rehearsal
    // with no delays would rehearse something that cannot happen —
    // and the wait message, which is the other thing worth seeing,
    // would never appear.
    //
    // Written against freeAttempts rather than a literal, so it holds
    // in both builds: the attempt that fires must be a penalised one.
    expect(selfDestructThreshold, greaterThan(freeAttempts),
        reason: 'the threshold has to sit beyond the free attempts, or '
            'the vault is destroyed before any delay is served');

    final backend = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = backend;
    final guard = AttemptGuard(storage: const FlutterSecureStorage());

    // Spend the free attempts; the next one must cost a wait.
    for (var i = 0; i < freeAttempts; i++) {
      await guard.recordFailure();
    }
    expect(await guard.penaltyBeforeNextAttempt(), greaterThan(Duration.zero),
        reason: 'the attempt after the free ones must be penalised, so '
            'the wait message has something to show');
  });

  test('the production curve really is slow enough to need a rehearsal',
      () {
    // The reason this build exists, as arithmetic: reaching the
    // threshold by hand costs this much waiting.
    var total = Duration.zero;
    for (var failures = kFreeAttempts;
        failures < kSelfDestructThreshold;
        failures++) {
      final steps = failures - kFreeAttempts + 1;
      final raw = kPenaltyStep * steps;
      total += raw > kMaxPenalty ? kMaxPenalty : raw;
    }

    expect(total.inSeconds, greaterThan(120),
        reason: 'if the production curve ever becomes quick enough to '
            'test by hand, this build has no reason to exist');
  });
}
