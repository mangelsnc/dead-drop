/// Canonical byte encodings of the two wire formats.
///
/// These were produced by this implementation, so they do not prove the
/// encoding is *correct* — they pin it. That is what is needed, because
/// the wire is the one interface this project cannot version-negotiate:
/// a sender and a receiver are two separately installed binaries, often
/// on different platforms and different release dates, and there is no
/// back-channel for them to discover a disagreement. A field that
/// silently moves by one byte produces a transfer that fails with
/// "signature invalid" or decodes into rubbish, on someone else's
/// device, with no way to tell which side is wrong.
///
/// Every byte of each vector was checked by hand against the layout in
/// docs/technical-spec.md §2.2 before being committed: field order,
/// field widths, and big-endian ordering for every multi-byte integer.
///
/// If a refactor changes these values, that is a wire format change. It
/// needs a version bump and a note in the spec, not a regenerated
/// constant.
library;

import 'dart:typed_data';

import 'package:dead_drop/src/crypto.dart';
import 'package:dead_drop/src/qrframe.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bytes `start, start+1, …` truncated to a byte, so every field in a
/// vector is visually distinct and a field swapped with its neighbour
/// shows up as different bytes rather than as the same filler twice.
Uint8List _fill(int n, int start) =>
    Uint8List.fromList(List.generate(n, (i) => (start + i) & 0xff));

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A session header with every field set to a recognisable pattern.
///
/// The integers are deliberately not palindromes and not small: 1000000
/// is `000f4240`, 1954 is `07a2`, 512 is `0200`. Each reads differently
/// byte-swapped, so the vector pins big-endian ordering rather than
/// merely pinning a number.
SessionHeader _referenceHeader() => SessionHeader(
      senderEphPk: _fill(32, 0x01),
      receiverPk: _fill(32, 0x41),
      senderVerifyKey: _fill(32, 0x81),
      fileId: _fill(8, 0xf0),
      totalSize: 1000000,
      chunkCount: 1954,
      chunkSize: 512,
      manifestHash: _fill(32, 0x20),
      signature: _fill(64, 0xc0),
    );

/// The exact 211 bytes [_referenceHeader] must pack to.
const String _headerHex =
    '4444' // MAGIC "DD"
    '03' // VERSION
    '0102030405060708090a0b0c0d0e0f10'
    '1112131415161718191a1b1c1d1e1f20' // SENDER_EPH_PK
    '4142434445464748494a4b4c4d4e4f50'
    '5152535455565758595a5b5c5d5e5f60' // RECEIVER_PK
    '8182838485868788898a8b8c8d8e8f90'
    '9192939495969798999a9b9c9d9e9fa0' // SENDER_VERIFY_KEY
    'f0f1f2f3f4f5f6f7' // FILE_ID
    '000f4240' // TOTAL_SIZE   1000000
    '07a2' // CHUNK_COUNT  1954
    '0200' // CHUNK_SIZE   512
    '202122232425262728292a2b2c2d2e2f'
    '303132333435363738393a3b3c3d3e3f' // MANIFEST_HASH
    'c0c1c2c3c4c5c6c7c8c9cacbcccdcecf'
    'd0d1d2d3d4d5d6d7d8d9dadbdcdddedf'
    'e0e1e2e3e4e5e6e7e8e9eaebecedeeef'
    'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff'; // SIGNATURE

/// A data frame with every field set to a recognisable pattern.
///
/// `seq` 70000 exceeds 16 bits, so a field narrowed to uint16 truncates
/// visibly instead of round-tripping. `seed` is 0x12345678, which is a
/// different number byte-swapped.
Frame _referenceFrame() => Frame(
      fileId: _fill(8, 0xf0),
      seq: 70000,
      seed: 0x12345678,
      degree: 3,
      nonce: _fill(24, 0xa0),
      payload: _fill(48, 0x10),
    );

/// The exact 93 bytes [_referenceFrame] must pack to.
const String _frameHex =
    '4444' // MAGIC "DD"
    '03' // VERSION
    'f0f1f2f3f4f5f6f7' // FILE_ID
    '00011170' // SEQ    70000
    '12345678' // SEED
    '0003' // DEGREE 3
    'a0a1a2a3a4a5a6a7a8a9aaabacadaeaf'
    'b0b1b2b3b4b5b6b7' // NONCE
    '101112131415161718191a1b1c1d1e1f'
    '202122232425262728292a2b2c2d2e2f'
    '303132333435363738393a3b3c3d3e3f'; // CIPHERTEXT + TAG

