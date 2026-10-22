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

## Release signing

`flutter build apk --release` on a fresh clone signs with Gradle's **debug
keys**. That is fine for testing on your own machine and useless for anything
else: Android identifies an app by package name **plus signing certificate**,
and debug keys are generated per machine. An APK signed on one computer cannot
install over a copy someone installed from another — they get "app not
installed" and have to uninstall first, losing their data.

Anything you hand to another person needs a single, stable **upload key**.

### Generating the keystore

Keep the file and the passwords somewhere safe — a password manager, not the
repo. If you lose them, every tester has to uninstall before they can take an
update.

```bash
cd ~   # anywhere outside the repo
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

No Java on your machine? The dev container has JDK 17:

```bash
docker run --rm -it --platform linux/amd64 \
  -v "$HOME:/out" -w /out --user "$(id -u):$(id -g)" \
  deaddrop-dev:3.24.5 \
  keytool -genkey -v -keystore /out/upload-keystore.jks -storetype JKS \
    -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### Using it

Create `app/android/key.properties` (gitignored, never commit it):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=upload
```

`flutter build apk --release` now signs with that key. Without the file the
build still works and falls back to debug keys, so contributors who never
cut releases need no setup.

### Verifying which key signed an APK

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/w" deaddrop-dev:3.24.5 \
  bash -c '$(find /opt/android-sdk/build-tools -name apksigner | head -1) \
    verify --print-certs /w/app/build/app/outputs/flutter-apk/app-release.apk'
```

A debug-signed APK reports `CN=Android Debug`. Your upload key reports
whatever you entered when generating it.


## Summary

| Warning | Action | Reason |
|---------|--------|--------|
| `compileSdk 34 → 35` | **Fixed** | Required by `flutter_plugin_android_lifecycle` |
| File watcher error in Docker | **Fixed** | Docker-on-Mac filesystem limitation |
| Tree-shaking message | **None** | This is a size optimization feature |
| Release signed with debug keys | **Fixed** | Debug keys are per-machine; distributed APKs need a stable upload key |
