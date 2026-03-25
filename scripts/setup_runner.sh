#!/usr/bin/env bash
set -euo pipefail

# Minimal runner setup for Qalti CI.
# - Installs Qalti.app from DMG
# - Installs allurectl locally
# - Optionally downloads simulator/real-device app bundles from URLs

QALTI_VERSION="${QALTI_VERSION:-0.5.5}"
DMG_URL="${QALTI_DMG_URL:-https://app.qalti.com/releases/Qalti-${QALTI_VERSION}.dmg}"

SIMULATOR_APP_ZIP="${SIMULATOR_APP_ZIP:-SyncUps-simulator.zip}"
REAL_DEVICE_APP_ZIP="${REAL_DEVICE_APP_ZIP:-SyncUps-real-device.zip}"

APP_SIMULATOR_ZIP_URL="${APP_SIMULATOR_ZIP_URL:-}"
APP_REAL_DEVICE_ZIP_URL="${APP_REAL_DEVICE_ZIP_URL:-}"

download_if_url() {
  local url="$1"
  local out="$2"
  if [ -n "${url}" ]; then
    echo "Downloading ${out} from configured URL"
    curl -L -o "${out}" "${url}"
  else
    echo "No URL configured for ${out}; expecting it to be available locally."
  fi
}

# Fetch and install Qalti.app in headless mode.
curl -L -o "./Qalti.dmg" "${DMG_URL}"
hdiutil attach "./Qalti.dmg" -nobrowse -quiet -mountpoint "/Volumes/Qalti"
cp -R "/Volumes/Qalti/Qalti.app" "/Applications/Qalti.app"
xattr -dr com.apple.quarantine "/Applications/Qalti.app" || true
hdiutil detach "/Volumes/Qalti" -quiet || true

# Codesign setup for non-interactive CI.
# Required only if real-device tests are used in CI.
if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
  CODESIGN_ALLOCATE="$(xcrun --sdk iphoneos -f codesign_allocate)"
  export CODESIGN_ALLOCATE
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "CODESIGN_ALLOCATE=${CODESIGN_ALLOCATE}" >> "${GITHUB_ENV}"
  fi

  security unlock-keychain -p "${KEYCHAIN_PASSWORD}" ~/Library/Keychains/login.keychain-db
  security list-keychains -s ~/Library/Keychains/login.keychain-db
  security set-keychain-settings -t 3600 -u ~/Library/Keychains/login.keychain-db
  security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" ~/Library/Keychains/login.keychain-db
else
  echo "KEYCHAIN_PASSWORD is not set; skipping keychain unlock."
fi

# Install allurectl.
ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ] || [ "${ARCH}" = "aarch64" ]; then
  ALLURE_URL="https://github.com/allure-framework/allurectl/releases/latest/download/allurectl_darwin_arm64"
else
  ALLURE_URL="https://github.com/allure-framework/allurectl/releases/latest/download/allurectl_darwin_amd64"
fi
curl -L -o allurectl "${ALLURE_URL}"
chmod +x ./allurectl

# Optional app bundle downloads.
download_if_url "${APP_SIMULATOR_ZIP_URL}" "${SIMULATOR_APP_ZIP}"
download_if_url "${APP_REAL_DEVICE_ZIP_URL}" "${REAL_DEVICE_APP_ZIP}"

exit 0
