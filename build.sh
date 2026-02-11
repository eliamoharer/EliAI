#!/bin/bash
set -e

# EliAI Build Script for iOS IPA

PROJECT_NAME="EliAI"
SCHEME_NAME="EliAI"
ARCHIVE_PATH="build/${PROJECT_NAME}.xcarchive"
EXPORT_PATH="build"
PLIST_PATH="ExportOptions.plist"

echo "🚀 Starting Build for ${PROJECT_NAME}..."

# 1. Clean build directory
rm -rf build
mkdir build

# 2. Archive
echo "📦 Archiving..."
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -sdk iphoneos \
    -configuration Release \
    -allowProvisioningUpdates

# 3. Export IPA
echo "📤 Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${PLIST_PATH}"

echo "✅ Build Complete!"
echo "📍 IPA located at: ${EXPORT_PATH}/${PROJECT_NAME}.ipa"
