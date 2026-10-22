# Android Build Notes

This document explains Android-specific build configuration decisions and addresses common warnings you may encounter.

## compileSdk = 35

**Decision:** The project compiles against Android SDK 35 (Android 15).

**Why:** The `flutter_plugin_android_lifecycle` plugin (a transitive dependency of several Flutter plugins) requires Android SDK 35 or higher. Compiling against SDK 34 produces this warning:

```
Warning: The plugin flutter_plugin_android_lifecycle requires Android SDK version 35 or higher.
Your project is configured to compile against Android SDK 34
```

**Configuration:** In `app/android/app/build.gradle`:

```gradle
android {
    compileSdk = 35
    // ...
}
```

**Note:** This sets the *compile-time* SDK only. The app still runs on older Android versions — `minSdk` in `defaultConfig` controls the minimum supported version.

---

## Gradle File Watcher Disabled in Docker

**Decision:** Gradle's Virtual File System (VFS) watcher is disabled.

**Why:** When running Flutter builds inside Docker on macOS, Gradle's file watcher fails with:

```
Caught exception: Couldn't poll for events, error = 4
Error while receiving file changes
```

This is a known Docker-on-Mac issue. The file watcher uses native file system events that don't propagate correctly through Docker's filesystem layer on macOS.

**Configuration:** In `app/android/gradle.properties`:

```properties
org.gradle.vfs.watch=false
```

**Impact:** Disabling the file watcher means Gradle won't detect file changes between builds as efficiently. For CI/CD and Docker-based development, this is acceptable — builds are typically clean or incremental within a single session. Local native development (outside Docker) can re-enable it if desired.

---

## Tree-Shaking: Feature, Not Warning

**What you see:**

```
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 2520 bytes (99.8% reduction)
```

**This is an optimization, not a problem.**

Flutter's tree-shaking removes unused icons from font files. The MaterialIcons font contains thousands of icons; your app likely uses only a handful. Tree-shaking strips out the unused glyphs.

**Benefits:**
- Reduces APK/IPA size by ~1.6MB (in this case)
- Faster app downloads and installs
- Less storage used on user devices

**Keep it enabled.** No action needed.

If you ever need to disable tree-shaking (e.g., for debugging icon rendering issues), use:

```bash
flutter build apk --no-tree-shake-icons
```

But for production builds, always leave it enabled.

---

## Summary

| Warning | Action | Reason |
|---------|--------|--------|
| `compileSdk 34 → 35` | **Fixed** | Required by `flutter_plugin_android_lifecycle` |
| File watcher error in Docker | **Fixed** | Docker-on-Mac filesystem limitation |
| Tree-shaking message | **None** | This is a size optimization feature |

---

## Automated beta distribution (Firebase App Distribution)

Every push to `main` builds a signed release APK and uploads it to Firebase
App Distribution for the `testers` group. The job is `distribute-android`
in `.github/workflows/build.yml`.

It does **not** run on pull requests. PRs from forks cannot read repository
secrets, so the upload would fail for outside contributors, and testers
would otherwise receive builds that were never merged.

### Why the APK must be signed with a fixed key

Android identifies an app by package name **plus signing certificate**. Debug
keys are generated per machine, so an APK signed with a CI runner's debug key
cannot install over a tester's existing copy — they get "app not installed"
and have to uninstall first, losing their data. One stable upload key avoids
this.

`app/android/app/build.gradle` reads `app/android/key.properties` when it
exists and falls back to the debug keys when it does not, so a fresh clone
still builds locally without any setup.

### One-time setup

**1. Create the upload keystore** (keep the file and the passwords safe — if
you lose them, testers must uninstall and reinstall to take an update):

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**2. Create a Firebase service account.** In the Firebase console:
*Project settings → Service accounts → Generate new private key*. The account
needs the **Firebase App Distribution Admin** role. Download the JSON.

A service account is used rather than `FIREBASE_TOKEN` (which the Fastlane
lanes in `app/android/fastlane/` still reference): `firebase login:ci` tokens
are tied to a personal Google account and were deprecated by Google in 2024.

**3. Add six repository secrets** under *Settings → Secrets and variables →
Actions*:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks` (one line, no newlines) |
| `ANDROID_KEYSTORE_PASSWORD` | the `-storepass` you chose |
| `ANDROID_KEY_PASSWORD` | the `-keypass` you chose (often the same) |
| `ANDROID_KEY_ALIAS` | `upload` |
| `FIREBASE_APP_ID_ANDROID` | from Firebase console, e.g. `1:123456789:android:abc123` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | the full contents of the service account JSON |

On macOS, `base64 -i file | pbcopy` copies the value without a trailing
newline. On Linux use `base64 -w0 file`.

**4. Create the `testers` group** in Firebase App Distribution and add the
beta testers' email addresses. The group name must match the `groups:` value
in the workflow.

### Notes

- `key.properties` and `*.jks` are gitignored; CI writes them at build time
  and deletes them in a final `if: always()` step. The service account JSON
  is written to the runner temp dir with mode 600 and removed in the same
  step.
- The upload runs `firebase appdistribution:distribute` from a
  version-pinned `firebase-tools`, not a marketplace action. That step holds
  a credential with App Distribution Admin rights, and a third-party action
  referenced by a mutable tag (`@v1`) can be repointed by its owner at any
  time. Bump the pinned version deliberately rather than tracking `latest`.
- The app bundles no Firebase SDK, so no `google-services.json` is needed to
  build or upload. The copies previously committed to this repo were removed
  in #23.
- Release notes are the merged commit subject plus the short SHA.
