/// Does the emission profiler report the figures it claims to, and does it
/// stay out of an ordinary build?
///
/// The second question is the one with teeth. This instrumentation exists to
/// answer one question on one machine, and the owner's condition for it
/// living in the tree at all is that a normal build does not carry it. A
/// `const bool.fromEnvironment` gives that for free — but only while it
/// stays `const` and the call sites stay behind it, and neither is
/// self-evident to whoever edits this next.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/emission_profile.dart';

void main() {
  group('profiling is off unless it was asked for', () {
    test('this test binary has it off', () {
      // The tests are run without the define, so this is also a check that
      // the define's name has not been mistyped into something that is
      // always false for a different reason.
      expect(profileEmission, isFalse);
    });

    test('the no-QR diagnostic is off too', () {
      // It makes the app unable to transfer, so shipping it enabled
      // would be worse than shipping the overlay.
      expect(profileWithoutQr, isFalse);
    });

    test('the no-QR flag is a compile-time constant', () {
      final source =
          File('lib/src/emission_profile.dart').readAsStringSync();
      expect(source, contains('const bool profileWithoutQr ='),
          reason: 'a `final` here would ship a build that cannot transfer');
      expect(
        source,
        contains("bool.fromEnvironment('DEADDROP_PROFILE_WITHOUT_QR')"),
      );
    });

    test('the flag is a compile-time constant', () {
      // `const` is what lets the tree shaker remove the overlay and the
      // recording from a release build. A `final` would compile and run
      // identically here and ship the instrumentation to users.
      final source =
          File('lib/src/emission_profile.dart').readAsStringSync();
      expect(
        source,
        contains('const bool profileEmission ='),
        reason: 'profileEmission must stay const or the dead code it '
            'guards is no longer dead',
      );
      expect(
        source,
        contains("bool.fromEnvironment('DEADDROP_PROFILE_EMISSION')"),
        reason: 'the define the build passes',
      );
    });

    test('every use in the send page is behind the flag', () {
      // The recording is cheap but not free, and an unguarded call would
      // run in the build users get. Each `profile.` call must sit in a line
      // that tests the flag, or in a block this test can see is guarded.
      final source = File('lib/ui/send/send_page.dart').readAsStringSync();
      final lines = source.split('\n');

      final unguarded = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!RegExp(r'\bprofile\.(recordPrepare|markDraw|recordEngineFrame|summary)')
            .hasMatch(line)) {
          continue;
        }
        // Guarded on its own line, or inside a block opened by a guard in
        // the few lines above it.
        final context = lines.sublist((i - 4).clamp(0, i), i + 1).join('\n');
        if (!context.contains('profileEmission')) unguarded.add(line.trim());
      }

      expect(unguarded, isEmpty,
          reason: 'these record or read timings in builds that did not ask '
              'for profiling');
    });
  });

  group('PhaseTimings', () {
    test('says nothing before it has a sample', () {
      final timings = PhaseTimings();
      expect(timings.medianMillis, isNull);
      expect(timings.worstMillis, isNull);
      expect(timings.count, 0);
    });

    test('reports the median, not the mean', () {
      // The distinction this class exists for. One 2-second stall among
      // four 10 ms frames is a dragged window, not the cost being hunted:
      // the mean would read 507 ms and point at nothing.
      final timings = PhaseTimings();
      for (final ms in [10, 10, 10, 10, 2000]) {
        timings.record(ms * 1000);
      }

      expect(timings.medianMillis, 10.0);
    });

    test('reports the worst sample too', () {
      // Because a median hides exactly the stall above, and a frame rate
      // is set by the slow frames as much as by the typical one.
      final timings = PhaseTimings();
      for (final ms in [10, 10, 10, 10, 2000]) {
        timings.record(ms * 1000);
      }

      expect(timings.worstMillis, 2000.0);
    });

    test('averages the middle two when the count is even', () {
      final timings = PhaseTimings();
      for (final ms in [10, 20, 30, 40]) {
        timings.record(ms * 1000);
      }

      expect(timings.medianMillis, 25.0);
    });

    test('keeps only the most recent window', () {
      final timings = PhaseTimings(window: 3);
      for (final ms in [100, 100, 100, 7, 8, 9]) {
        timings.record(ms * 1000);
      }

      // The three 100s have fallen out; the median is of 7, 8, 9.
      expect(timings.medianMillis, 8.0);
      expect(timings.worstMillis, 9.0);
    });

    test('counts every sample, not just the window', () {
      // So a reader can tell a figure drawn from six frames from one drawn
      // from six hundred.
      final timings = PhaseTimings(window: 3);
      for (var i = 0; i < 10; i++) {
        timings.record(1000);
      }

      expect(timings.count, 10);
    });

    test('ignores a negative sample', () {
      // A clock that steps backwards mid-transfer would otherwise put a
      // negative duration into the median.
      final timings = PhaseTimings();
      timings.record(-5000);

      expect(timings.medianMillis, isNull);
      expect(timings.count, 0);
    });
  });

  group('EmissionProfile', () {
    test('times a draw from the mark to the frame callback', () {
      final profile = EmissionProfile();
      final start = DateTime(2026, 1, 1, 0, 0, 0);

      profile.markDrawStart(at: start);
      profile.markDrawEnd(at: start.add(const Duration(milliseconds: 420)));

      expect(profile.frameGap.medianMillis, 420.0);
    });

    test('a frame callback with no draw outstanding records nothing', () {
      // The send page rebuilds for reasons other than a new code — a
      // window resize, the size advice appearing. Those must not invent a
      // sample, or the median drifts toward whatever a cheap rebuild costs.
      final profile = EmissionProfile();
      final start = DateTime(2026, 1, 1, 0, 0, 0);

      profile.markDrawStart(at: start);
      profile.markDrawEnd(at: start.add(const Duration(milliseconds: 400)));
      // A second frame with no new code behind it.
      profile.markDrawEnd(at: start.add(const Duration(milliseconds: 900)));

      expect(profile.frameGap.count, 1);
      expect(profile.frameGap.medianMillis, 400.0);
    });

    test('keeps prepare and draw apart', () {
      // The whole point: one figure per half, so the ~460 ms can be
      // attributed to one of them.
      final profile = EmissionProfile();
      final start = DateTime(2026, 1, 1, 0, 0, 0);

      profile.recordPrepare(const Duration(milliseconds: 3));
      profile.markDrawStart(at: start);
      profile.markDrawEnd(at: start.add(const Duration(milliseconds: 450)));

      expect(profile.prepare.medianMillis, 3.0);
      expect(profile.frameGap.medianMillis, 450.0);
    });

    test('summary names both halves and their sample counts', () {
      final profile = EmissionProfile();
      final start = DateTime(2026, 1, 1, 0, 0, 0);
      profile.recordPrepare(const Duration(milliseconds: 3));
      profile.markDrawStart(at: start);
      profile.markDrawEnd(at: start.add(const Duration(milliseconds: 450)));

      final summary = profile.summary!;
      expect(summary, contains('prepare 3.0 ms'));
      expect(summary, contains('gap 450.0 ms'));
      expect(summary, contains('n=1'));
    });

    test('summary is null before anything has been measured', () {
      expect(EmissionProfile().summary, isNull);
    });

    test('records the engine figures as separate phases', () {
      // The whole reason this instrumentation was rewritten: build and
      // raster come from the engine, across two threads, and the one that
      // is large says whether the cost is this app or the machine.
      final profile = EmissionProfile();

      profile.recordEngineFrame(
        buildDuration: const Duration(milliseconds: 12),
        rasterDuration: const Duration(milliseconds: 480),
      );

      expect(profile.build.medianMillis, 12.0);
      expect(profile.raster.medianMillis, 480.0);
    });

    test('summary leads with build and raster', () {
      // They are what the next measurement is for. `gap` is kept because
      // the frame period is worth seeing beside them, but it is the figure
      // that misled this investigation for a day and does not lead.
      final profile = EmissionProfile();
      profile.recordEngineFrame(
        buildDuration: const Duration(milliseconds: 12),
        rasterDuration: const Duration(milliseconds: 480),
      );

      final summary = profile.summary!;
      expect(summary, contains('build 12.0 ms'));
      expect(summary, contains('raster 480.0 ms'));
      expect(summary.indexOf('build'), lessThan(summary.indexOf('gap')));
    });

    test('a summary exists from engine frames alone', () {
      // The engine reports frames whether or not a code was published, so
      // the overlay must not stay blank waiting for a gap sample.
      final profile = EmissionProfile();
      profile.recordEngineFrame(
        buildDuration: const Duration(milliseconds: 9),
        rasterDuration: const Duration(milliseconds: 4),
      );

      expect(profile.summary, isNotNull);
    });

    test('reset forgets the engine figures too', () {
      final profile = EmissionProfile();
      profile.recordEngineFrame(
        buildDuration: const Duration(milliseconds: 9),
        rasterDuration: const Duration(milliseconds: 4),
      );

      profile.reset();

      expect(profile.build.count, 0);
      expect(profile.raster.count, 0);
      expect(profile.summary, isNull);
    });

    test('reset forgets the samples and any outstanding draw', () {
      // Called when the frame rate changes, so two rates are not averaged
      // into one figure describing neither.
      final profile = EmissionProfile();
      final start = DateTime(2026, 1, 1, 0, 0, 0);
      profile.recordPrepare(const Duration(milliseconds: 3));
      profile.markDrawStart(at: start);

      profile.reset();
      // The draw that was outstanding must not close against the new run.
      profile.markDrawEnd(at: start.add(const Duration(seconds: 5)));

      expect(profile.summary, isNull);
      expect(profile.frameGap.count, 0);
      expect(profile.prepare.count, 0);
    });
  });
}
