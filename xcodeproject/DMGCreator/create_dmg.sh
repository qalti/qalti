#!/bin/bash
set -e  # Exit immediately on error

# Get the directory where this script resides.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#########################
# 1. Check for create-dmg
#########################
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found."
    if command -v brew >/dev/null 2>&1; then
        echo "Installing create-dmg via Homebrew..."
        brew install create-dmg
    else
        echo "Error: Homebrew is not installed. Please install Homebrew to continue." >&2
        exit 1
    fi
fi

##############################
# 2. Check and create app_folder
##############################
APP_FOLDER="${SCRIPT_DIR}/app_folder"
if [ ! -d "${APP_FOLDER}" ]; then
    echo "Creating app folder at ${APP_FOLDER}..."
    mkdir -p "${APP_FOLDER}"
fi

###########################################################################
# 3. Find the most recent Qalti*.xcarchive and copy the app
###########################################################################
# Archives are stored in ~/Library/Developer/Xcode/Archives/
ARCHIVE_BASE=~/Library/Developer/Xcode/Archives

# Enable nullglob so that non-matching globs expand to nothing.
shopt -s nullglob

LATEST_ARCHIVE_DIR=""
LATEST_ARCHIVE_TIME=0

# Loop through date directories under the Archives folder.
for date_dir in "${ARCHIVE_BASE}"/*; do
    if [ -d "${date_dir}" ]; then
        # Check if this date directory contains any xcarchive matching our pattern.
        archives=("${date_dir}"/Qalti*.xcarchive)
        if [ ${#archives[@]} -gt 0 ]; then
            # Get the modification time of the date folder.
            dir_mtime=$(stat -f "%m" "${date_dir}")
            if [ "${dir_mtime}" -gt "${LATEST_ARCHIVE_TIME}" ]; then
                LATEST_ARCHIVE_TIME="${dir_mtime}"
                LATEST_ARCHIVE_DIR="${date_dir}"
            fi
        fi
    fi
done

if [ -z "${LATEST_ARCHIVE_DIR}" ]; then
    echo "Error: No Qalti xcarchive found in any archive folder." >&2
    exit 1
fi

echo "Using archive folder: ${LATEST_ARCHIVE_DIR}"

# Within the selected date directory, choose the most recently modified xcarchive.
LATEST_XCARCHIVE=""
LATEST_XCARCHIVE_TIME=0
for archive in "${LATEST_ARCHIVE_DIR}"/Qalti*.xcarchive; do
    if [ -d "${archive}" ]; then
        archive_mtime=$(stat -f "%m" "${archive}")
        if [ "${archive_mtime}" -gt "${LATEST_XCARCHIVE_TIME}" ]; then
            LATEST_XCARCHIVE_TIME="${archive_mtime}"
            LATEST_XCARCHIVE="${archive}"
        fi
    fi
done

if [ -z "${LATEST_XCARCHIVE}" ]; then
    echo "Error: No Qalti xcarchive found in ${LATEST_ARCHIVE_DIR}." >&2
    exit 1
fi

echo "Using xcarchive: ${LATEST_XCARCHIVE}"

# Find the UUID subfolder in Submissions and verify Qalti.app exists.
SUBMISSIONS_DIR="${LATEST_XCARCHIVE}/Submissions"
if [ ! -d "${SUBMISSIONS_DIR}" ]; then
    echo "Error: Submissions directory not found in ${LATEST_XCARCHIVE}." >&2
    exit 1
fi

# Count the number of subfolders in Submissions
submission_folders=("${SUBMISSIONS_DIR}"/*)
submission_count=0
for folder in "${submission_folders[@]}"; do
    if [ -d "${folder}" ]; then
        submission_count=$((submission_count + 1))
        UUID_FOLDER="${folder}"
    fi
done

if [ "${submission_count}" -eq 0 ]; then
    echo "Error: No submission folders found in ${SUBMISSIONS_DIR}." >&2
    exit 1
elif [ "${submission_count}" -gt 1 ]; then
    echo "Error: Multiple submission folders found in ${SUBMISSIONS_DIR}. Expected exactly one." >&2
    exit 1
fi

SOURCE_APP_PATH="${UUID_FOLDER}/Qalti.app"
if [ ! -d "${SOURCE_APP_PATH}" ]; then
    echo "Error: Qalti.app not found in ${UUID_FOLDER}." >&2
    exit 1
fi

# Copy the app into the app_folder.
echo "Copying Qalti.app to ${APP_FOLDER}..."
cp -R "${SOURCE_APP_PATH}" "${APP_FOLDER}/"

#####################################################
# 4. Extract version information from the app
#####################################################
APP_PATH="${APP_FOLDER}/Qalti.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

if [ ! -f "${INFO_PLIST}" ]; then
    echo "Error: Info.plist not found in ${APP_PATH}" >&2
    exit 1
fi

# Extract version information
VERSION=$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw "${INFO_PLIST}")

if [ -z "${VERSION}" ] || [ -z "${BUILD_NUMBER}" ]; then
    echo "Error: Could not extract version information from Info.plist" >&2
    exit 1
fi

echo "App version: ${VERSION} (${BUILD_NUMBER})"

##########################################################
# 5. Remove existing DMG and create the new one
##########################################################
# Name the DMG with version information
OUTPUT_DMG="${HOME}/Downloads/Qalti-${VERSION}.dmg"
OUTPUT_RELEASE_NOTES="${HOME}/Downloads/Qalti-${VERSION}-release-notes.html"

if [ -f "${OUTPUT_DMG}" ]; then
    echo "Removing existing DMG: ${OUTPUT_DMG}"
    rm -f "${OUTPUT_DMG}"
fi

# Define absolute paths for required resources.
VOLICON="${SCRIPT_DIR}/shiftleft.installer.icns"
BACKGROUND="${SCRIPT_DIR}/bg.with-elements.small.png"

# Run create-dmg with the specified options.
echo "Creating DMG..."
create-dmg \
    --volname "Qalti" \
    --volicon "${VOLICON}" \
    --background "${BACKGROUND}" \
    --window-size 512 316 \
    --icon-size 128 \
    --app-drop-link 380 129 \
    --icon "Qalti.app" 125 129 \
    --hide-extension "Qalti.app" \
    "${OUTPUT_DMG}" \
    "${APP_FOLDER}"

echo "DMG created successfully: ${OUTPUT_DMG}"

##########################################################
# 6. Copy release notes next to the DMG
##########################################################
SOURCE_RELEASE_NOTES="${SCRIPT_DIR}/release_notes.html"

if [ -f "${SOURCE_RELEASE_NOTES}" ]; then
    echo "Copying release notes to Downloads: ${OUTPUT_RELEASE_NOTES}"
    cp "${SOURCE_RELEASE_NOTES}" "${OUTPUT_RELEASE_NOTES}"
else
    echo "Warning: ${SOURCE_RELEASE_NOTES} not found" >&2
fi

##########################################################
# 7. Display summary information
##########################################################
echo ""
echo "========================================"
echo "RELEASE SUMMARY"
echo "========================================"
echo "Version: ${VERSION} (build ${BUILD_NUMBER})"
echo "DMG: ${OUTPUT_DMG}"
echo "Release notes (original): ${SOURCE_RELEASE_NOTES}"
if [ -f "${OUTPUT_RELEASE_NOTES}" ]; then
    echo "Release notes (for upload): ${OUTPUT_RELEASE_NOTES}"
fi
echo ""
echo "Next steps:"
echo "1. Create or update GitHub Release v${VERSION}"
echo "2. Upload ${OUTPUT_DMG} as Qalti.dmg"
if [ -f "${OUTPUT_RELEASE_NOTES}" ]; then
    echo "3. Use ${OUTPUT_RELEASE_NOTES} as the GitHub Release notes source"
fi
echo "========================================"

#######################
# 8. Cleanup app_folder
#######################
if [ -d "${APP_FOLDER}/Qalti.app" ]; then
    echo "Cleaning up: Removing ${APP_FOLDER}/Qalti.app"
    rm -rf "${APP_FOLDER}/Qalti.app"
fi

echo "Done!"
