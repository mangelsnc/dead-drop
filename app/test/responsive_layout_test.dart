/// Tests for the shared phone/desktop layout rules
/// (app/lib/ui/responsive.dart).
///
/// The property that matters is not "two columns appear on a desktop" — it
/// is that **the narrow layout is never a reduced version of the wide one**.
/// A responsive layout that quietly drops a control below some width is a
/// worse bug than one that scrolls, because nothing tells the user the
/// control exists. These tests pin that both layouts render the same
/// widgets, and that reading order is preserved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/responsive.dart';

/// Pumps [child] at a given logical window size.
Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

const _phone = Size(400, 800);
const _desktop = Size(1280, 720);

void main() {
  group('TwoColumnLayout', () {
    const layout = TwoColumnLayout(
      start: [Text('alpha'), Text('beta')],
      end: [Text('gamma')],
    );

    testWidgets('narrow: every child is still rendered', (tester) async {
      await _pumpAt(tester, _phone, layout);

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget,
          reason: 'the end column must not vanish on a phone — a control '
              'the user cannot see is worse than one they must scroll to');
    });

    testWidgets('wide: every child is still rendered', (tester) async {
      await _pumpAt(tester, _desktop, layout);

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('gamma'), findsOneWidget);
    });

    testWidgets('narrow stacks; wide puts the columns side by side',
        (tester) async {
      await _pumpAt(tester, _phone, layout);
      final narrowAlpha = tester.getTopLeft(find.text('alpha'));
      final narrowGamma = tester.getTopLeft(find.text('gamma'));
      expect(narrowGamma.dy, greaterThan(narrowAlpha.dy),
          reason: 'stacked: end comes below start');
      expect(narrowGamma.dx, equals(narrowAlpha.dx),
          reason: 'stacked: both at the same x');

      await _pumpAt(tester, _desktop, layout);
      final wideAlpha = tester.getTopLeft(find.text('alpha'));
      final wideGamma = tester.getTopLeft(find.text('gamma'));
      expect(wideGamma.dx, greaterThan(wideAlpha.dx),
          reason: 'side by side: end is to the right of start');
      expect(wideGamma.dy, equals(wideAlpha.dy),
          reason: 'side by side: both columns start at the same height');
    });

    testWidgets('narrow preserves reading order: start before end',
        (tester) async {
      await _pumpAt(tester, _phone, layout);

      final beta = tester.getTopLeft(find.text('beta')).dy;
      final gamma = tester.getTopLeft(find.text('gamma')).dy;

      expect(gamma, greaterThan(beta),
          reason: 'the whole start column comes before the end column');
    });
  });

  group('the breakpoint', () {
    testWidgets('a 1280x720 desktop window gets the wide layout',
        (tester) async {
      // The default size of the Linux and Windows runners. The layout must
      // be wide there without the user resizing anything.
      late bool wide;
      await _pumpAt(
        tester,
        _desktop,
        Builder(builder: (context) {
          wide = isWideLayout(context);
          return const SizedBox();
        }),
      );
      expect(wide, isTrue);
    });

    testWidgets('a large phone in landscape stays narrow', (tester) async {
      // 892 logical px is a Pixel 8 Pro in landscape — still a phone, and
      // it must not get a two-column layout.
      late bool wide;
      await _pumpAt(
        tester,
        const Size(892, 412),
        Builder(builder: (context) {
          wide = isWideLayout(context);
          return const SizedBox();
        }),
      );
      expect(wide, isFalse);
    });

    testWidgets('exactly at the breakpoint counts as wide', (tester) async {
      late bool wide;
      await _pumpAt(
        tester,
        const Size(kWideLayoutBreakpoint, 700),
        Builder(builder: (context) {
          wide = isWideLayout(context);
          return const SizedBox();
        }),
      );
      expect(wide, isTrue, reason: 'the breakpoint is inclusive');
    });
  });

  group('ContentWidthLimit', () {
    testWidgets('does not stretch content across a very wide window',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(2560, 1440),
        const ContentWidthLimit(child: SizedBox(height: 10)),
      );

      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.width, lessThanOrEqualTo(kMaxContentWidth),
          reason: 'a maximised window must not stretch controls across the '
              'whole screen');
    });

    testWidgets('leaves a narrow window alone', (tester) async {
      await _pumpAt(
        tester,
        _phone,
        const ContentWidthLimit(child: SizedBox(height: 10)),
      );

      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.width, lessThanOrEqualTo(_phone.width),
          reason: 'no horizontal overflow on a phone');
    });
  });
}
