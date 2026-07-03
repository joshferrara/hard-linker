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
APP_ICON="AppIcon.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Hivemind Labs, Inc. (684MMQ8PLC)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-hivemindlabs}"  # Set up with: xcrun notarytool store-credentials
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-sparkle_private_key}"  # Path to your Sparkle private key
SPARKLE_PUBLIC_ED_KEY="N4HJPxwDFLFXsF+wZO0gg5TpW0fejZwpe4aEEtSB+2k="
SPARKLE_FEED_URL="https://joshferrara.github.io/hard-linker/appcast.xml"
RELEASES_DIR="${RELEASES_DIR:-releases}"

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

    # Do not preserve the upstream entitlements here; Sparkle bundles are signed
    # with the project's team identifier. Preserving their metadata leaves the
    # original application-identifier in place and produces an invalid signature.
    codesign --force --options runtime \
        --timestamp \
        --sign "${SIGNING_IDENTITY}" \
        "${component_path}"
}

prepare_app_bundle() {
    if [ ! -f "${APP_ICON}" ]; then
        echo_error "App icon not found: ${APP_ICON}"
        exit 1
    fi

    rm -rf "${APP_BUNDLE}"
    mkdir -p \
        "${APP_BUNDLE}/Contents/MacOS" \
        "${APP_BUNDLE}/Contents/Resources" \
        "${APP_BUNDLE}/Contents/Frameworks"

    cp "${APP_ICON}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

    cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright (c) 2025 Josh Ferrara. All rights reserved.</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
</dict>
</plist>
PLIST
}

verify_embedded_dependencies() {
    local app_executable="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
    local sparkle_binary="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

    if ! otool -L "${app_executable}" | grep -q "@rpath/Sparkle.framework/Versions/B/Sparkle"; then
        echo_error "App executable is not linked against Sparkle"
        exit 1
    fi

    if ! otool -l "${app_executable}" | grep -q "@loader_path/../Frameworks"; then
        echo_error "App executable is missing the Frameworks rpath"
        exit 1
    fi

    if [ ! -f "${sparkle_binary}" ]; then
        echo_error "Sparkle framework binary is missing from the app bundle"
        exit 1
    fi
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

# Step 1: Create a fresh app bundle
echo_info "Preparing app bundle..."
prepare_app_bundle

# Step 2: Clean and build release
echo_info "Building release binary..."
swift build -c release

# Step 3: Copy binary to app bundle
echo_info "Copying binary to app bundle..."
cp ".build/release/HardLinkCreator" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 3.5: Update binary rpath to point to Frameworks directory
echo_info "Updating binary rpath..."
if otool -l "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" | grep -q "@loader_path/../Frameworks"; then
    echo_info "Frameworks rpath already present"
else
    install_name_tool -add_rpath "@loader_path/../Frameworks" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

# Step 3.6: Copy Sparkle framework to app bundle
echo_info "Copying Sparkle framework to app bundle..."
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
    mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
    rm -rf "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
    cp -R "${SPARKLE_FW}" "${APP_BUNDLE}/Contents/Frameworks/"
    echo_info "Sparkle framework copied"
else
    echo_error "Sparkle framework not found"
    exit 1
fi

echo_info "Verifying embedded dependencies..."
verify_embedded_dependencies

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
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"
ditto -c -k --keepParent --norsrc "${APP_BUNDLE}" "${ARCHIVE_PATH}"

echo_info "Verifying notarization..."
spctl --assess -vv --type execute "${APP_BUNDLE}" || echo_warn "spctl assessment failed; stapler validation already succeeded"

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
