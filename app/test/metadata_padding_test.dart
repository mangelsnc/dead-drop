import 'dart:convert';

import 'package:dead_drop/src/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

/// The module count of the QR a payload of [bytes] plaintext produces,
/// once it has been through the encryption overhead and base64 of a real
/// frame. The exact constant does not matter: both sides of every
/// comparison below carry it.
int _modulesForPayload(int bytes) {
  const frameOverhead = 48;
  final chars = (bytes * 4 / 3).ceil() + frameOverhead;
  return QrImage(
    QrCode.fromData(
      data: 'A' * chars,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  ).moduleCount;
}

void main() {
  group('file metadata payload padding', () {
    test('pads to exactly the requested size', () {
      for (final padTo in [256, 512, 1024]) {
        for (final name in ['a.txt', 'informe-anual-2026.pdf', '']) {
          final payload =
              buildFileMetadataPayload(fileName: name, padTo: padTo);
          expect(
            payload.length,
            padTo,
            reason: 'name "$name" padded to $padTo',
          );
        }
      }
    });

    test('renders at the same QR version as a data frame', () {
      // This is the whole point: an unpadded metadata frame is a much
      // smaller code, and the sender's display flashes every time one
      // goes out.
      for (final chunkSize in [256, 512, 1024]) {
        final padded = buildFileMetadataPayload(
          fileName: 'informe.pdf',
          padTo: chunkSize,
        );
        expect(
          _modulesForPayload(padded.length),
          _modulesForPayload(chunkSize),
          reason: 'a metadata frame at chunk size $chunkSize',
        );
      }
    });

    test('an unpadded payload would not have matched', () {
      // Without this the test above would pass even if padding did
      // nothing, because both sides would be the same small number.
      final bare = buildFileMetadataPayload(fileName: 'informe.pdf');
      expect(
        _modulesForPayload(bare.length),
        lessThan(_modulesForPayload(1024)),
      );
    });

    test('a name too long to pad is still emitted whole', () {
      final longName = '${'n' * 400}.pdf';
      final payload =
          buildFileMetadataPayload(fileName: longName, padTo: 256);
      expect(parseFileMetadataPayload(payload)['name'], longName);
    });

    test('the padding survives a round trip and does not reach the name',
        () {
      for (final padTo in [0, 256, 1024]) {
        final payload = buildFileMetadataPayload(
          fileName: 'informe anual.pdf',
          padTo: padTo,
        );
        final parsed = parseFileMetadataPayload(payload);
        expect(parsed['name'], 'informe anual.pdf');
      }
    });

    test('padding is the only difference from the unpadded document', () {
      final bare = jsonDecode(
        utf8.decode(buildFileMetadataPayload(fileName: 'x.txt')),
      ) as Map<String, dynamic>;
      final padded = jsonDecode(
        utf8.decode(buildFileMetadataPayload(fileName: 'x.txt', padTo: 512)),
      ) as Map<String, dynamic>;
      for (final key in bare.keys) {
        expect(padded[key], bare[key], reason: 'key "$key"');
      }
    });

    test('padTo of zero or less leaves the payload unpadded', () {
      final bare = buildFileMetadataPayload(fileName: 'x.txt');
      expect(buildFileMetadataPayload(fileName: 'x.txt', padTo: 0).length,
          bare.length);
      expect(buildFileMetadataPayload(fileName: 'x.txt', padTo: -5).length,
          bare.length);
    });
  });
}
