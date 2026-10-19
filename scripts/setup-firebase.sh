#!/bin/bash
# DeadDrop — Firebase App Distribution quick setup
# Run this after creating your Firebase project
# Usage: ./scripts/setup-firebase.sh

set -e

echo "🔥 DeadDrop — Firebase App Distribution Setup"
echo "============================================="
echo ""

# Check if GoogleService-Info.plist exists
if [ ! -f "app/ios/Runner/GoogleService-Info.plist" ]; then
    echo "❌ GoogleService-Info.plist not found!"
    echo ""
    echo "Please:"
    echo "  1. Go to https://console.firebase.google.com"
    echo "  2. Select your project → Project settings → Your apps"
    echo "  3. Click the iOS app (dev.deaddrop.deadDrop)"
    echo "  4. Download GoogleService-Info.plist"
    echo "  5. Save it to: app/ios/Runner/GoogleService-Info.plist"
    echo ""
    exit 1
fi

echo "✅ GoogleService-Info.plist found"

# Extract Firebase App ID
FIREBASE_APP_ID=$(grep -o '"GOOGLE_APP_ID": "[^"]*"' app/ios/Runner/GoogleService-Info.plist | cut -d'"' -f4)

if [ -z "$FIREBASE_APP_ID" ]; then
    echo "⚠️  Could not extract Firebase App ID from plist"
    echo "   You'll need to set FIREBASE_APP_ID_IOS manually"
else
    echo "✅ Firebase App ID: $FIREBASE_APP_ID"
    echo ""
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "  export FIREBASE_APP_ID_IOS=\"$FIREBASE_APP_ID\""
    echo ""
fi

# Check if fastlane firebase plugin is installed
if [ ! -f "app/ios/Gemfile" ]; then
    echo "📦 Creating Gemfile for fastlane..."
    cat > app/ios/Gemfile << 'EOF'
source "https://rubygems.org"

gem "fastlane"
gem "fastlane-plugin-firebase_app_distribution"
EOF
    echo "✅ Gemfile created"
fi

echo ""
echo "📦 Installing fastlane dependencies..."
cd app/ios
bundle install

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Add testers in Firebase Console → App Distribution → Testers & Groups"
echo "  2. Run: cd app/ios && fastlane beta"
echo "  3. Testers will receive email with install link"
echo ""
echo "For CI/CD, set these secrets in GitHub:"
echo "  - FIREBASE_APP_ID_IOS"
echo "  - GOOGLE_APPLICATION_CREDENTIALS (service account JSON)"
