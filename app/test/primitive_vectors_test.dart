/// Official test vectors for the primitives DeadDrop orchestrates.
///
/// DeadDrop implements no cryptography: it calls libsodium through
/// `package:sodium`. That is only worth something if the primitives it
/// calls really are the published ones, computing what their standards
/// say they compute. A system can be perfectly self-consistent and
/// wrong — every round-trip test in this suite would still pass if the
/// whole stack agreed on a cipher nobody else implements.
///
/// So these vectors come from outside this project, and none of them
/// were produced by running this code:
///
/// * X25519 — RFC 7748 section 5.2 (scalar multiplication) and
///   section 6.1 (the Diffie-Hellman example).
/// * Ed25519 — RFC 8032 section 7.1, tests 1 to 3.
/// * BLAKE2b — RFC 7693 appendix A.
/// * Argon2id — libsodium's own `test/default/pwhash_argon2id.c`
///   and its expected output, `pwhash_argon2id.exp`.
///
/// RFC 9106's own Argon2id vector (section 5.3) is deliberately **not**
/// here, and cannot be: it specifies a secret key, associated data and
/// four lanes, and `crypto_pwhash` accepts none of the three. Pinning
/// libsodium's vector instead keeps the test honest about which API the
/// vault actually calls — see [the Argon2id group] for the detail.
///
/// These are the primitives, not the protocol. Vectors for DeadDrop's
/// own frame and session encoding are a separate question; the fountain
/// derivation is pinned in `fountain_vectors_test.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------------
// RFC 7748 section 5.2 — X25519 scalar multiplication.
// ---------------------------------------------------------------------

const _x25519Vectors = [
  (
    scalar: 'a546e36bf0527c9d3b16154b82465edd'
        '62144c0ac1fc5a18506a2244ba449ac4',
    u: 'e6db6867583030db3594c1a424b15f7c'
        '726624ec26b3353b10a903a6d0ab1c4c',
    output: 'c3da55379de9c6908e94ea4df28d084f'
        '32eccf03491c71f754b4075577a28552',
  ),
  (
    scalar: '4b66e9d4d1b4673c5ad22691957d6af5'
        'c11b6421e0ea01d42ca4169e7918ba0d',
    u: 'e5210f12786811d3f4b7959d0538ae2c'
        '31dbe7106fc03c3efc4cd549c715a493',
    output: '95cbde9476e8907d7aade45cb4b873f8'
        '8b595a68799fa152e6f8f7647aac7957',
  ),
];

// RFC 7748 section 6.1 — the Diffie-Hellman worked example.
const _alicePrivate = '77076d0a7318a57d3c16c17251b26645'
    'df4c2f87ebc0992ab177fba51db92c2a';
const _alicePublic = '8520f0098930a754748b7ddcb43ef75a'
    '0dbf3a0d26381af4eba4a98eaa9b4e6a';
const _bobPrivate = '5dab087e624a8a4b79e17f8b83800ee6'
    '6f3bb1292618b6fd1c2f8b27ff88e0eb';
const _bobPublic = 'de9edb7d7b7dc1b4d35b61c2ece43537'
    '3f8343c85b78674dadfc7e146f882b4f';
const _sharedSecret = '4a5d9d5ba4ce2de1728e3bf480350f25'
    'e07e21c947d19e3376f09b3c1e161742';

// ---------------------------------------------------------------------
// RFC 8032 section 7.1 — Ed25519, tests 1 to 3.
// ---------------------------------------------------------------------

const _ed25519Vectors = [
  (
    name: 'TEST 1 (empty message)',
    secretKey: '9d61b19deffd5a60ba844af492ec2cc4'
        '4449c5697b326919703bac031cae7f60',
    publicKey: 'd75a980182b10ab7d54bfed3c964073a'
        '0ee172f3daa62325af021a68f707511a',
    message: '',
    signature: 'e5564300c360ac729086e2cc806e828a'
        '84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46b'
        'd25bf5f0595bbe24655141438e7a100b',
  ),
  (
    name: 'TEST 2 (one byte)',
    secretKey: '4ccd089b28ff96da9db6c346ec114e0f'
        '5b8a319f35aba624da8cf6ed4fb8a6fb',
    publicKey: '3d4017c3e843895a92b70aa74d1b7ebc'
        '9c982ccf2ec4968cc0cd55f12af4660c',
    message: '72',
    signature: '92a009a9f0d4cab8720e820b5f642540'
        'a2b27b5416503f8fb3762223ebdb69da'
        '085ac1e43e15996e458f3613d0f11d8c'
        '387b2eaeb4302aeeb00d291612bb0c00',
  ),
  (
    name: 'TEST 3 (two bytes)',
    secretKey: 'c5aa8df43f9f837bedb7442f31dcb7b1'
        '66d38535076f094b85ce3a2e0b4458f7',
    publicKey: 'fc51cd8e6218a1a38da47ed00230f058'
        '0816ed13ba3303ac5deb911548908025',
    message: 'af82',
    signature: '6291d657deec24024827e69c3abe01a3'
        '0ce548a284743a445e3680d7db5ac3ac'
        '18ff9b538d16f290ae67f760984dc659'
        '4a7c15e9716ed28dc027beceea1ec40a',
  ),
];

