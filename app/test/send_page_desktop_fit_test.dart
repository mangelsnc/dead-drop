/// Does the send page fit a desktop window without scrolling?
/// (issue #69, app/lib/ui/send/send_page.dart)
///
/// The layout tests in responsive_layout_test.dart prove the mechanism.
/// This one proves the thing actually reported: at the default size of the
/// Linux and Windows runners (1280x720), "Send a file" required vertical
/// scrolling while most of the window sat empty.
///
/// Asserting on the scroll extent rather than on widget positions means
/// this keeps working as the page's content changes — it fails when the
/// page stops fitting, for whatever reason, which is the actual regression.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/send/send_page.dart';
import 'package:dead_drop/ui/theme.dart';


/// Logical size of a Linux/Windows window at its default
/// (see app/linux/my_application.cc: gtk_window_set_default_size).
const _desktopWindow = Size(1280, 720);

/// A phone, for the contrast case.
const _phoneWindow = Size(400, 800);

Future<void> _pumpSendPage(
  WidgetTester tester,
  SodiumSumo sodium,
  Size size,
) async {
  tester.view.physicalSize = size;
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
  // running animation (the identity card's loading indicator), so settling
  // never completes. Two frames is enough for the layout to resolve, which
  // is all this test measures.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// How far the page can be scrolled. Zero means everything fits.
double _scrollExtent(WidgetTester tester) {
  final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
  return scrollable.controller?.position.maxScrollExtent ??
      Scrollable.of(
        tester.element(find.byType(Scrollable).first),
      ).position.maxScrollExtent;
}

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  testWidgets('fits a 1280x720 desktop window without scrolling',
      (tester) async {
    await _pumpSendPage(tester, sodium, _desktopWindow);

    expect(
      _scrollExtent(tester),
      0,
      reason: 'issue #69: the send page required scrolling in a desktop '
          'window while two thirds of it sat empty. If this fails, the '
          'page has grown past the window again — either trim it or move '
          'something into the second column.',
    );
  });

  testWidgets('still renders on a phone, where scrolling is expected',
      (tester) async {
    // The contrast case: the fix must not be "make everything smaller".
    // A phone legitimately scrolls; what matters is that the page builds
    // and overflows nothing horizontally.
    await _pumpSendPage(tester, sodium, _phoneWindow);

    expect(tester.takeException(), isNull);
    expect(find.text('Choose a file'), findsOneWidget);
  });
}
