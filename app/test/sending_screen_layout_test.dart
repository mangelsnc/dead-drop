/// Does the sending screen line up with the code it exists to show?
///
/// On a maximised 24-inch monitor the column was the width of the
/// window, so the file name sat in one far corner, its size in the
/// other, and the controls floated under a code they had no visual
/// relationship to. The code is the object of this screen; it sets the
/// measure and everything else is a caption to it.
///
/// These pin the parts that were got wrong twice by eye: that the block
/// is no wider than the code, and that the three actions are told apart
/// by weight rather than by size.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/theme.dart';

/// The source of the sending screen. Part of what this pins is which
/// widget was chosen and what colour it carries, which no rendered
/// frame reports — the same source-inspection pattern already used for
/// the receive page's trust prompt.
final String _source =
    File('lib/ui/send/send_page.dart').readAsStringSync();

void main() {
  group('the three transfer actions are ranked, not sized', () {
    test('Stop is filled, Restart and New transfer are outlined', () {
      final body = _sendingScreenSource();

      expect(body, contains('FilledButton.icon'),
          reason: 'Stop is the action being reached for, so it carries '
              'the weight');
      expect('OutlinedButton.icon'.allMatches(body).length, 2,
          reason: 'Restart and New transfer both carry an outline; a '
              'bare TextButton on the page background did not read as '
              'a button at all');
    });

    test('New transfer is told apart by colour, not by being smaller', () {
      // Reported twice: with Restart's own outline the two read as a
      // pair, though one retunes and keeps the file and the key while
      // the other throws both away.
      final body = _sendingScreenSource();
      // The whole SizedBox wrapping it: the width is set before the
      // label and the colour after.
      final from = body.lastIndexOf('SizedBox(', body.indexOf("'New transfer'"));
      final newTransfer = body.substring(from);

      expect(newTransfer, contains('DeadDropColors.accent'),
          reason: 'the accent is what separates it from Restart');
      expect(newTransfer.substring(0, newTransfer.indexOf("'New transfer'")),
          contains('width: double.infinity'),
          reason: 'it takes the full measure rather than a third of it');
    });

    test('every control is big enough to hit', () {
      // 56 and 52 were 44 and 48 at various points, which on a 24-inch
      // monitor read as small.
      final body = _sendingScreenSource();
      final sizes = RegExp(r'Size\(0, (\d+)\)')
          .allMatches(body)
          .map((m) => int.parse(m.group(1)!))
          .toList();

      expect(sizes, isNotEmpty, reason: 'the controls set a minimum size');
      expect(sizes.every((h) => h >= 48), isTrue,
          reason: '44 is the floor for a touch target and reads small on '
              'a desktop monitor; these were measured at $sizes');
    });
  });

  group('everything lines up with the code', () {
    test('the block is capped at the width the QR was given', () {
      final body = _sendingScreenSource();

      expect(body, contains('state.qrDisplaySizePx > 0'),
          reason: 'the measure comes from what _QrDisplay reported, not '
              'from a constant: a guessed constant for this screen was '
              'already wrong by 300 pixels once');
      expect(body, contains('maxWidth: state.qrDisplaySizePx'),
          reason: 'the column is no wider than the code, so the file '
              'name cannot sit in a far corner of a 24-inch monitor');
    });

    test('the old full-width furniture is gone', () {
      final body = _sendingScreenSource();

      expect(body.contains('kTransferControlsMaxWidth'), isFalse,
          reason: 'the controls are measured against the code now, not '
              'against a fixed 460 pixels that ignored it');
    });
  });

  test('the colours used are the theme\'s, not invented', () {
    // Cheap guard: the accent has to exist and differ from the error
    // colour, or "a different colour" is not actually different.
    expect(DeadDropColors.accent, isNot(DeadDropColors.error));
    expect(DeadDropColors.accent, isNot(DeadDropColors.textSecondary));
  });
}

/// The `_SendingScreen` class body.
String _sendingScreenSource() {
  final start = _source.indexOf('class _SendingScreen');
  expect(start, greaterThan(-1), reason: '_SendingScreen was renamed');
  final end = _source.indexOf('class _ParamSlider', start);
  expect(end, greaterThan(start), reason: '_ParamSlider was renamed');
  return _source.substring(start, end);
}
