/// Tests for camera-driven emission hints
/// (app/lib/src/capability_hint.dart, and the handshake fields that carry
/// them in app/lib/src/handshake.dart).
///
/// The sender chooses frame rate, chunk size and error correction, but the
/// receiver's camera is what has to read them — and the channel is one-way,
/// so nothing comes back mid-transfer to say "too fast". The handshake QR
/// is the only moment the receiver can speak, which is why the hint rides
/// along with the public key.
///
/// Two things matter most here: a weak camera must get a gentler stream,
/// and a QR from an older version must still work.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/capability_hint.dart';
import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/src/handshake.dart';
import 'package:dead_drop/src/transport.dart';

final _key = Uint8List.fromList(List.generate(32, (i) => i));

void main() {
  group('suggesting settings', () {
    test('a good camera gets settings close to the defaults', () {
      final hint = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      expect(hint.chunkSize, kDefaultChunkSize);
      expect(hint.ecLevel, 'M');
      expect(hint.fps, greaterThanOrEqualTo(12));
    });

    test('emission stays below the camera, not level with it', () {
      // Sampling exactly at the emission rate catches each code at an
      // arbitrary point in its display, often mid-change. Headroom means
      // most frames land on a stable code.
      final hint = suggestEmission(const CameraCapability(
        framesPerSecond: 12,
        width: 1280,
        height: 720,
      ));

      expect(hint.fps, lessThan(12));
    });

    test('a slow camera gets a slower stream', () {
      final slow = suggestEmission(const CameraCapability(
        framesPerSecond: 8,
        width: 1280,
        height: 720,
      ));
      final fast = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      expect(slow.fps, lessThan(fast.fps));
    });

    test('a low-resolution camera gets smaller codes and more correction',
        () {
      // Below 640x480 there are not enough pixels to resolve a dense QR,
      // so each code should carry fewer modules.
      final hint = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 320,
        height: 240,
      ));

      expect(hint.chunkSize, lessThan(kDefaultChunkSize));
      expect(hint.ecLevel, 'Q');
      expect(hint.reason, contains('320x240'));
    });

    test('a poor decode rate backs off on every axis', () {
      // The most honest signal available: it reflects focus, lighting and
      // a shaky hand, none of which resolution or frame rate reveal.
      final measured = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
        decodeRate: 0.2,
      ));
      final unmeasured = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      expect(measured.fps, lessThan(unmeasured.fps));
      expect(measured.chunkSize, lessThan(unmeasured.chunkSize));
      expect(measured.ecLevel, isNot(unmeasured.ecLevel));
      expect(measured.reason, contains('20%'));
    });

    test('a healthy decode rate changes nothing', () {
      final good = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
        decodeRate: 0.9,
      ));
      final unknown = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      expect(good.fps, unknown.fps);
      expect(good.chunkSize, unknown.chunkSize);
    });

    test('always suggests a chunk size the sender can actually select', () {
      // A suggestion the sender cannot apply is worse than none.
      for (final fps in [1.0, 5.0, 12.0, 60.0]) {
        for (final size in [[160, 120], [320, 240], [1920, 1080]]) {
          for (final rate in [null, 0.1, 0.5, 1.0]) {
            final hint = suggestEmission(CameraCapability(
              framesPerSecond: fps,
              width: size[0],
              height: size[1],
              decodeRate: rate,
            ));
            expect(kChunkSizeOptions, contains(hint.chunkSize),
                reason: 'fps=$fps size=$size rate=$rate');
            expect(hint.fps, greaterThan(0));
          }
        }
      }
    });

    test('the reason always says something a person can read', () {
      final hint = suggestEmission(const CameraCapability(
        framesPerSecond: 15,
        width: 1280,
        height: 720,
      ));

      expect(hint.reason, isNotEmpty);
      expect(hint.reason, contains('15'));
    });
  });

  group('carrying the hint in the handshake QR', () {
    test('a hint survives the round trip', () {
      const sent = HandshakeHint(fps: 8, chunkSize: 256, ecLevel: 'Q');

      final decoded = decodeHandshakePayload(
        encodeHandshakeQr(_key, hint: sent),
      );

      expect(decoded, isNotNull);
      expect(decoded!.publicKey, _key);
      expect(decoded.hint!.fps, 8);
      expect(decoded.hint!.chunkSize, 256);
      expect(decoded.hint!.ecLevel, 'Q');
    });

    test('a QR with no hint still yields its key', () {
      final decoded = decodeHandshakePayload(encodeHandshakeQr(_key));

      expect(decoded!.publicKey, _key);
      expect(decoded.hint, isNull);
    });

    test('an older sender ignores the extra field', () {
      // The compatibility that makes this safe to ship: decodeHandshakeQr
      // is what shipped before, and must keep working against a QR that
      // now carries more than it did.
      const hint = HandshakeHint(fps: 8, chunkSize: 256, ecLevel: 'Q');

      final key = decodeHandshakeQr(encodeHandshakeQr(_key, hint: hint));

      expect(key, _key);
    });

    test('a malformed hint is dropped, not treated as an error', () {
      // An advisory field being wrong must not cost a perfectly good key.
      final doc = jsonEncode({
        't': handshakeType,
        'v': handshakeVersion,
        'pk': bytesToHex(_key),
        'h': {'fps': 'fast', 'cs': 'big', 'ec': 9},
      });
      final raw = encodeQrPayload(Uint8List.fromList(utf8.encode(doc)));

      final decoded = decodeHandshakePayload(raw);

      expect(decoded!.publicKey, _key);
      expect(decoded.hint, isNull);
    });

    test('an out-of-range hint is dropped', () {
      // 1000 fps is not a camera, it is a bug or a hostile QR. Either way
      // the key is still usable and the hint is not.
      final doc = jsonEncode({
        't': handshakeType,
        'v': handshakeVersion,
        'pk': bytesToHex(_key),
        'h': {'fps': 1000, 'cs': 512, 'ec': 'M'},
      });

      final decoded = decodeHandshakePayload(
        encodeQrPayload(Uint8List.fromList(utf8.encode(doc))),
      );

      expect(decoded!.publicKey, _key);
      expect(decoded.hint, isNull);
    });

    test('an unknown error-correction level is dropped', () {
      final doc = jsonEncode({
        't': handshakeType,
        'v': handshakeVersion,
        'pk': bytesToHex(_key),
        'h': {'fps': 10, 'cs': 512, 'ec': 'Z'},
      });

      final decoded = decodeHandshakePayload(
        encodeQrPayload(Uint8List.fromList(utf8.encode(doc))),
      );

      expect(decoded!.hint, isNull);
    });

    test('a foreign QR is still rejected outright', () {
      expect(decodeHandshakePayload('not a deaddrop qr'), isNull);
    });

    test('the hint does not make the QR unreasonably large', () {
      // The handshake QR is displayed on one screen and read by one
      // camera. If the hint pushed it into a much denser symbol it would
      // be self-defeating.
      final withHint = encodeHandshakeQr(
        _key,
        hint: const HandshakeHint(fps: 8, chunkSize: 256, ecLevel: 'Q'),
      );
      final without = encodeHandshakeQr(_key);

      expect(withHint.length - without.length, lessThan(60),
          reason: 'the hint should cost a few dozen characters, not double '
              'the payload');
    });
  });
}
