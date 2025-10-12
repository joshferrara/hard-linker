#!/bin/bash

# Hard Linker Build, Sign, Notarize, and Release Script
# This script automates the complete release process for Hard Linker

set -e  # Exit on any error

# Configuration
APP_NAME="Hard Linker"
APP_BUNDLE="Hard-Linker.app"
BUNDLE_ID="com.hardlinker.app"
VERSION=""
BUILD_NUMBER=""
ENTITLEMENTS="Sources/HardLinkCreator/Entitlements.plist"
SIGNING_IDENTITY="Developer ID Application: Hivemind Labs, Inc. (684MMQ8PLC)"
KEYCHAIN_PROFILE="hivemindlabs"  # You'll need to set this up with: xcrun notarytool store-credentials
SPARKLE_PRIVATE_KEY="sparkle_private_key"  # Path to your Sparkle private key
RELEASES_DIR="releases"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

sign_component() {
    local component_path="$1"
    if [ ! -e "${component_path}" ]; then
        echo_error "Component not found for codesigning: ${component_path}"
        exit 1
    fi

    codesign --force --options runtime \
        --timestamp \
        --sign "${SIGNING_IDENTITY}" \
        --preserve-metadata=entitlements,requirements \
        "${component_path}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        *)
            echo_error "Unknown option: $1"
            echo "Usage: $0 -v VERSION -b BUILD_NUMBER"
            echo "Example: $0 -v 1.0.1 -b 2"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
    echo_error "Version and build number are required"
    echo "Usage: $0 -v VERSION -b BUILD_NUMBER"
    echo "Example: $0 -v 1.0.1 -b 2"
    exit 1
fi

echo_info "Building Hard Linker v${VERSION} (build ${BUILD_NUMBER})"

# Step 1: Update version in Info.plist
echo_info "Updating version information..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_BUNDLE}/Contents/Info.plist"

# Step 2: Clean and build release
echo_info "Building release binary..."
swift build -c release

# Step 3: Copy binary to app bundle
echo_info "Copying binary to app bundle..."
cp ".build/release/HardLinkCreator" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 3.5: Update binary rpath to point to Frameworks directory
echo_info "Updating binary rpath..."
install_name_tool -add_rpath "@loader_path/../Frameworks" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 3.6: Copy Sparkle framework to app bundle
echo_info "Copying Sparkle framework to app bundle..."
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
    mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
    cp -R "${SPARKLE_FW}" "${APP_BUNDLE}/Contents/Frameworks/"
    echo_info "Sparkle framework copied"
else
    echo_error "Sparkle framework not found"
    exit 1
fi

# Step 4: Code sign the app bundle
echo_info "Code signing application..."
echo_info "Signing Sparkle helper components..."
sign_component "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign_component "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign_component "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
sign_component "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
sign_component "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${SIGNING_IDENTITY}" \
    --timestamp \
    "${APP_BUNDLE}"

# Verify code signature
echo_info "Verifying code signature..."
codesign --verify --verbose "${APP_BUNDLE}"
spctl --assess --verbose "${APP_BUNDLE}" || echo_warn "App not yet notarized (expected at this stage)"

# Step 5: Create distributable archive
echo_info "Creating distributable archive..."
mkdir -p "${RELEASES_DIR}"
ARCHIVE_NAME="Hard-Linker-${VERSION}.zip"
ARCHIVE_PATH="${RELEASES_DIR}/${ARCHIVE_NAME}"

# Use ditto with --norsrc to exclude AppleDouble files that break code signatures
ditto -c -k --keepParent --norsrc "${APP_BUNDLE}" "${ARCHIVE_PATH}"

# Step 6: Notarize the archive
echo_info "Submitting for notarization..."
xcrun notarytool submit "${ARCHIVE_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

# Step 7: Staple the notarization ticket
echo_info "Stapling notarization ticket..."
# Extract, staple, and re-zip
TEMP_DIR=$(mktemp -d)
unzip -q "${ARCHIVE_PATH}" -d "${TEMP_DIR}"
xcrun stapler staple "${TEMP_DIR}/${APP_BUNDLE}"
cd "${TEMP_DIR}"
ditto -c -k --keepParent --norsrc "${APP_BUNDLE}" "${ARCHIVE_PATH}"
cd - > /dev/null
rm -rf "${TEMP_DIR}"

echo_info "Verifying notarization..."
spctl --assess -vv --type install "${APP_BUNDLE}"

# Step 8: Generate appcast with Sparkle
echo_info "Generating appcast..."
if [ ! -f "${SPARKLE_PRIVATE_KEY}" ]; then
    echo_warn "Sparkle private key not found at ${SPARKLE_PRIVATE_KEY}"
    echo_warn "Skipping appcast generation. Run generate_keys first."
else
    # Find Sparkle's generate_appcast tool
    SPARKLE_TOOL=$(find .build/artifacts -name "generate_appcast" -type f | head -1)
    if [ -z "${SPARKLE_TOOL}" ]; then
        echo_warn "generate_appcast tool not found. Make sure Sparkle is resolved."
        echo_warn "Run: swift package resolve"
    else
        echo_info "Using Sparkle tool: ${SPARKLE_TOOL}"
        "${SPARKLE_TOOL}" "${RELEASES_DIR}" \
            --ed-key-file "${SPARKLE_PRIVATE_KEY}" \
            --download-url-prefix "https://github.com/joshferrara/hard-linker/releases/download/v${VERSION}/"

        # Move generated appcast to root
        if [ -f "${RELEASES_DIR}/appcast.xml" ]; then
            cp "${RELEASES_DIR}/appcast.xml" "appcast.xml"
            echo_info "Appcast updated at appcast.xml"
        fi
    fi
fi

# Step 9: Calculate archive size and hash
ARCHIVE_SIZE=$(stat -f%z "${ARCHIVE_PATH}")
ARCHIVE_SHA256=$(shasum -a 256 "${ARCHIVE_PATH}" | cut -d' ' -f1)

# Summary
echo_info "==============================================="
echo_info "Build complete!"
echo_info "Version: ${VERSION} (build ${BUILD_NUMBER})"
echo_info "Archive: ${ARCHIVE_PATH}"
echo_info "Size: ${ARCHIVE_SIZE} bytes"
echo_info "SHA256: ${ARCHIVE_SHA256}"
echo_info "==============================================="
echo ""
echo_info "Next steps:"
echo "1. Test the app: open '${APP_BUNDLE}'"
echo "2. Test the archive: unzip '${ARCHIVE_PATH}' to a temp location and test"
echo "3. Create GitHub release: gh release create v${VERSION} '${ARCHIVE_PATH}'"
echo "4. Commit and push appcast.xml to gh-pages branch"
echo "5. Update Info.plist with the correct SUFeedURL if needed"
echo ""
echo_warn "Remember to keep your Sparkle private key (${SPARKLE_PRIVATE_KEY}) secure and NEVER commit it!"
