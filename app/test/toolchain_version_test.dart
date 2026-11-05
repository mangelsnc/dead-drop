/// Does every file that names the Flutter version name the same one?
///
/// `.fvmrc` is the single source of truth. The Makefile reads it, so those
/// two cannot drift. Everything else repeats the number by hand, and one of
/// them already drifted: `docker-compose.yml` sat on 3.24.5 for the six days
/// after the toolchain moved to 3.47.8, because the commit that bumped
/// `.fvmrc` did not touch it. Anyone building through compose got a Flutter
/// two years older than the one CI uses, with no warning.
///
/// A comment asking people to keep these in step is what was there before.
/// This is the test that holds the claim instead.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The repository root, from `app/` where the suite runs.
final Directory _repo = Directory('..');

String _read(String relativePath) {
  final file = File('${_repo.path}/$relativePath');
  expect(file.existsSync(), isTrue,
      reason: '$relativePath is missing; this test pins its contents');
  return file.readAsStringSync();
}

/// The version `.fvmrc` declares, which every other file must agree with.
String get _declaredVersion {
  final match =
      RegExp(r'"flutter"\s*:\s*"([^"]+)"').firstMatch(_read('.fvmrc'));
  expect(match, isNotNull,
      reason: '.fvmrc no longer has a "flutter" key; the Makefile parses '
          'it with the same shape and would silently produce an empty tag');
  return match!.group(1)!;
}

void main() {
  test('.fvmrc names a plausible Flutter version', () {
    // Guards the degenerate case: every comparison below passes if the
    // parse yields an empty string and nothing else mentions a version.
    expect(_declaredVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'the other checks compare against this, so it has to be '
            'a real version and not an empty match');
  });

  group('every file that pins the toolchain pins the same one', () {
    test('docker-compose.yml defaults to the declared version', () {
      final compose = _read('docker-compose.yml');
      final version = _declaredVersion;

      // Both the build arg and the image tag, since a mismatch between
      // those two builds one version and labels it another.
      expect(compose, contains('FLUTTER_VERSION: \${FLUTTER_VERSION:-$version}'),
          reason: 'compose builds with its own default when FLUTTER_VERSION '
              'is unset, so that default is the version people get');
      expect(compose, contains('image: deaddrop-dev:\${FLUTTER_VERSION:-$version}'),
          reason: 'the tag has to name what was actually built');
    });

    test('the Dockerfile default matches', () {
      // The Makefile now passes --build-arg explicitly, but a bare
      // `docker build` still falls back to this.
      expect(_read('docker/Dockerfile'),
          contains('ARG FLUTTER_VERSION=$_declaredVersion'));
    });

    test('both CI workflows match', () {
      final version = _declaredVersion;
      for (final workflow in ['build.yml', 'test-build.yml']) {
        expect(_read('.github/workflows/$workflow'),
            contains("FLUTTER_VERSION: '$version'"),
            reason: '$workflow builds what users download; if it disagrees '
                'with .fvmrc the binaries are not what was tested');
      }
    });
  });

  group('the Makefile keeps its hands off other projects', () {
    // `azukari-spike-hook` was built from a copy of docker/Dockerfile and so
    // inherited `dev.deaddrop.project=dead-drop`. `make docker-clean` filtered
    // on that label alone, which put 14.6GB belonging to a different project
    // on the delete list. A label travels with a copied Dockerfile; the image
    // name does not.

    test('docker-clean filters on the image name, not only the label', () {
      final target = _targetBody(_read('Makefile'), 'docker-clean');

      expect(target, contains(r'docker images "$(IMAGE_REPO)"'),
          reason: 'without the repository argument, `docker images '
              '--filter label=…` lists every image that copied the '
              'Dockerfile, and docker rmi takes the lot');
    });

    test('docker-status lists the strays instead of hiding them', () {
      final target = _targetBody(_read('Makefile'), 'docker-status');

      expect(target, contains(r'grep -v "^$(IMAGE_REPO):"'),
          reason: 'an image wearing this project\'s label that is not this '
              'project\'s image is worth reporting: it means a copied '
              'Dockerfile somewhere needs its label changed');
    });

    test('the image name is a variable both targets can filter on', () {
      final makefile = _read('Makefile');
      expect(makefile, contains(r'IMAGE_REPO   := deaddrop-dev'));
      expect(makefile, contains(r'IMAGE        := $(IMAGE_REPO):$(FLUTTER_VERSION)'),
          reason: 'the tag is built from the same variable the filters use, '
              'so renaming the image cannot leave a filter behind');
    });
  });

  test('the Makefile builds the version it tags', () {
    // The tag came from .fvmrc while the installed version came from the
    // Dockerfile's default. Equal today, and nothing made them stay equal:
    // the image would have claimed one version and contained another.
    expect(_read('Makefile'),
        contains(r'--build-arg FLUTTER_VERSION=$(FLUTTER_VERSION)'));
  });
}

/// The body of a Makefile target, up to the next target definition.
String _targetBody(String makefile, String name) {
  final start = makefile.indexOf('\n$name:');
  expect(start, greaterThan(-1), reason: 'the $name target was renamed');
  final next = RegExp(r'\n[a-z][a-z0-9-]*:').firstMatch(
    makefile.substring(start + 1),
  );
  return next == null
      ? makefile.substring(start)
      : makefile.substring(start, start + 1 + next.start);
}