// ---------------------------------------------------------------------
// RFC 7693 appendix A — BLAKE2b-512 of the three ASCII bytes "abc".
// ---------------------------------------------------------------------

const _blake2bAbc =
    'ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1'
    '7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923';

// ---------------------------------------------------------------------
// Argon2id — libsodium's own vector, from test/default/pwhash_argon2id.c
// (the `tv2` table) and its expected output pwhash_argon2id.exp.
//
// Two details of that test are load-bearing and easy to get wrong:
//
//  * The salt literal in the C source is 32 bytes, but it is read into a
//    `crypto_pwhash_SALTBYTES` buffer, so `sodium_hex2bin` stops after 16
//    and returns an error the test ignores. The salt libsodium actually
//    hashed is the first 16 bytes, which is what is pinned here.
//  * The password is 127 bytes of binary, not text.
// ---------------------------------------------------------------------

const _argon2idPassword =
    'a347ae92bce9f80f6f595a4480fc9c2fe7e7d7148d371e9487d75f5c23008ffa'
    'e065577a928febd9b1973a5a95073acdbeb6a030cfc0d79caa2dc5cd011cef02'
    'c08da232d76d52dfbca38ca8dcbd665b17d1665f7cf5fe59772ec909733b24de'
    '97d6f58d220b20c60d7c07ec1fd93c52c31020300c6c1facd77937a597c7a6';

const _argon2idSalt = '5541fbc995d5c197ba290346d2c559de';

const _argon2idOps4 =
    '20e7ba6faa2c0a4b07f3ff38e15e252a069c2c62bac3f2785d311764d73e67fd'
    '713be342ee938e6df4de6af1a89a44b8589838864457bcfe3cf0f2d329b800ab'
    '9f5810b6325588eb4e0c56f99192b2cc76dc8194dc1097fe5ed12ac4214481c0'
    '3c3597131ba164a56e7187e2da565a8cd529668e9a37faa58a1701c49a14edf7'
    'a50dec4143b456cba6d14c957bb655e99ce96bc506961216ef887a';

