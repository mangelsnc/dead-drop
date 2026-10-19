#!/bin/bash
# DeadDrop — Firebase App Distribution quick setup
# Run this after creating your Firebase project and downloading the config files
# Usage: ./scripts/setup-firebase.sh

set -e

echo "🔥 DeadDrop — Firebase App Distribution Setup"
echo "============================================="
echo ""

# --- Validate Firebase config files exist ---
# These files are gitignored and must be downloaded from Firebase Console.
# See docs/firebase-setup.md for step-by-step instructions.

MISSING=0

if [ ! -f "app/ios/Runner/GoogleService-Info.plist" ]; then
    echo "❌ GoogleService-Info.plist not found!"
    echo ""
    echo "   Download it from Firebase Console and place it at:"
    echo "   app/ios/Runner/GoogleService-Info.plist"
    echo ""
    echo "   Steps:"
    echo "     1. Go to https://console.firebase.google.com"
    echo "     2. Select your project → Project settings → Your apps"
    echo "     3. Click the iOS app (dev.deaddrop.deadDrop)"
    echo "     4. Download GoogleService-Info.plist"
    echo "     5. Save it to: app/ios/Runner/GoogleService-Info.plist"
    echo ""
    echo "   A template is available at:"
    echo "   app/ios/Runner/GoogleService-Info.plist.template"
    echo ""
    MISSING=1
fi

if [ ! -f "app/android/app/google-services.json" ]; then
    echo "❌ google-services.json not found!"
    echo ""
    echo "   Download it from Firebase Console and place it at:"
    echo "   app/android/app/google-services.json"
    echo ""
    echo "   Steps:"
    echo "     1. Go to https://console.firebase.google.com"
    echo "     2. Select your project → Project settings → Your apps"
    echo "     3. Click the Android app (dev.deaddrop.dead_drop)"
    echo "     4. Download google-services.json"
    echo "     5. Save it to: app/android/app/google-services.json"
    echo ""
    echo "   A template is available at:"
    echo "   app/android/app/google-services.json.template"
    echo ""
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    echo "⚠️  These files are gitignored — they are NOT in the repository."
    echo "   Each contributor must download their own from Firebase Console."
    echo "   See docs/firebase-setup.md for full instructions."
    exit 1
fi

echo "✅ GoogleService-Info.plist found"
echo "✅ google-services.json found"

# --- Extract Firebase App IDs ---
FIREBASE_APP_ID_IOS=$(grep -o '"GOOGLE_APP_ID": "[^"]*"' app/ios/Runner/GoogleService-Info.plist | cut -d'"' -f4)
FIREBASE_APP_ID_ANDROID=$(grep -o '"mobilesdk_app_id": "[^"]*"' app/android/app/google-services.json | cut -d'"' -f4)

echo ""
echo "Firebase App IDs:"
echo "  iOS:     $FIREBASE_APP_ID_IOS"
echo "  Android: $FIREBASE_APP_ID_ANDROID"
echo ""
echo "Add these to your shell profile (~/.zshrc or ~/.bashrc):"
echo ""
echo "  export FIREBASE_APP_ID_IOS=\"$FIREBASE_APP_ID_IOS\""
echo "  export FIREBASE_APP_ID_ANDROID=\"$FIREBASE_APP_ID_ANDROID\""
echo ""

# --- Install fastlane dependencies ---

# Check if fastlane firebase plugin is installed (iOS)
if [ ! -f "app/ios/Gemfile" ]; then
    echo "📦 Creating Gemfile for iOS fastlane..."
    cat > app/ios/Gemfile << 'EOF'
source "https://rubygems.org"

gem "fastlane"
gem "fastlane-plugin-firebase_app_distribution"
EOF
    echo "✅ iOS Gemfile created"
fi

# Check if fastlane firebase plugin is installed (Android)
if [ ! -f "app/android/Gemfile" ]; then
    echo "📦 Creating Gemfile for Android fastlane..."
    cat > app/android/Gemfile << 'EOF'
source "https://rubygems.org"

gem "fastlane"
gem "fastlane-plugin-firebase_app_distribution"
EOF
    echo "✅ Android Gemfile created"
fi

echo ""
echo "📦 Installing iOS fastlane dependencies..."
cd app/ios
bundle install

echo ""
echo "📦 Installing Android fastlane dependencies..."
cd ../android
bundle install

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Add testers in Firebase Console → App Distribution → Testers & Groups"
echo "  2. iOS:     cd app/ios && fastlane beta"
echo "  3. Android: cd app/android && fastlane beta"
echo "  4. Testers will receive email with install link"
echo ""
echo "For CI/CD, set these secrets in GitHub:"
echo "  - FIREBASE_APP_ID_IOS"
echo "  - FIREBASE_APP_ID_ANDROID"
echo "  - GOOGLE_APPLICATION_CREDENTIALS (service account JSON)"
