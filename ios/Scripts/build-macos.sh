#!/bin/sh
#
# Build (and optionally run) the Mac menu bar build of the wallet.
#
#   ./Scripts/build-macos.sh          # build only
#   ./Scripts/build-macos.sh run      # build, then launch it
#
# The app is an LSUIElement accessory: it has no Dock icon and no window at
# launch. Look for the bitcoin glyph in the menu bar on the right-hand side.
#
# Signed ad-hoc by default so a build works with no Apple Developer setup at
# all. Pass DEV_TEAM=... to sign with a real identity instead.

set -eu

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-$PWD/build/macos}"

# Ad-hoc by default, which also means unsandboxed — the two are linked.
#
# A sandboxed app reaches the Keychain through an access group derived from the
# team identifier in its signature. Ad-hoc has no team identifier, so a
# sandboxed ad-hoc build cannot save the wallet seed at all. The local
# entitlements file therefore turns the sandbox off; see the comment in it.
#
# Pass DEV_TEAM=... to sign properly, which uses the real sandboxed
# entitlements the project references. That is what release builds must use.
SIGNING_ARGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= CODE_SIGN_ENTITLEMENTS=CashuWallet/CashuWalletMacLocal.entitlements"
if [ -n "${DEV_TEAM:-}" ]; then
    SIGNING_ARGS="CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=${DEV_TEAM}"
fi

# Workaround, not a preference — and NOT specific to macOS.
#
# swift-secp256k1 0.23.2 gates its C modules behind SwiftPM package *traits*
# (`.define(..., .when(traits:))`). Xcode 26.1 does not apply that package's
# default traits, so ENABLE_MODULE_{ECDH,RECOVERY,SCHNORRSIG,MUSIG} never reach
# the compiler, those modules are preprocessed away, and the link fails with
# ~20 undefined `_secp256k1_*` symbols. Verified against an unmodified checkout
# of main: the iOS build in README.md fails the same way on Xcode 26.1.
#
# Only *command-line* build settings reach SwiftPM package targets — setting
# these at the project level in project.pbxproj has no effect on them (tested).
# So the defines have to live here, in the invocation.
#
# Remove this block once Xcode resolves package traits, or once the dependency
# stops gating its C sources on them.
SECP256K1_TRAITS="GCC_PREPROCESSOR_DEFINITIONS=\$(inherited) ENABLE_MODULE_ECDH=1 ENABLE_MODULE_RECOVERY=1 ENABLE_MODULE_SCHNORRSIG=1 ENABLE_MODULE_MUSIG=1"

echo "Building CashuWallet for macOS (${CONFIG})..."

# shellcheck disable=SC2086
xcodebuild \
    -project CashuWallet.xcodeproj \
    -scheme CashuWallet \
    -destination 'platform=macOS,arch=arm64' \
    -configuration "${CONFIG}" \
    -derivedDataPath "${DERIVED}" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    ${SIGNING_ARGS} \
    "${SECP256K1_TRAITS}" \
    build

APP="${DERIVED}/Build/Products/${CONFIG}/CashuWallet.app"
echo
echo "Built: ${APP}"

if [ "${1:-}" = "run" ]; then
    # Kill any previous instance so the status item is not installed twice.
    pkill -x CashuWallet 2>/dev/null || true
    open "${APP}"
    echo "Launched. The wallet is the bitcoin glyph in your menu bar."
fi
