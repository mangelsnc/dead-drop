/// The three transfer settings explain themselves.
///
/// Chunk size, frame rate and error correction decide whether a transfer
/// reads at all, and they are what a user is told to change when one is
/// not reading. A control you are told to adjust but cannot understand
/// is guesswork, so each carries an (i).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/info_point.dart';
import 'package:dead_drop/ui/send/send_page.dart';
import 'package:dead_drop/ui/theme.dart';

Future<void> _pumpSendPage(WidgetTester tester, SodiumSumo sodium) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sodiumProvider.overrideWithValue(sodium)],
      child: MaterialApp(
        theme: deadDropTheme(),
        home: const SendPage(),
      ),
    ),
  );
  // Fixed pumps rather than pumpAndSettle: the page holds a continuously
  // running animation, so settling never completes.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Open the collapsed Options section, where the three settings live.
Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.text('Options'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  testWidgets('each of the three settings carries an info point',
      (tester) async {
    await _pumpSendPage(tester, sodium);
    await _openOptions(tester);

    for (final title in const [
      'Chunk size',
      'Frame rate',
      'Error correction',
    ]) {
      expect(
        find.byWidgetPredicate(
          (w) => w is InfoPoint && w.title == title,
        ),
        findsOneWidget,
        reason: '"$title" is a setting a user is told to change when a '
            'transfer is not reading, so it must explain itself',
      );
    }
  });

  testWidgets('an info point opens an explanation and closes again',
      (tester) async {
    await _pumpSendPage(tester, sodium);
    await _openOptions(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is InfoPoint && w.title == 'Frame rate',
      ),
    );
    // Fixed pumps, not pumpAndSettle: the page holds a continuously
    // running animation, so settling never completes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The dialog says what the setting does, not just its name.
    expect(find.text(SettingHelp.frameRate), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(SettingHelp.frameRate), findsNothing);
  });

  testWidgets('the error correction selector leaves no room for a checkmark',
      (tester) async {
    // Reported from a phone: the selected segment reserved space for a
    // tick, which took enough width from the label that "M (15%)"
    // wrapped onto three lines and that segment grew to twice the
    // height of its neighbours. The fill already shows which is
    // selected.
    await _pumpSendPage(tester, sodium);
    await _openOptions(tester);

    final selectors = tester
        .widgetList<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>),
        )
        .toList();
    expect(selectors, hasLength(1));
    expect(selectors.single.showSelectedIcon, isFalse);

    // And the labels are short enough to sit on one line each, which is
    // what the stacked layout buys. "M (15%)" on a single line is what
    // did not fit.
    for (final level in const ['L', 'M', 'Q', 'H']) {
      expect(find.text(level), findsOneWidget, reason: level);
    }
    for (final pct in const ['(7%)', '(15%)', '(25%)', '(30%)']) {
      expect(find.text(pct), findsOneWidget, reason: pct);
    }
    expect(find.text('M (15%)'), findsNothing,
        reason: 'the single-line label is what overflowed');
  });

  testWidgets('the selector fills the row on a desktop window',
      (tester) async {
    // Reported from macOS: the four levels huddled into a small block
    // at the left of a wide row, because a SegmentedButton sizes itself
    // to its content.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sodiumProvider.overrideWithValue(sodium)],
        child: MaterialApp(
          theme: deadDropTheme(),
          home: const SendPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _openOptions(tester);

    final selector = find.byType(SegmentedButton<String>);
    expect(selector, findsOneWidget);

    // It should span most of the column it sits in, rather than
    // shrinking to the width of its text.
    final selectorWidth = tester.getSize(selector).width;
    final columnWidth = tester.getSize(find.text('Error correction')).width;
    expect(selectorWidth, greaterThan(columnWidth * 2),
        reason: 'the selector shrank back to its content width');
  });

  group('the help text earns its place', () {
    test('each one explains, rather than restating the label', () {
      // A help text that says "the frame rate is the rate of frames"
      // would satisfy a test that only checked a dialog appears.
      for (final (label, body) in const [
        ('Chunk size', SettingHelp.chunkSize),
        ('Frame rate', SettingHelp.frameRate),
        ('Error correction', SettingHelp.errorCorrection),
      ]) {
        expect(body.length, greaterThan(200), reason: label);
        // Says which way to move it when something is wrong.
        expect(
          RegExp(r'\b(smaller|lower|higher|move up)\b', caseSensitive: false)
              .hasMatch(body),
          isTrue,
          reason: '$label does not say which way to move it',
        );
      }
    });

    test('they are three distinct explanations', () {
      final bodies = {
        SettingHelp.chunkSize,
        SettingHelp.frameRate,
        SettingHelp.errorCorrection,
      };
      expect(bodies.length, 3);
    });
  });
}