void main() {
  group('session header', () {
    test('packs to its pinned bytes', () {
      expect(_hex(_referenceHeader().pack()), _headerHex);
    });

    test('is 211 bytes, and the constant agrees', () {
      // Both, because packedSize is what callers size buffers and QR
      // versions against: a pack() that wrote the right bytes while
      // packedSize disagreed would pick the wrong QR version.
      expect(_referenceHeader().pack().length, 211);
      expect(SessionHeader.packedSize, 211);
    });

    test('unpacking the pinned bytes recovers every field', () {
      // The reverse direction, against the literal rather than against
      // pack(): a pack/unpack pair that agreed with each other and with
      // nothing else would satisfy a round-trip test.
      final header = SessionHeader.unpack(
        Uint8List.fromList([
          for (var i = 0; i < _headerHex.length; i += 2)
            int.parse(_headerHex.substring(i, i + 2), radix: 16),
        ]),
      );

      expect(_hex(header.senderEphPk), _hex(_fill(32, 0x01)));
      expect(_hex(header.receiverPk), _hex(_fill(32, 0x41)));
      expect(_hex(header.senderVerifyKey), _hex(_fill(32, 0x81)));
      expect(_hex(header.fileId), 'f0f1f2f3f4f5f6f7');
      expect(header.totalSize, 1000000);
      expect(header.chunkCount, 1954);
      expect(header.chunkSize, 512);
      expect(_hex(header.manifestHash), _hex(_fill(32, 0x20)));
      expect(_hex(header.signature), _hex(_fill(64, 0xc0)));
    });

    test('the signature covers everything except the signature', () {
      // The field the signature does NOT cover is itself, and nothing
      // else. If a field were ever appended after the signature it
      // would travel unauthenticated, which is the bug this pins.
      final header = _referenceHeader();
      final signed = header.signedPayload();

      expect(signed.length, 147);
      expect(signed.length, SessionHeader.packedSize - 64);
      expect(_hex(signed), _headerHex.substring(0, 147 * 2));
    });
  });

  group('data frame', () {
    test('packs to its pinned bytes', () {
      expect(_hex(_referenceFrame().pack()), _frameHex);
    });

    test('the header is 21 bytes before nonce and payload', () {
      expect(frameHeaderSize, 21);
      expect(_referenceFrame().pack().length, 21 + 24 + 48);
    });

    test('unpacking the pinned bytes recovers every field', () {
      final frame = Frame.unpack(
        Uint8List.fromList([
          for (var i = 0; i < _frameHex.length; i += 2)
            int.parse(_frameHex.substring(i, i + 2), radix: 16),
        ]),
      );

      expect(_hex(frame.fileId), 'f0f1f2f3f4f5f6f7');
      expect(frame.seq, 70000,
          reason: 'seq exceeds 16 bits; a narrowed field truncates here');
      expect(frame.seed, 0x12345678);
      expect(frame.degree, 3);
      expect(_hex(frame.nonce), _hex(_fill(24, 0xa0)));
      expect(_hex(frame.payload), _hex(_fill(48, 0x10)));
    });

    test('degree 0 is what marks a metadata frame', () {
      // The one field whose value carries meaning rather than data, and
      // the only thing distinguishing the metadata frame on the wire.
      expect(_referenceFrame().isMetadata, isFalse);
      expect(
        Frame(
          fileId: _fill(8, 0xf0),
          seq: 0,
          seed: 0x12345678,
          degree: 0,
          nonce: _fill(24, 0xa0),
          payload: _fill(48, 0x10),
        ).isMetadata,
        isTrue,
      );
    });
  });

  group('what both formats share', () {
    test('magic and version are the same two constants', () {
      // A receiver tells the two apart by length and context, not by a
      // type byte, so the shared prefix has to stay shared.
      expect(magic, [0x44, 0x44]);
      expect(version, 3);
      expect(_headerHex.startsWith('444403'), isTrue);
      expect(_frameHex.startsWith('444403'), isTrue);
    });

    test('the vectors are not degenerate', () {
      // Guards the vectors themselves: all-zero or all-identical bytes
      // would satisfy every test above while pinning nothing about
      // field order. Each format must contain many distinct byte
      // values, and the two must not be the same string.
      expect(_headerHex.length, 211 * 2);
      expect(_frameHex.length, 93 * 2);
      expect(_headerHex, isNot(_frameHex));

      for (final (name, hex) in [
        ('header', _headerHex),
        ('frame', _frameHex),
      ]) {
        final bytes = [
          for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
        ];
        expect(bytes.toSet().length, greaterThan(32),
            reason: '$name vector must not be filler');
      }
    });
  });
}
