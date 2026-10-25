/// Tests for named senders in TofuStore (app/lib/src/tofu_store.dart).
///
/// Two things are being pinned here.
///
/// **The address book itself.** A device's Ed25519 identity is persistent,
/// so the same sender shows the same fingerprint on every transfer. That is
/// what makes a name worth storing — see IdentityStore.
///
/// **The format migration.** The store originally held a JSON array of
/// fingerprints; names need an object. A user who already trusts senders
/// must not be asked to re-approve them because the layout changed, and a
/// sender silently forgotten is a sender who gets a scary first-contact
/// warning on their next perfectly ordinary transfer.
library;

import 'dart:convert';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/tofu_store.dart';

/// In-memory keychain: flutter_secure_storage talks to the OS over a
/// platform channel that does not exist in flutter_tester.
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
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async =>
      data.clear();
}

const _storageKey = 'deaddrop_tofu_known_senders';
const _ana = 'aaaaaaaaaaaaaaaa';
const _bruno = 'bbbbbbbbbbbbbbbb';
const _carmen = 'cccccccccccccccc';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorage keychain;

  setUp(() {
    keychain = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = keychain;
  });

  group('naming a sender', () {
    test('a sender accepted with a name keeps it', () async {
      final store = TofuStore();

      await store.markKnown(_ana, name: 'Ana');

      expect(await store.isKnown(_ana), isTrue);
      expect(await store.nameFor(_ana), 'Ana');
    });

    test('a sender can be accepted without a name', () async {
      final store = TofuStore();

      await store.markKnown(_ana);

      expect(await store.isKnown(_ana), isTrue);
      expect(await store.nameFor(_ana), isNull);
    });

    test('re-accepting a named sender does not erase the name', () async {
      // The receive flow calls markKnown on acceptance. Accepting the same
      // sender again — a second transfer, a re-approval — must not quietly
      // drop a label the user chose.
      final store = TofuStore();
      await store.markKnown(_ana, name: 'Ana');

      await store.markKnown(_ana);

      expect(await store.nameFor(_ana), 'Ana');
    });

    test('a name can be changed later', () async {
      final store = TofuStore();
      await store.markKnown(_ana, name: 'Ana');

      await store.setName(_ana, 'Ana (work laptop)');

      expect(await store.nameFor(_ana), 'Ana (work laptop)');
    });

    test('a name can be removed, leaving the sender trusted', () async {
      final store = TofuStore();
      await store.markKnown(_ana, name: 'Ana');

      await store.setName(_ana, null);

      expect(await store.nameFor(_ana), isNull);
      expect(await store.isKnown(_ana), isTrue,
          reason: 'removing a label must not revoke trust');
    });

    test('a blank or whitespace name is stored as unnamed', () async {
      final store = TofuStore();

      await store.markKnown(_ana, name: '   ');

      expect(await store.nameFor(_ana), isNull,
          reason: 'a whitespace label would render as an empty name');
    });

    test('a name is trimmed', () async {
      final store = TofuStore();

      await store.markKnown(_ana, name: '  Ana  ');

      expect(await store.nameFor(_ana), 'Ana');
    });

    test('names survive a new store instance (they are persisted)', () async {
      await TofuStore().markKnown(_ana, name: 'Ana');

      // A fresh instance, as on the next app launch: no shared cache.
      expect(await TofuStore().nameFor(_ana), 'Ana');
    });
  });

  group('listing and forgetting', () {
    test('all() returns named senders first, then unnamed', () async {
      final store = TofuStore();
      await store.markKnown(_carmen);
      await store.markKnown(_bruno, name: 'Bruno');
      await store.markKnown(_ana, name: 'Ana');

      final list = await store.all();

      expect(list.keys.toList(), [_ana, _bruno, _carmen],
          reason: 'named senders sort by name; unnamed go last');
    });

    test('all() sorts names case-insensitively', () async {
      final store = TofuStore();
      await store.markKnown(_ana, name: 'ana');
      await store.markKnown(_bruno, name: 'Bruno');

      expect((await store.all()).keys.toList(), [_ana, _bruno]);
    });

    test('forget() removes one sender and leaves the rest', () async {
      final store = TofuStore();
      await store.markKnown(_ana, name: 'Ana');
      await store.markKnown(_bruno, name: 'Bruno');

      await store.forget(_ana);

      expect(await store.isKnown(_ana), isFalse,
          reason: 'a forgotten sender is a first contact again');
      expect(await store.isKnown(_bruno), isTrue);
    });
  });

  group('reading the original storage format', () {
    test('a JSON array of fingerprints is read as unnamed senders', () async {
      // What an install from before named senders has on disk.
      keychain.data[_storageKey] = jsonEncode([_ana, _bruno]);

      final store = TofuStore();

      expect(await store.isKnown(_ana), isTrue,
          reason: 'an already-trusted sender must not become a first '
              'contact again just because the format changed');
      expect(await store.isKnown(_bruno), isTrue);
      expect(await store.nameFor(_ana), isNull);
      expect(await store.count, 2);
    });

    test('an old store is rewritten in the new format on the next save',
        () async {
      keychain.data[_storageKey] = jsonEncode([_ana]);
      final store = TofuStore();

      await store.markKnown(_bruno, name: 'Bruno');

      final raw = jsonDecode(keychain.data[_storageKey]!);
      expect(raw, isA<Map>(), reason: 'migrated to the object format');
      expect((raw as Map)[_ana], isNull, reason: 'old entry preserved');
      expect(raw[_bruno], 'Bruno');
    });

    test('an unreadable store fails closed, not open', () async {
      // Trusting something we could not parse is the dangerous direction:
      // every sender should look new instead.
      keychain.data[_storageKey] = 'not json at all {{{';

      final store = TofuStore();

      expect(await store.isKnown(_ana), isFalse);
      expect(await store.count, 0);
    });

    test('a non-string name in stored JSON is read as unnamed', () async {
      keychain.data[_storageKey] = jsonEncode({_ana: 42, _bruno: 'Bruno'});

      final store = TofuStore();

      expect(await store.isKnown(_ana), isTrue);
      expect(await store.nameFor(_ana), isNull);
      expect(await store.nameFor(_bruno), 'Bruno');
    });
  });

  group('environment scoping still holds', () {
    test('a name recorded in one environment is invisible in another',
        () async {
      // The decoy must not expose the real environment's address book: a
      // list of real contacts inside the decoy is exactly the tell the
      // vault exists to avoid.
      await TofuStore(environmentSlot: 0).markKnown(_ana, name: 'Ana');

      final decoy = TofuStore(environmentSlot: 1);

      expect(await decoy.isKnown(_ana), isFalse);
      expect(await decoy.nameFor(_ana), isNull);
    });
  });
}
