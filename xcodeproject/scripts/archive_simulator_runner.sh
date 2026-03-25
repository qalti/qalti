#!/usr/bin/env bash

set -euo pipefail

# Allow specifying a custom Xcode path via an environment variable.
if [ -n "${XCODE_PATH:-}" ] && [ -d "${XCODE_PATH}" ]; then
  echo "==> Using custom Xcode from XCODE_PATH: ${XCODE_PATH}"
  export DEVELOPER_DIR="${XCODE_PATH}/Contents/Developer"
fi

# Directory layout -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PROJECT_ROOT}/.." && pwd)"

PROJECT_PATH="${PROJECT_ROOT}/Qalti.xcodeproj"
SCHEME="${SCHEME:-QaltiRunner}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"

ARTIFACT_ROOT="${PROJECT_ROOT}/${SIM_RUNNER_OUTPUT_DIR:-.artifacts/simulator-runner}"
DERIVED_DATA_DIR="${ARTIFACT_ROOT}/DerivedData"
PAYLOAD_DIR="${ARTIFACT_ROOT}/payload"
ARCHIVE_PATH="${ARTIFACT_ROOT}/qalti-runner-simulator.tar.bz2"

echo "==> Building ${SCHEME} (${CONFIGURATION}) for ${DESTINATION}"
echo "    Project:    ${PROJECT_PATH}"
echo "    Output dir: ${ARTIFACT_ROOT}"

rm -rf "${DERIVED_DATA_DIR}" "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"

xcodebuild \
  build-for-testing \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphonesimulator \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  ONLY_ACTIVE_ARCH=NO

PRODUCTS_DIR="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}-iphonesimulator"
if [[ ! -d "${PRODUCTS_DIR}" ]]; then
  echo "Unable to locate products directory at ${PRODUCTS_DIR}" >&2
  exit 1
fi

for bundle in "QaltiRunner.app" "QaltiUITests-Runner.app"; do
  if [[ ! -e "${PRODUCTS_DIR}/${bundle}" ]]; then
    echo "Missing build product: ${PRODUCTS_DIR}/${bundle}" >&2
    exit 1
  fi
  echo "Copying ${bundle}"
  rsync -a "${PRODUCTS_DIR}/${bundle}" "${PAYLOAD_DIR}/"
done

echo "Creating archive ${ARCHIVE_PATH}"
rm -f "${ARCHIVE_PATH}"
tar -cjf "${ARCHIVE_PATH}" -C "${PAYLOAD_DIR}" .

echo ""
echo "Simulator runner assets are ready:"
echo "  - Host app & UI test bundle: ${PAYLOAD_DIR}"
echo "  - Archive: ${ARCHIVE_PATH}"
echo ""
echo "You can redistribute the archive or copy the payload contents into"
echo "the macOS bundle's simulator binaries directory."
