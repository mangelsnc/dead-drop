/// The application's version, as shown in Settings → About.
///
/// Injected at build time with `--dart-define`, rather than read from the
/// bundle at run time. The obvious package for the latter,
/// `package_info_plus`, depends on `http`: this branch exists to remove
/// the last transitive network dependency from the app, and a tool that
/// claims to work without a network should not ship an HTTP client to
/// print its own version number.
///
/// `tool/build_args.sh` derives the values from `pubspec.yaml`, which
/// stays the single source of truth.
library;

/// The semantic version, e.g. `0.9.1`.
///
/// Empty when the app was built without the define — a `flutter run` from
/// a checkout, typically. [appVersionLabel] is what the UI should show;
/// it handles that case.
const String appVersion = String.fromEnvironment('DEADDROP_VERSION');

/// The build number, e.g. `162`. Empty under the same conditions as
/// [appVersion].
const String appBuildNumber =
    String.fromEnvironment('DEADDROP_BUILD_NUMBER');

/// The short commit the build came from, e.g. `ebbf57f`. Empty when not
/// built from a git checkout, and empty under the same conditions as
/// [appVersion].
const String appCommit = String.fromEnvironment('DEADDROP_COMMIT');

/// What Settings → About displays.
///
/// A development build says so rather than showing a blank or a made-up
/// number: someone reporting a problem needs to be able to tell us which
/// build they are holding, and "no version" is itself that answer.
String get appVersionLabel => formatVersionLabel(
      version: appVersion,
      buildNumber: appBuildNumber,
      commit: appCommit,
    );

/// The formatting behind [appVersionLabel], separated so it can be tested
/// at values other than the ones this binary happens to be built with.
/// A test that could only read the compiled-in constants would be unable
/// to check the case that actually ships.
String formatVersionLabel({
  required String version,
  required String buildNumber,
  required String commit,
}) {
  if (version.isEmpty) return 'Development build';
  final buildPart = buildNumber.isEmpty ? '' : ' ($buildNumber)';
  final commitPart = commit.isEmpty ? '' : ' · $commit';
  return 'Version $version$buildPart$commitPart';
}
