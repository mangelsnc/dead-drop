/// Tests for the emission hint actually reaching the sender's settings
/// (capability_hint.dart had 16 tests and no caller until now).
///
/// The suggestion travels: receiver measures its camera → the measurement
/// is stored → the next handshake QR carries it → the sender scans and
/// applies it. Each link is cheap to break silently, because nothing
/// fails when a hint is dropped — the transfer just runs at the sender's
/// defaults and nobody is told why.
///
/// The one place a hint must NOT win is chunk size: pickFile chooses the
/// smallest size that can carry the file, and a smaller suggestion would
/// make the transfer impossible rather than merely slow.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/camera_measurement_store.dart';
import 'package:dead_drop/src/capability_hint.dart';
import 'package:dead_drop/src/crypto.dart';
import 'package:dead_drop/src/handshake.dart';
import 'package:dead_drop/src/identity_store.dart';
import 'package:dead_drop/ui/send/send_page.dart';

Uint8List _key(int fill) => Uint8List.fromList(List.filled(32, fill));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('measurement_test_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('remembering a measurement', () {
    test('a stored measurement comes back', () async {
      final store = CameraMeasurementStore(directory: dir);
      await store.write(const CameraCapability(
        framesPerSecond: 9.5,
        width: 640,
        height: 480,
        decodeRate: 0.4,
      ));

      final back = await store.read();

      expect(back, isNotNull);
      expect(back!.capability.framesPerSecond, closeTo(9.5, 0.01));
      expect(back.capability.width, 640);
      expect(back.capability.height, 480);
      expect(back.capability.decodeRate, closeTo(0.4, 0.01));
    });

    test('a first run has nothing to announce', () async {
      expect(await CameraMeasurementStore(directory: dir).read(), isNull);
    });

    test('a stale measurement is discarded, not trusted', () async {
      // A reading taken in good light a month ago, replayed in a dark
      // room, suggests a stream the camera can no longer follow.
      var now = DateTime(2026, 1, 1);
      final store = CameraMeasurementStore(directory: dir, now: () => now);
      await store.write(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      now = now.add(kMeasurementMaxAge + const Duration(days: 1));

      expect(await store.read(), isNull);
      // One day inside the window still counts.
      now = DateTime(2026, 1, 1).add(kMeasurementMaxAge - const Duration(days: 1));
      expect(await store.read(), isNotNull);
    });

    test('a corrupt file reads as no measurement', () async {
      // Must never throw into the receive screen: the fallback is simply
      // a QR with no hint, which is what shipped before this existed.
      final store = CameraMeasurementStore(directory: dir);
      await (await store.debugFile()).writeAsString('not json at all');

      expect(await store.read(), isNull);
    });

    test('an impossible camera reads as no measurement', () async {
      final store = CameraMeasurementStore(directory: dir);
      await (await store.debugFile()).writeAsString(jsonEncode({
        'fps': 0,
        'w': 1280,
        'h': 720,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));

      expect(await store.read(), isNull);
    });

    test('clearing stops the device announcing anything', () async {
      final store = CameraMeasurementStore(directory: dir);
      await store.write(const CameraCapability(
        framesPerSecond: 12,
        width: 640,
        height: 480,
      ));
      expect(await store.read(), isNotNull);

      await store.clear();

      expect(await store.read(), isNull);
    });

    test('a later measurement replaces an earlier one', () async {
      // Otherwise a single bad reading would follow the device forever.
      final store = CameraMeasurementStore(directory: dir);
      await store.write(const CameraCapability(
        framesPerSecond: 5,
        width: 320,
        height: 240,
      ));
      await store.write(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
      ));

      final back = await store.read();

      expect(back!.capability.framesPerSecond, closeTo(30, 0.01));
      expect(back.capability.width, 1280);
    });
  });

  group('a stored measurement produces a usable hint', () {
    test('a weak camera ends up suggesting a gentler stream', () async {
      // The end-to-end property this whole chain exists for.
      final store = CameraMeasurementStore(directory: dir);
      await store.write(const CameraCapability(
        framesPerSecond: 8,
        width: 320,
        height: 240,
        decodeRate: 0.2,
      ));

      final hint = suggestEmission((await store.read())!.capability);

      expect(hint.fps, lessThan(8));
      expect(hint.chunkSize, lessThan(512));
      expect(hint.reason, isNotEmpty);
    });

    test('a good camera round-trips to near the defaults', () async {
      final store = CameraMeasurementStore(directory: dir);
      await store.write(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
        decodeRate: 0.95,
      ));

      final direct = suggestEmission(const CameraCapability(
        framesPerSecond: 30,
        width: 1280,
        height: 720,
        decodeRate: 0.95,
      ));
      final viaStore = suggestEmission((await store.read())!.capability);

      expect(viaStore.fps, direct.fps);
      expect(viaStore.chunkSize, direct.chunkSize);
      expect(viaStore.ecLevel, direct.ecLevel);
    });
  });

  group('the sender applying what it scanned', () {
    late SodiumSumo sodium;

    setUpAll(() async => sodium = await SodiumSumoInit.init());

    SendNotifier build() =>
        SendNotifier(sodium, IdentityStore(sodium));

    test('a scanned hint sets frame rate, chunk size and correction', () {
      // The wiring that did not exist: suggestEmission had tests and no
      // caller, so a perfectly good suggestion reached the sender's
      // screen and changed nothing.
      final notifier = build();
      final before = notifier.state.fps;

      notifier.setReceiverPk(
        _key(1),
        hint: const HandshakeHint(fps: 6, chunkSize: 256, ecLevel: 'Q'),
      );

      expect(notifier.state.fps, 6);
      expect(notifier.state.chunkSize, 256);
      expect(notifier.state.ecLevel, 'Q');
      expect(before, isNot(6), reason: 'otherwise this test proves nothing');
      expect(notifier.state.appliedHint, isNotNull,
          reason: 'the screen has to be able to say where these came from');
    });

    test('a QR with no hint leaves the settings alone', () {
      final notifier = build();
      notifier.setFps(15);
      notifier.setEcLevel('L');

      notifier.setReceiverPk(_key(2));

      expect(notifier.state.fps, 15);
      expect(notifier.state.ecLevel, 'L');
      expect(notifier.state.appliedHint, isNull);
    });

    group('negotiating against what this screen can draw', () {
      // The handshake happens before any QR exists, so the size used to
      // be zero and the negotiation was skipped by a `> 0` guard — at
      // exactly the moment it was needed. Reported from a phone: it
      // accepted 512 bytes from a Mac Studio's handshake, then warned
      // that its own screen could not draw them. The warning was right
      // and far too late.

      test('a hint too dense for this screen is cut down, not accepted', () {
        final notifier = build();
        // A phone-sized code. 512 bytes needs more room than this.
        notifier.predictQrDisplaySize(320);

        notifier.setReceiverPk(
          _key(10),
          hint: const HandshakeHint(fps: 10, chunkSize: 512, ecLevel: 'L'),
        );

        expect(notifier.state.chunkSize, lessThan(512),
            reason: 'a screen that cannot draw 512 must not agree to it');
      });

      test('a hint this screen can draw is accepted unchanged', () {
        // The counterpart: the negotiation must not cut down a request
        // that was fine, or every transfer runs slower than it could.
        final notifier = build();
        notifier.predictQrDisplaySize(kQrMaxDisplaySize);

        notifier.setReceiverPk(
          _key(11),
          hint: const HandshakeHint(fps: 10, chunkSize: 512, ecLevel: 'L'),
        );

        expect(notifier.state.chunkSize, 512);
      });

      test('a real measurement replaces a prediction', () {
        final notifier = build();
        notifier.predictQrDisplaySize(320);

        notifier.reportQrDisplaySize(700);

        expect(notifier.state.qrDisplaySizePx, 700);
        expect(notifier.state.qrDisplaySizeMeasured, isTrue);
      });

      test('a prediction never replaces a real measurement', () {
        // The sending view knows the truth; the config page only
        // estimates. A later estimate overwriting a measurement would
        // reintroduce the guess this replaced.
        final notifier = build();
        notifier.reportQrDisplaySize(700);

        notifier.predictQrDisplaySize(320);

        expect(notifier.state.qrDisplaySizePx, 700);
      });
    });

    test('a key entered by hand clears a hint from an earlier scan', () {
      // Otherwise the screen keeps claiming "set from the receiver's
      // camera" for a receiver whose key was typed in by hand.
      final notifier = build();
      notifier.setReceiverPk(
        _key(3),
        hint: const HandshakeHint(fps: 6, chunkSize: 256, ecLevel: 'Q'),
      );
      expect(notifier.state.appliedHint, isNotNull);

      notifier.setReceiverPk(_key(4));

      expect(notifier.state.appliedHint, isNull);
    });

    test('a hint never shrinks the chunk size below what the file needs',
        () {
      // The one case where the receiver's suggestion must lose. A chunk
      // size too small for the file overflows the uint16 chunk count, so
      // obeying the hint would make the transfer impossible rather than
      // slow.
      final notifier = build();
      final big = Uint8List(maxFileSizeForChunkSize(256) + 1);
      notifier.state = SendState(
        fileName: 'big.bin',
        fileBytes: big,
        chunkSize: 2048,
      );

      notifier.setReceiverPk(
        _key(5),
        hint: const HandshakeHint(fps: 6, chunkSize: 256, ecLevel: 'Q'),
      );

      expect(notifier.state.chunkSize, 2048,
          reason: 'a file that cannot fit 256-byte chunks must keep its own');
      expect(notifier.state.fps, 6);
      // 'Q' is refused here, not because of the hint but because a
      // 2048-byte frame only fits a QR at level L. Obeying it would
      // produce a code too large to draw.
      expect(notifier.state.ecLevel, 'L');
    });

    test('a hint that the file can carry is applied', () {
      // The mirror of the test above: the guard must not be a blanket
      // refusal that quietly drops every chunk-size suggestion.
      final notifier = build();
      notifier.state = SendState(
        fileName: 'small.txt',
        fileBytes: Uint8List(1000),
        chunkSize: 2048,
      );

      notifier.setReceiverPk(
        _key(6),
        hint: const HandshakeHint(fps: 6, chunkSize: 256, ecLevel: 'Q'),
      );

      expect(notifier.state.chunkSize, 256);
    });
  });
}
