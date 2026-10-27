# Versioning and releases

One number identifies a build of DeadDrop, and it is derived, never typed.
This page says where it comes from, what each part means, and what a person
has to do to cut a release — which is, in the normal case, nothing.

## The version itself

DeadDrop follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`,
tagged as `vMAJOR.MINOR.PATCH`.

| Part | Goes up when | Example |
|---|---|---|
| **MAJOR** | A transfer between two devices running different versions stops working, or a vault written by an older version can no longer be opened | `1.0.0` → `2.0.0` |
| **MINOR** | A feature is added and both of those stay true | `0.3.0` → `0.4.0` |
| **PATCH** | A fix that adds nothing and breaks nothing | `0.3.0` → `0.3.1` |

**Compatibility is the criterion, not the size of the diff.** A one-line change
to the wire format is a MAJOR; a thousand lines of new UI that nothing else
depends on is a MINOR. Two things decide it, because they are the two a user
cannot recover from on their own:

- **The wire protocol.** Devices are air-gapped and are updated separately; a
  sender on v1 and a receiver on v2 must either interoperate or be on different
  MAJORs. There is no server to negotiate for them.
- **The vault format.** A vault that an upgrade cannot open is lost data, and
  the whole point of the feature is that nobody else can recover it.

While the version is `0.y.z` the project is pre-1.0 and SemVer allows breaking
changes in a MINOR. We do not use that latitude for the two things above: they
get a MAJOR regardless, because the cost of being wrong falls on a user who
cannot see it coming. `1.0.0` is cut when the MVP ships and the protocol is
considered settled.

## The build number

`pubspec.yaml` carries `version: MAJOR.MINOR.PATCH+BUILD`, and the build number
is `git rev-list --count HEAD` — the commit count.

It only ever grows, it is derivable from the repository alone, and two builds of
the same commit agree on it. Google Play and App Store Connect both reject an
upload whose build number has been seen before for that version train, and the
user never sees this number, so there is no reason for it to be anything but
monotonic.

Android reads it as `flutter.versionCode`, Apple as `$(FLUTTER_BUILD_NUMBER)`.
Neither is set by hand.

## Where the number lives

`app/pubspec.yaml` is the single source. Everything else reads from it:

| Target | Reads | Via |
|---|---|---|
| Android | `versionName` / `versionCode` | `flutter.versionName`, `flutter.versionCode` |
| iOS / macOS | `CFBundleShortVersionString` / `CFBundleVersion` | `$(FLUTTER_BUILD_NAME)`, `$(FLUTTER_BUILD_NUMBER)` |
| Linux / Windows | artifact filename | the release workflow |
| Android APK | `versionCode` in the manifest | `flutter build apk` reads pubspec |
| Git | the `vX.Y.Z` tag | the release workflow |

A release never edits `pubspec.yaml` by hand. The workflow writes it and fails
loudly if the file disagrees with the tag afterwards — a mislabelled binary is
worse than a failed release, and that is exactly what happened through v0.2.0.

## How the bump is decided

From the commits since the last tag, using
[Conventional Commits](https://www.conventionalcommits.org):

| In the commit | Bump |
|---|---|
| `feat!:`, `fix!:`, any `type!:` | **major** |
| `BREAKING CHANGE` in the body | **major** |
| `feat:` | **minor** |
| anything else (`fix:`, `docs:`, `chore:`, `refactor:`, `test:`, `ci:`) | **patch** |

A merged PR's labels can raise the level but never lower it: `breaking` forces
major, `enhancement` raises patch to minor. The label is the escape hatch for
when a commit message undersold the change; it cannot be used to sneak a
breaking change out as a patch.

So: **write the commit message correctly and the version takes care of itself.**
That is the whole strategy. The automation reads what you already have to write.

## What happens on a merge to main

1. `release.yml` fires on every push to `main`.
2. It reads the commits since the last tag and computes the next version.
3. git-cliff writes `CHANGELOG.md` and the release notes.
4. It commits the version bump as `chore(release): vX.Y.Z [skip release]`.
5. It creates the annotated tag, with the release notes as the tag message.
6. It triggers `build.yml` for that tag, which builds Linux, Windows, macOS and
   Android, collects the SHA-256 of each artifact, and publishes the GitHub
   Release.

The Android APK is signed with the upload key held in repository secrets, and
the build fails if it ends up signed with the debug key instead — gradle falls
back to debug when the signing config is missing, and an APK signed that way
cannot be installed over a previous one. iOS is built in CI as a compile check
only: distributing an `.ipa` needs a paid Apple certificate, so those builds go
out by hand (see [ios-build.md](ios-build.md)).

Steps 1-6 need no human. The `[skip release]` marker and the
`chore(release):` prefix stop the bump commit from triggering another release.

### Skipping a release

Put `[skip release]` in the commit or merge message. Documentation-only changes
are still worth a patch release in this project — the user guide ships with the
app — so use it sparingly, mostly for changes to CI that cannot affect a build.

## Pre-releases

A tag with a suffix (`v0.4.0-rc.1`, `v0.4.0-beta.2`) publishes as a GitHub
pre-release and is never offered as the latest download. Those are cut by hand:

```bash
git tag -a v0.4.0-rc.1 -m "Release candidate for the MVP freeze"
git push origin v0.4.0-rc.1
```

The build workflow marks anything with a `-` in the tag as a pre-release. Use
one when a build needs to go to a tester before it goes to everyone — before
the MVP deadline, in particular.

## Verifying a release

Every release carries `SHA256SUMS.txt` and a `.sha256` beside each artifact.
The Linux build is bit-for-bit reproducible, so you can rebuild it yourself and
compare: see [reproducible-builds.md](reproducible-builds.md) for the procedure
and [reproducibility-verification.md](reproducibility-verification.md) for the
evidence that it holds.

A release is only as trustworthy as that check, which is why the checksums are
published with the binaries rather than alongside them on a different site.
