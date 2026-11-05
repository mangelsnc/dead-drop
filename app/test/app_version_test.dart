import 'package:dead_drop/src/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatVersionLabel', () {
    test('shows the version, build number and commit of a real build', () {
      expect(
        formatVersionLabel(
          version: '0.9.1',
          buildNumber: '162',
          commit: '3024b01',
        ),
        'Version 0.9.1 (162) · 3024b01',
      );
    });

    test('drops the parts a build does not have', () {
      expect(
        formatVersionLabel(version: '0.9.1', buildNumber: '', commit: ''),
        'Version 0.9.1',
      );
      expect(
        formatVersionLabel(
            version: '0.9.1', buildNumber: '162', commit: ''),
        'Version 0.9.1 (162)',
      );
    });

    test('says so rather than going blank when nothing was injected', () {
      // A `flutter run` from a checkout. Someone reporting a problem has
      // to be able to tell us which build they are holding, and an empty
      // About cannot do that — so this says what it is.
      expect(
        formatVersionLabel(version: '', buildNumber: '', commit: ''),
        'Development build',
      );
    });

    test('never prints the word Version without a number after it', () {
      // The failure this guards is "Version " or "Version  ()" leaking
      // out of a partially-injected build.
      for (final label in [
        formatVersionLabel(version: '', buildNumber: '162', commit: 'abc'),
        formatVersionLabel(version: '', buildNumber: '', commit: 'abc'),
      ]) {
        expect(label.startsWith('Version'), isFalse, reason: label);
        expect(label, 'Development build');
      }
    });

    test('the label this binary was built with is never empty', () {
      // Whichever way the suite is invoked, with defines or without.
      expect(appVersionLabel, isNotEmpty);
    });
  });
}
