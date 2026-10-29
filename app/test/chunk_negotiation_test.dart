/// A transfer runs at what both ends can manage, not just what the
/// receiver asked for.
///
/// The receiver's hint is measured from its camera and knows nothing
/// about the sender's screen. The UI stops a user picking an
/// unrenderable combination, but the hint is applied without passing
/// through it — so an automatic setting could ask a phone for a chunk
/// size it has no pixels to draw. Reported after a Redmi Note 14
/// transferred nothing in three minutes at 512 bytes and finished in
/// one at 256.
library;

import 'package:dead_drop/ui/send/send_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// The QR size a Redmi Note 14 has for the code, and a desktop window.
const _phone = 345.0;
const _desktop = 700.0;

void main() {
  group('largestDisplayableChunk', () {
    test('a phone cannot offer what a desktop can', () {
      final onPhone =
          largestDisplayableChunk(displaySize: _phone, ecLevel: 'M');
      final onDesktop =
          largestDisplayableChunk(displaySize: _desktop, ecLevel: 'M');
      expect(onPhone, lessThan(onDesktop!));
      // The measured case: 512 produced 3.29 px/module and did not
      // transfer; 256 produced 4.26 and did.
      expect(onPhone, 256);
    });

    test('a stronger error correction lowers what fits', () {
      // Stronger correction spends more modules on the same payload, so
      // the same screen can show less. On this phone level H leaves
      // nothing showable at all — which is worth knowing, because the
      // receiver can ask for H.
      expect(largestDisplayableChunk(displaySize: _phone, ecLevel: 'L'), 256);
      expect(largestDisplayableChunk(displaySize: _phone, ecLevel: 'M'), 256);
      // Q and H leave this phone nothing it can show at all, which
      // matters because the receiver's hint can ask for either.
      expect(largestDisplayableChunk(displaySize: _phone, ecLevel: 'Q'),
          isNull);
      expect(largestDisplayableChunk(displaySize: _phone, ecLevel: 'H'),
          isNull);
    });

    test('a desktop screen can show every level', () {
      expect(largestDisplayableChunk(displaySize: _desktop, ecLevel: 'L'),
          1024);
      expect(largestDisplayableChunk(displaySize: _desktop, ecLevel: 'Q'),
          1024);
      // Even H, which costs this screen a step down rather than
      // everything.
      expect(largestDisplayableChunk(displaySize: _desktop, ecLevel: 'H'),
          512);
    });

    test('a screen with no room for any size says so', () {
      expect(largestDisplayableChunk(displaySize: 40, ecLevel: 'M'), isNull);
    });
  });

  group('negotiateChunkSize', () {
    test('caps the receiver request at what this screen can draw', () {
      // The reported hazard: the receiver asks for 1024 and the sender
      // can only show 256.
      expect(
        negotiateChunkSize(
          requested: 1024,
          displaySize: _phone,
          ecLevel: 'M',
        ),
        256,
      );
    });

    test('never raises what the receiver asked for', () {
      // The receiver knows its own camera; a bigger code is not a
      // favour. A desktop could draw 1024 and must still send 256.
      expect(
        negotiateChunkSize(
          requested: 256,
          displaySize: _desktop,
          ecLevel: 'M',
        ),
        256,
      );
    });

    test('leaves a request this screen can meet alone', () {
      expect(
        negotiateChunkSize(
          requested: 512,
          displaySize: _desktop,
          ecLevel: 'M',
        ),
        512,
      );
    });

    test('lets an impossible screen try rather than refusing', () {
      // Nothing fits. Honour the request: the send screen warns, and a
      // transfer the user can attempt beats one the app declines.
      expect(
        negotiateChunkSize(requested: 512, displaySize: 40, ecLevel: 'M'),
        512,
      );
    });
  });

  group('negotiateSettings', () {
    test('weakens the error correction when no chunk fits at the one '
        'asked for', () {
      // The reported case exactly: the handshake asked for Q, and this
      // phone cannot legibly show any chunk size at Q. Capping only the
      // chunk size would have left it at Q and still unreadable.
      final r = negotiateSettings(
        requestedChunkSize: 512,
        requestedEcLevel: 'Q',
        displaySize: _phone,
      );
      expect(r.ecLevel, 'M');
      expect(r.chunkSize, 256);
    });

    test('leaves a request this screen can meet alone', () {
      final r = negotiateSettings(
        requestedChunkSize: 512,
        requestedEcLevel: 'Q',
        displaySize: _desktop,
      );
      expect(r.ecLevel, 'Q');
      expect(r.chunkSize, 512);
    });

    test('never strengthens the error correction', () {
      // The receiver asked for L because its camera is fine; giving it
      // H would cost data room for no reason.
      final r = negotiateSettings(
        requestedChunkSize: 256,
        requestedEcLevel: 'L',
        displaySize: _desktop,
      );
      expect(r.ecLevel, 'L');
    });

    test('never raises the chunk size', () {
      final r = negotiateSettings(
        requestedChunkSize: 256,
        requestedEcLevel: 'M',
        displaySize: _desktop,
      );
      expect(r.chunkSize, 256);
    });

    test('whatever it returns, this screen can show it', () {
      // The property that matters, over every combination rather than
      // the ones that happened to be reported.
      for (final display in [345.0, 500.0, 700.0]) {
        for (final chunk in [256, 512, 1024]) {
          for (final ec in const ['L', 'M', 'Q', 'H']) {
            final r = negotiateSettings(
              requestedChunkSize: chunk,
              requestedEcLevel: ec,
              displaySize: display,
            );
            final density = pixelsPerModuleOnScreen(
              displaySize: display,
              chunkSize: r.chunkSize,
              ecLevel: r.ecLevel,
            );
            // Unless nothing at all fits, in which case the request
            // stands and the screen warns.
            final anyFits = const ['H', 'Q', 'M', 'L']
                .skip(const ['H', 'Q', 'M', 'L'].indexOf(ec))
                .any((l) =>
                    largestDisplayableChunk(
                        displaySize: display, ecLevel: l) !=
                    null);
            if (anyFits) {
              expect(density, greaterThanOrEqualTo(kMinUsablePixelsPerModule),
                  reason: 'asked $chunk/$ec on a ${display}px screen, '
                      'got ${r.chunkSize}/${r.ecLevel}');
            }
          }
        }
      }
    });
  });

  group('chunkUnlockedByABiggerWindow', () {
    test('a small window is told what a big one would allow', () {
      // The reported case: a MacBook with a small window negotiated
      // itself down to 256-byte chunks and spent about 5,000 codes on a
      // 1 MB file, where 1024 would have taken 1,250.
      expect(
        chunkUnlockedByABiggerWindow(
          currentSize: 300,
          currentChunk: 256,
          ecLevel: 'M',
        ),
        1024,
      );
    });

    test('says nothing when the window is already big enough', () {
      expect(
        chunkUnlockedByABiggerWindow(
          currentSize: kQrMaxDisplaySize,
          currentChunk: 1024,
          ecLevel: 'M',
        ),
        isNull,
      );
    });

    test('says nothing when the chunk is already the best available', () {
      // Nagging about a window that would change nothing is noise.
      expect(
        chunkUnlockedByABiggerWindow(
          currentSize: 600,
          currentChunk: 1024,
          ecLevel: 'M',
        ),
        isNull,
      );
    });

    test('never suggests something the bigger window could not show', () {
      for (final ec in const ['L', 'M', 'Q', 'H']) {
        final suggestion = chunkUnlockedByABiggerWindow(
          currentSize: 300,
          currentChunk: 256,
          ecLevel: ec,
        );
        if (suggestion == null) continue;
        expect(
          pixelsPerModuleOnScreen(
            displaySize: kQrMaxDisplaySize,
            chunkSize: suggestion,
            ecLevel: ec,
          ),
          greaterThanOrEqualTo(kMinUsablePixelsPerModule),
          reason: 'suggested $suggestion at level $ec',
        );
      }
    });
  });

  group('qrSizeAdvice', () {
    test('warns when the window cannot show the chunk', () {
      final advice = qrSizeAdvice(
        displaySize: 200,
        chunkSize: 512,
        ecLevel: 'L',
      );
      expect(advice, isNotNull);
      expect(advice!.isProblem, isTrue);
      expect(advice.text, contains('512'));
    });

    test('suggests a bigger window when that would help', () {
      final advice = qrSizeAdvice(
        displaySize: 420,
        chunkSize: 256,
        ecLevel: 'L',
      );
      expect(advice, isNotNull);
      expect(advice!.isProblem, isFalse);
      expect(advice.text, contains('larger window'));
    });

    test('says nothing when the window is already right', () {
      expect(
        qrSizeAdvice(
          displaySize: kQrMaxDisplaySize,
          chunkSize: 1024,
          ecLevel: 'L',
        ),
        isNull,
      );
    });

    test('never gives both messages at once', () {
      // The two advisories this replaced could appear together and
      // contradict each other: "a larger window would fit 2048 bytes"
      // above "this screen is too small for 512". They are the same
      // question, so there is one answer.
      for (final size in [120.0, 200.0, 300.0, 420.0, 600.0, 720.0]) {
        for (final chunk in [256, 512, 1024]) {
          final advice =
              qrSizeAdvice(displaySize: size, chunkSize: chunk, ecLevel: 'L');
          if (advice == null) continue;
          // A problem message must never also offer a bigger window as
          // if the current size were fine.
          if (advice.isProblem) {
            expect(advice.text, contains('too small'),
                reason: '${size}px / $chunk B');
          } else {
            expect(advice.text, isNot(contains('too small')),
                reason: '${size}px / $chunk B');
          }
        }
      }
    });
  });
}
