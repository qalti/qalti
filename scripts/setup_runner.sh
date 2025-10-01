#!/usr/bin/env bash
set -euo pipefail

# Minimal runner setup for Qalti CI.
# - Installs Qalti.app from DMG
# - Installs Qalti.app so you can invoke `Qalti` and `QaltiScheduler` from the app bundle
# - Downloads `allurectl` locally
# - Downloads simulator and real-device builds from S3

QALTI_VERSION="${QALTI_VERSION:-0.5.5}"
DMG_URL="${QALTI_DMG_URL:-https://app.qalti.com/releases/Qalti-${QALTI_VERSION}.dmg}"


# Fetch and install Qalti.app in headless mode
curl -L -o "./Qalti.dmg" "${DMG_URL}"
hdiutil attach "./Qalti.dmg" -nobrowse -quiet -mountpoint "/Volumes/Qalti"
cp -R "/Volumes/Qalti/Qalti.app" "/Applications/Qalti.app"
xattr -dr com.apple.quarantine "/Applications/Qalti.app" || true
hdiutil detach "/Volumes/Qalti" -quiet || true


# Codesign setup for non-interactive CI
# In non-interactive runs, codesign can’t read the private key unless the keychain
# is unlocked and the identity is in a keychain on the search list with the right
# access control. Apple engineers frequently recommend unlocking the keychain for
# the job before signing.
# We need codesign to run tests on your real device.

# Pins codesign to the SDK-correct codesign_allocate tool for iOS builds 
# (Xcode finds this via the CODESIGN_ALLOCATE env var)
CODESIGN_ALLOCATE="$(xcrun --sdk iphoneos -f codesign_allocate)"
export CODESIGN_ALLOCATE
echo "CODESIGN_ALLOCATE=${CODESIGN_ALLOCATE}" >> "${GITHUB_ENV}"

# Unlock and configure the login keychain for codesigning
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" ~/Library/Keychains/login.keychain-db
security list-keychains -s ~/Library/Keychains/login.keychain-db
security set-keychain-settings -t 3600 -u ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" ~/Library/Keychains/login.keychain-db


# Install allurectl
# We use it to demonstrate how to upload Allure reports to TestOps Cloud
ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
  ALLURE_URL="https://github.com/allure-framework/allurectl/releases/latest/download/allurectl_darwin_arm64"
else
  ALLURE_URL="https://github.com/allure-framework/allurectl/releases/latest/download/allurectl_darwin_amd64"
fi
curl -L -o allurectl "${ALLURE_URL}"
chmod +x ./allurectl


# Fetch simulator and real-device builds
aws s3 cp "s3://aiqa-data-dir-3/builds/syncups/SyncUps-simulator.zip" SyncUps-simulator.zip --no-progress
aws s3 cp "s3://aiqa-data-dir-3/builds/syncups/SyncUps-real-device.zip" SyncUps-real-device.zip --no-progress

exit 0