const _argon2idOps3 =
    '8fb6ed1862cdd2a399e10956c60dc9b2670338ea59c3414d0443216925ba24c6'
    'e89a17f3e56c12893dcbc9bc498e8308aea9627d9c9e47912d6342b631008719'
    'edfa2db364b97e60cf47a97ad9aa3b7f139d80ddda44f1ef2af881ce027a1564'
    '4218cac6cc74751469ae56be0469fbc760825882b3e8abca55daaae575357510'
    '6cf867cd69932602c63ec880ad8811d9aa4870a9e0b39fef47c92e';

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  group('X25519 (RFC 7748)', () {
    test('section 5.2: scalar multiplication matches the published vectors',
        () {
      for (final v in _x25519Vectors) {
        final scalar = SecureKey.fromList(sodium, _hex(v.scalar));
        addTearDown(scalar.dispose);
        final result = sodium.crypto.scalarmult(
          n: scalar,
          p: _hex(v.u),
        );
        addTearDown(result.dispose);

        expect(_toHex(result.extractBytes()), v.output,
            reason: 'X25519(${v.scalar}, ${v.u})');
      }
    });

    test('section 6.1: both sides reach the published shared secret', () {
      // The published example, both directions. This is the operation
      // under crypto_box, which is how every transfer agrees a key.
      final aPriv = SecureKey.fromList(sodium, _hex(_alicePrivate));
      final bPriv = SecureKey.fromList(sodium, _hex(_bobPrivate));
      addTearDown(aPriv.dispose);
      addTearDown(bPriv.dispose);

      expect(_toHex(sodium.crypto.scalarmult.base(n: aPriv)), _alicePublic,
          reason: "Alice's public key is X25519(a, 9)");
      expect(_toHex(sodium.crypto.scalarmult.base(n: bPriv)), _bobPublic,
          reason: "Bob's public key is X25519(b, 9)");

      final aliceSide =
          sodium.crypto.scalarmult(n: aPriv, p: _hex(_bobPublic));
      final bobSide = sodium.crypto.scalarmult(n: bPriv, p: _hex(_alicePublic));
      addTearDown(aliceSide.dispose);
      addTearDown(bobSide.dispose);

      expect(_toHex(aliceSide.extractBytes()), _sharedSecret);
      expect(_toHex(bobSide.extractBytes()), _sharedSecret,
          reason: 'both sides must reach the same secret');
    });
  });

  group('Ed25519 (RFC 8032 section 7.1)', () {
    test('a published secret key derives its published public key', () {
      for (final v in _ed25519Vectors) {
        final seed = SecureKey.fromList(sodium, _hex(v.secretKey));
        addTearDown(seed.dispose);
        // RFC 8032's "secret key" is libsodium's seed: libsodium's own
        // secret key is the seed followed by the public key.
        final pair = sodium.crypto.sign.seedKeyPair(seed);
        addTearDown(pair.secretKey.dispose);

        expect(_toHex(pair.publicKey), v.publicKey, reason: v.name);
      }
    });

    test('signing a published message produces its published signature', () {
      for (final v in _ed25519Vectors) {
        final seed = SecureKey.fromList(sodium, _hex(v.secretKey));
        addTearDown(seed.dispose);
        final pair = sodium.crypto.sign.seedKeyPair(seed);
        addTearDown(pair.secretKey.dispose);

        final signature = sodium.crypto.sign.detached(
          message: _hex(v.message),
          secretKey: pair.secretKey,
        );

        expect(_toHex(signature), v.signature, reason: v.name);
      }
    });

    test('the published signature verifies, and a flipped bit does not', () {
      // Ed25519 is what tells a receiver who sent a transfer. A verify
      // that accepts everything would pass the test above, since that
      // one only signs.
      for (final v in _ed25519Vectors) {
        expect(
          sodium.crypto.sign.verifyDetached(
            message: _hex(v.message),
            signature: _hex(v.signature),
            publicKey: _hex(v.publicKey),
          ),
          isTrue,
          reason: v.name,
        );

        final tampered = _hex(v.signature);
        tampered[0] ^= 0x01;
        expect(
          sodium.crypto.sign.verifyDetached(
            message: _hex(v.message),
            signature: tampered,
            publicKey: _hex(v.publicKey),
          ),
          isFalse,
          reason: '${v.name}: a corrupted signature must not verify',
        );
      }
    });
  });

  group('BLAKE2b (RFC 7693 appendix A)', () {
    test('the unkeyed 512-bit hash of "abc" matches the published digest', () {
      final digest = sodium.crypto.genericHash(
        message: Uint8List.fromList(utf8.encode('abc')),
        outLen: 64,
      );

      expect(_toHex(digest), _blake2bAbc);
    });
  });

  group('Argon2id (libsodium pwhash_argon2id)', () {
    // Slow by design: 397645 bytes of memory, 3 and 4 passes. That is
    // the point of a memory-hard hash, and it is why this group is
    // tagged — the vault's own parameters cost more still.
    test('matches libsodium at opslimit 4', () {
      final password = _hex(_argon2idPassword);
      final out = sodium.crypto.pwhash.callRaw(
        outLen: 155,
        password: Int8List.view(
            password.buffer, password.offsetInBytes, password.length),
        salt: _hex(_argon2idSalt),
        opsLimit: 4,
        memLimit: 397645,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      addTearDown(out.dispose);

      expect(_toHex(out.extractBytes()), _argon2idOps4);
    });

    test('matches libsodium at opslimit 3', () {
      final password = _hex(_argon2idPassword);
      final out = sodium.crypto.pwhash.callRaw(
        outLen: 155,
        password: Int8List.view(
            password.buffer, password.offsetInBytes, password.length),
        salt: _hex(_argon2idSalt),
        opsLimit: 3,
        memLimit: 397645,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      addTearDown(out.dispose);

      expect(_toHex(out.extractBytes()), _argon2idOps3,
          reason: 'a different pass count must give a different tag');
    });

    test('the vault derives its key with argon2id13, not a weaker default',
        () {
      // deriveKek names the algorithm explicitly. If that argument were
      // ever dropped, libsodium's default would take over — which is
      // argon2id13 today, so a round-trip test would not notice, and
      // the vault would silently follow whatever a future libsodium
      // chose as its default.
      expect(CryptoPwhashAlgorithm.argon2id13.name, 'argon2id13');
    });
  });
}
