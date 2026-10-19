# DeadDrop — Firebase App Distribution Setup

This guide walks you through setting up Firebase App Distribution for iOS and Android beta testing. No Apple Developer Program required ($99 saved).

- **Time:** ~15 minutes
- **Requirements:** Google account, iPhone/iPad or Android device for testing

---

## ⚠️ Important: Firebase config files are NOT in this repo

`GoogleService-Info.plist` (iOS) and `google-services.json` (Android) contain API keys and project identifiers. **They are gitignored and must never be committed.** Each contributor downloads their own from Firebase Console.

Template files showing the expected format are included:
- `app/ios/Runner/GoogleService-Info.plist.template`
- `app/android/app/google-services.json.template`

---

## Step 1: Create Firebase Project (5 min)

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name: `deaddrop-beta` (or whatever you prefer)
4. Disable Google Analytics (not needed for beta)
5. Click "Create project"

## Step 2: Add iOS App to Firebase (3 min)

1. In the project overview, click the iOS icon (`</>`)
2. Register app:
   - Bundle ID: `dev.deaddrop.deadDrop`
   - App nickname: `DeadDrop iOS`
   - App Store ID: leave empty (not published yet)
3. Click "Register app"
4. **Download `GoogleService-Info.plist`**
5. Save it to: `app/ios/Runner/GoogleService-Info.plist`

## Step 3: Add Android App to Firebase (3 min)

1. In the project overview, click the Android icon
2. Register app:
   - Package name: `dev.deaddrop.dead_drop`
   - App nickname: `DeadDrop Android`
3. Click "Register app"
4. **Download `google-services.json`**
5. Save it to: `app/android/app/google-services.json`

## Step 4: Verify the files are gitignored

After placing both files, confirm git is ignoring them:

```bash
cd app
git status
```

You should **not** see `GoogleService-Info.plist` or `google-services.json` listed as modified or untracked. If they appear, check that `app/.gitignore` contains:

```
ios/Runner/GoogleService-Info.plist
android/app/google-services.json
```

You can also verify explicitly:

```bash
git check-ignore -v app/ios/Runner/GoogleService-Info.plist
git check-ignore -v app/android/app/google-services.json
```

Both commands should output the matching `.gitignore` rule.

## Step 5: Enable App Distribution (2 min)

1. In Firebase Console, left menu: "Release & Monitor" → "App Distribution"
2. Click "Get started"
3. Accept terms
4. You should see your apps listed

## Step 6: Add Testers (2 min)

1. In App Distribution, go to "Testers & Groups"
2. Click "Add testers"
3. Enter email addresses of testers (your email, etc.)
4. They'll receive an email with a link to install the "Firebase App Distribution" app

## Step 7: Build and Distribute (3 min)

On your Mac, with iPhone connected:

```bash
# 1. Navigate to iOS folder
cd app/ios

# 2. Install fastlane dependencies (first time only)
bundle install

# 3. Build and upload to Firebase
fastlane beta
```

The `fastlane beta` command will:
- Build the IPA (release mode)
- Upload to Firebase App Distribution
- Send email to testers with install link

For Android:

```bash
cd app/android
bundle install
fastlane beta
```

## Step 8: Install on device

1. Tester opens email on their device
2. Clicks "Download the Firebase App Distribution app"
3. Installs the Firebase app from App Store / Play Store
4. Opens the link again → installs DeadDrop
5. On iOS: trusts the developer profile in Settings → General → VPN & Device Management

---

## Quick setup script

Instead of doing the above manually, run:

```bash
./scripts/setup-firebase.sh
```

The script checks that both config files exist, extracts the Firebase App IDs, and installs fastlane dependencies.

---

## Troubleshooting

### "No signing certificate found"
- Open `app/ios/Runner.xcworkspace` in Xcode
- Select your Apple ID in Signing & Capabilities
- Build once in Xcode (⌘B) to register the certificate

### "Bundle ID mismatch"
- Verify `app/ios/Runner.xcodeproj/project.pbxproj` has `PRODUCT_BUNDLE_IDENTIFIER = dev.deaddrop.deadDrop`
- Or change in Xcode: Target → General → Bundle Identifier

### "fastlane not found"
```bash
sudo gem install fastlane
```

### "GoogleService-Info.plist not found"
- Make sure you downloaded it to `app/ios/Runner/GoogleService-Info.plist`
- **NOT** in `app/ios/` directly

### "google-services.json not found"
- Make sure you downloaded it to `app/android/app/google-services.json`
- **NOT** in `app/android/` directly

---

## Files in this setup

| File | Purpose |
|------|---------|
| `app/ios/fastlane/Appfile` | Apple ID and team config |
| `app/ios/fastlane/Fastfile` | Build and upload automation |
| `app/ios/fastlane/Pluginfile` | Firebase plugin for fastlane |
| `app/ios/Runner/GoogleService-Info.plist` | Firebase config — **you add this, gitignored** |
| `app/ios/Runner/GoogleService-Info.plist.template` | Template showing expected format |
| `app/android/app/google-services.json` | Firebase config — **you add this, gitignored** |
| `app/android/app/google-services.json.template` | Template showing expected format |
| `scripts/setup-firebase.sh` | One-command setup with validation |

---

## Security note

Firebase API keys in `GoogleService-Info.plist` and `google-services.json` are restricted by bundle ID / package name and SHA-1 fingerprint, so they are not secrets in the traditional sense. However, we still keep them out of the public repo as a best practice:

- Prevents unauthorized use of our Firebase project quota
- Avoids exposing our project ID and internal app configuration
- Follows the principle of least exposure for open-source projects

**Never commit these files.** If you accidentally do, rotate the keys in Firebase Console immediately.

---

## Next: CI automation

Once this works manually, we can add GitHub Actions to auto-upload on every merge to main. The CI workflow will need the config files provided as GitHub Secrets.
