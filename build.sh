#!/bin/bash
set -euo pipefail

# EliAI Build Script for iOS IPA

PROJECT_NAME="EliAI"
SCHEME_NAME="EliAI"
BUILD_DIR="build"

echo "Starting build for ${PROJECT_NAME}..."

# 1. Clean build directory
rm -rf "${BUILD_DIR}"
rm -rf Payload
rm -f "${PROJECT_NAME}.ipa"

# 2. Generate project and resolve dependencies
xcodegen generate
xcodebuild -resolvePackageDependencies \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -skipPackagePluginValidation \
    -clonedSourcePackagesDirPath .spm

# 3. Build without signing (for sideload packaging)
echo "Building app..."
xcodebuild build \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    IDECustomDerivedDataLocation="$(pwd)/${BUILD_DIR}" \
    -clonedSourcePackagesDirPath .spm \
    -parallelizeTargets \
    -jobs 4 \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    DEBUG_INFORMATION_FORMAT=dwarf \
    COMPILER_INDEX_STORE_ENABLE=NO \
    SWIFT_COMPILATION_MODE=wholemodule \
    SWIFT_OPTIMIZATION_LEVEL=-O \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# 4. Create IPA manually
echo "Packaging IPA..."
mkdir -p Payload
cp -r "${BUILD_DIR}/Build/Products/Release-iphoneos/${PROJECT_NAME}.app" Payload/
zip -r "${PROJECT_NAME}.ipa" Payload

# Cleanup
rm -rf Payload

echo "Build complete."
echo "IPA located at: $(pwd)/${PROJECT_NAME}.ipa"
