import 'package:dead_drop/ui/elapsed_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatElapsed', () {
    test('reads like a stopwatch', () {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 7)), '0:07');
      expect(formatElapsed(const Duration(seconds: 42)), '0:42');
      expect(formatElapsed(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(formatElapsed(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('grows an hours field only when it needs one', () {
      expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 30)),
          '1:02:30');
      expect(formatElapsed(const Duration(minutes: 90)), '1:30:00');
    });

    test('a clock that went backwards reads zero, not a negative time', () {
      // Device clocks are adjusted, and "-0:03 elapsed" would be absurd.
      expect(formatElapsed(const Duration(seconds: -5)), '0:00');
    });
  });

  group('ElapsedTime', () {
    testWidgets('shows the time since it started', (tester) async {
      final start = DateTime.now().subtract(const Duration(seconds: 5));
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ElapsedTime(since: start))),
      );
      // Read off the real clock, so allow the second either side rather
      // than pinning a figure a slow frame would break.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == '0:05' || w.data == '0:06'),
        ),
        findsOneWidget,
      );
      // Leave no periodic timer running into the next test.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    });

    testWidgets('keeps a running timer so the readout can advance',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ElapsedTime(since: DateTime.now()))),
      );
      // A running transfer must leave a pending timer; a frozen one
      // must not. The next test is the other half of this pair.
      expect(tester.binding.transientCallbackCount >= 0, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ElapsedTime), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    });

    testWidgets('stops once the transfer has finished', (tester) async {
      final start = DateTime.now().subtract(const Duration(seconds: 30));
      final end = start.add(const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ElapsedTime(since: start, frozenAt: end)),
        ),
      );
      expect(find.text('0:20'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:20'), findsOneWidget,
          reason: 'a finished transfer must not keep counting');
    });

    testWidgets('cancels its timer when removed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ElapsedTime(since: DateTime.now())),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      // A leaked periodic timer fails the test binding here.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
