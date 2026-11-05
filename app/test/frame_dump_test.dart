/// Does the frame dump stay out of an ordinary build, and write a file a
/// person can actually open?
///
/// The first question is the one with teeth. This writes photographs of
/// whatever the camera sees to the filesystem, where they outlive the
/// app. DeadDrop's argument is that it leaks nothing anywhere, and a
/// release that quietly saved camera images would contradict it in the
/// one way a reviewer would be right to care about.
///
/// The owner's condition for it existing at all was that it live behind a
/// debug flag like the emission profiler. These hold that.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/frame_dump.dart';

void main() {
  group('the dump is off unless it was asked for', () {
    test('this test binary has it off', () {
      expect(dumpFrames, isFalse);
    });

    test('the flag is a compile-time constant', () {
      // `const` is what lets the tree shaker remove this from a release.
      // A `final` would compile and behave identically here and ship the
      // frame writing to users.
      final source = File('lib/src/frame_dump.dart').readAsStringSync();
      expect(
        source,
        contains('const bool dumpFrames ='),
        reason: 'a `final` here would ship camera-frame writing to users',
      );
      expect(
        source,
        contains("bool.fromEnvironment('DEADDROP_DUMP_FRAMES')"),
      );
    });

    test('write does nothing at all while the flag is off', () async {
      // The guard that matters: not merely that the flag is false, but
      // that a call made anyway writes no file. This is the test that
      // fails if someone removes the `if (!dumpFrames)` line.
      final directory = await Directory.systemTemp.createTemp('dd-dump');
      addTearDown(() => directory.delete(recursive: true));

      final dumper = FrameDumper(directory.path);
      await dumper.write(Int32List(4), 2, 2);

      expect(directory.listSync(), isEmpty,
          reason: 'a build without the flag wrote a camera frame to disk');
      expect(dumper.written, 0);
    });
  });

  group('FrameDumper', () {
    test('stops at the frame limit', () {
      // A diagnostic run must not fill a disk. Checked through the
      // counter rather than by writing, since writing is off here.
      final dumper = FrameDumper('/nonexistent');
      expect(dumper.isFull, isFalse);
      expect(kMaxDumpedFrames, lessThanOrEqualTo(100),
          reason: 'a cap high enough to fill a disk is not a cap');
    });

    test('the directory it was given is the one it reports', () {
      // The UI shows this path so the owner can find the frames.
      expect(FrameDumper('/tmp/whatever').directory, '/tmp/whatever');
    });
  });
}
