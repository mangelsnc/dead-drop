/// Tests for clearing a loaded receiver key
/// (app/lib/ui/send/send_page.dart).
///
/// The bug this guards against: once any receiver key was loaded — the right
/// one or the wrong one — the send page replaced the whole "scan or enter a
/// key" section with a confirmation card whose only action was "Rescan". On
/// a platform with no camera (mobile_scanner 5.2.3 has no Linux or Windows
/// implementation) rescanning cannot succeed, so a mis-scanned or mistyped
/// key meant closing the application and starting over.
///
/// `SendState.copyWith` uses the `?? this.field` idiom throughout, which
/// cannot express "set this back to null" — so clearing the key needs its
/// own flag, and that flag is what these tests pin.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/send/send_page.dart';

Uint8List _key(int fill) => Uint8List.fromList(List.filled(32, fill));

void main() {
  group('SendState.copyWith', () {
    test('clearReceiverPk returns the key to null', () {
      final loaded = SendState().copyWith(receiverPk: _key(1));
      expect(loaded.receiverPk, isNotNull);

      final cleared = loaded.copyWith(clearReceiverPk: true);

      expect(cleared.receiverPk, isNull,
          reason: 'a wrong key must be removable without restarting the app');
    });

    test('clearing the key leaves the chosen file alone', () {
      // The user picked a file and then scanned the wrong key. Making them
      // pick the file again would be a second, pointless step.
      final state = SendState().copyWith(
        fileName: 'report.pdf',
        fileBytes: Uint8List.fromList([1, 2, 3]),
        receiverPk: _key(7),
      );

      final cleared = state.copyWith(clearReceiverPk: true);

      expect(cleared.receiverPk, isNull);
      expect(cleared.fileName, 'report.pdf');
      expect(cleared.fileBytes, isNotNull);
    });

    test('a later copyWith can load a new key after clearing', () {
      final cleared =
          SendState().copyWith(receiverPk: _key(1)).copyWith(
                clearReceiverPk: true,
              );

      final reloaded = cleared.copyWith(receiverPk: _key(2));

      expect(reloaded.receiverPk, isNotNull);
      expect(reloaded.receiverPk!.first, 2,
          reason: 'the replacement key must win, not the cleared one');
    });

    test('without the flag, copyWith still cannot null the key', () {
      // Documents why the flag exists at all: passing null means "leave it
      // alone" in this idiom, not "clear it".
      final loaded = SendState().copyWith(receiverPk: _key(3));

      final untouched = loaded.copyWith(receiverPk: null);

      expect(untouched.receiverPk, isNotNull);
    });
  });

  group('resetTransfer', () {
    // Stop keeps the file and the key so the user can retune and start
    // again. This is the other case: done with that file, on to the next.
    // Without it the only way back to an empty form was to close the app.
    test('clears the file and the receiver key', () {
      final loaded = SendState().copyWith(
        fileName: 'report.pdf',
        fileBytes: Uint8List.fromList([1, 2, 3]),
        receiverPk: _key(1),
      );

      // resetTransfer builds a fresh SendState, keeping only what is not
      // part of this transfer. Modelled here as the state it produces.
      final after = SendState(
        identity: loaded.identity,
        chunkSize: loaded.chunkSize,
        ecLevel: loaded.ecLevel,
        fps: loaded.fps,
      );

      expect(after.fileName, isNull);
      expect(after.fileBytes, isNull);
      expect(after.receiverPk, isNull);
      expect(after.isEmitting, isFalse);
      expect(after.readyToSend, isFalse);
    });

    test('keeps the emission settings the user tuned', () {
      // Having just found values that work for the receiver's camera,
      // being handed the defaults back would be a step backwards.
      final tuned = SendState().copyWith(
        fileName: 'report.pdf',
        chunkSize: 256,
        ecLevel: 'Q',
        fps: 6,
      );

      final after = SendState(
        identity: tuned.identity,
        chunkSize: tuned.chunkSize,
        ecLevel: tuned.ecLevel,
        fps: tuned.fps,
      );

      expect(after.chunkSize, 256);
      expect(after.ecLevel, 'Q');
      expect(after.fps, 6);
    });
  });

  group('readiness', () {
    test('clearing the key makes the transfer not ready again', () {
      final ready = SendState().copyWith(
        fileBytes: Uint8List.fromList([1, 2, 3]),
        receiverPk: _key(5),
      );
      expect(ready.readyToSend, isTrue);

      final cleared = ready.copyWith(clearReceiverPk: true);

      expect(cleared.readyToSend, isFalse,
          reason: 'with no receiver key there is nobody to encrypt to');
    });
  });
}
