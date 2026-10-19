#!/bin/bash
# DeadDrop — iOS preparation script
# Run this on a Mac with Xcode + Flutter installed
# Usage: ./scripts/prepare-ios.sh

set -e

echo "🔧 DeadDrop iOS Preparation"
echo "=========================="
echo ""

# Check we're in the right place
if [ ! -f "app/pubspec.yaml" ]; then
    echo "❌ Error: Run this from the repo root (where app/ is)"
    exit 1
fi

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Install from https://flutter.dev"
    exit 1
fi

echo "✅ Flutter: $(flutter --version | head -1)"

# Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Install from App Store."
    exit 1
fi

echo "✅ Xcode: $(xcodebuild -version | head -1)"

# Check CocoaPods
if ! command -v pod &> /dev/null; then
    echo "⚠️  CocoaPods not found. Installing..."
    sudo gem install cocoapods
fi

echo "✅ CocoaPods: $(pod --version)"
echo ""

# Regenerate iOS folder if incomplete
if [ ! -f "app/ios/Runner.xcodeproj/project.pbxproj" ]; then
    echo "📱 iOS project incomplete. Regenerating..."
    cd app
    flutter create --platforms=ios .
    cd ..
    echo "✅ iOS project regenerated"
else
    echo "✅ iOS project exists"
fi

echo ""
echo "📦 Installing dependencies..."
cd app
flutter pub get

echo ""
echo "🔨 Building for iOS (release)..."
flutter build ios --release --no-codesign

echo ""
echo "✅ iOS build complete!"
echo ""
echo "Next steps:"
echo "  1. Open app/ios/Runner.xcworkspace in Xcode"
echo "  2. Select your development team (Signing & Capabilities)"
echo "  3. Connect your iPhone/iPad"
echo "  4. Press ▶️ to build and run"
echo ""
echo "For distribution to testers:"
echo "  cd app/ios && fastlane beta"
