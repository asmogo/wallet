#!/bin/sh
#
# Patch the embedded CashuDevKitFFI.framework Info.plist so the app passes
# App Store / TestFlight upload validation.
#
# cashubtc/cdk-swift ships its Rust core as a *dynamic* framework whose
# Info.plist was missing keys Apple requires for embedded frameworks:
#   - MinimumOSVersion           (upload errors 90360 / 90530)
#   - CFBundleShortVersionString (upload error 90057)
# The bug is present in v0.17.0 and v0.17.1; upstream ships both keys as of
# v0.17.3-rc.0. Kept as a safety net: it overwrites the values to match the
# app (Set falls back to Add if a key is absent) and re-signs the framework
# (editing Info.plist invalidates its signature).
#
# Runs as the last build phase of the CashuWallet target.

set -eu

# macOS ships the framework in versioned layout and Apple's upload validation
# does not apply, so there is nothing to patch. Bail before touching
# IPHONEOS_DEPLOYMENT_TARGET, which is unset on that platform.
case "${PLATFORM_NAME:-}" in
    macosx)
        echo "note: macOS build; skipping iOS upload-validation plist fix-up"
        exit 0
        ;;
esac

FRAMEWORK="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/CashuDevKitFFI.framework"
PLIST="${FRAMEWORK}/Info.plist"

if [ ! -f "${PLIST}" ]; then
    echo "note: CashuDevKitFFI.framework not embedded at ${PLIST}; skipping fix-up"
    exit 0
fi

# MinimumOSVersion — must match (or be <=) the app's deployment target.
if ! /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion ${IPHONEOS_DEPLOYMENT_TARGET}" "${PLIST}" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string ${IPHONEOS_DEPLOYMENT_TARGET}" "${PLIST}"
fi

# CFBundleShortVersionString — any valid version string; reuse the app's.
SHORT_VERSION="${MARKETING_VERSION:-1.0}"
if ! /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" "${PLIST}" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${SHORT_VERSION}" "${PLIST}"
fi

echo "Patched ${PLIST} (MinimumOSVersion=${IPHONEOS_DEPLOYMENT_TARGET}, CFBundleShortVersionString=${SHORT_VERSION})"

# Re-sign — modifying Info.plist invalidates the framework's code signature.
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORK}"
    echo "Re-signed ${FRAMEWORK} with ${EXPANDED_CODE_SIGN_IDENTITY_NAME:-$EXPANDED_CODE_SIGN_IDENTITY}"
elif [ "${CODE_SIGNING_REQUIRED:-YES}" != "NO" ]; then
    codesign --force --sign - "${FRAMEWORK}"
    echo "Ad-hoc re-signed ${FRAMEWORK}"
fi
