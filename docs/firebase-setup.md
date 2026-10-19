# DeadDrop — Firebase App Distribution Setup
# ============================================
#
# This file guides you through setting up Firebase App Distribution
# for iOS beta testing. No Apple Developer Program required ($99 saved).
#
# Time: ~15 minutes
# Requirements: Google account, iPhone/iPad for testing

## Step 1: Create Firebase Project (5 min)

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name: `deaddrop-beta` (or whatever you prefer)
4. Disable Google Analytics (not needed for beta)
5. Click "Create project"

## Step 2: Add iOS App to Firebase (3 min)

1. In the project overview, click the iOS icon (</>)
2. Register app:
   - Bundle ID: `dev.deaddrop.deadDrop`
   - App nickname: `DeadDrop iOS`
   - App Store ID: leave empty (not published yet)
3. Click "Register app"
4. Download `GoogleService-Info.plist`
5. Save it to: `app/ios/Runner/GoogleService-Info.plist`

## Step 3: Enable App Distribution (2 min)

1. In Firebase Console, left menu: "Release & Monitor" → "App Distribution"
2. Click "Get started"
3. Accept terms
4. You should see your iOS app listed

## Step 4: Add Testers (2 min)

1. In App Distribution, go to "Testers & Groups"
2. Click "Add testers"
3. Enter email addresses of testers (your email, etc.)
4. They'll receive an email with a link to install the "Firebase App Distribution" app

## Step 5: Build and Distribute (3 min)

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

## Step 6: Install on iPhone

1. Tester opens email on iPhone
2. Clicks "Download the Firebase App Distribution app"
3. Installs the Firebase app from App Store
4. Opens the link again → installs DeadDrop
5. Trusts the developer profile in Settings → General → VPN & Device Management

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
- NOT in `app/ios/` directly

## Files in this setup

| File | Purpose |
|------|---------|
| `app/ios/fastlane/Appfile` | Apple ID and team config |
| `app/ios/fastlane/Fastfile` | Build and upload automation |
| `app/ios/fastlane/Pluginfile` | Firebase plugin for fastlane |
| `app/ios/Runner/GoogleService-Info.plist` | Firebase config (YOU ADD THIS) |
| `scripts/prepare-ios.sh` | One-command setup |

## Security note

`GoogleService-Info.plist` contains API keys but they're safe to commit:
- They're restricted by bundle ID and SHA-1 fingerprint
- Firebase App Distribution is designed for this workflow
- Still, don't share the file publicly if you're paranoid

## Next: CI automation

Once this works manually, we can add GitHub Actions to auto-upload on every merge to main. But that's for later — today we test manually.
