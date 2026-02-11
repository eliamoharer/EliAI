#!/bin/bash
set -e

# EliAI Build Script for iOS IPA

PROJECT_NAME="EliAI"
SCHEME_NAME="EliAI"
BUILD_DIR="build"

echo "🚀 Starting Build for ${PROJECT_NAME}..."

# 1. Clean build directory
rm -rf "${BUILD_DIR}"
rm -rf Payload
rm -f "${PROJECT_NAME}.ipa"

# 2. Build without signing (Ad-hoc)
echo "📦 Building App..."
xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -sdk iphoneos \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# 3. Create IPA manually
echo "📤 Packaging IPA..."
mkdir Payload
cp -r "${BUILD_DIR}/Build/Products/Release-iphoneos/${PROJECT_NAME}.app" Payload/
zip -r "${PROJECT_NAME}.ipa" Payload

# Cleanup
rm -rf Payload

echo "✅ Build Complete!"
echo "📍 IPA located at: $(pwd)/${PROJECT_NAME}.ipa"
