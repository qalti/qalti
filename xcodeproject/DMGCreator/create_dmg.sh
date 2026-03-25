#!/bin/bash
set -e  # Exit immediately on error

# Get the directory where this script resides.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#################################
# SPARKLE CONFIGURATION
#################################

# Function to find Sparkle tools (Homebrew first, then manual build)
find_sparkle_tools() {
    echo "Looking for Sparkle tools..."
    
    # Try Homebrew installation first
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix="$(brew --prefix)"
        local sparkle_cask_dir="${brew_prefix}/Caskroom/sparkle"
        
        if [ -d "${sparkle_cask_dir}" ]; then
            # Find the latest version directory
            local latest_version=$(ls -1 "${sparkle_cask_dir}" | sort -V | tail -1)
            local homebrew_tools_dir="${sparkle_cask_dir}/${latest_version}/bin"
            
            if [ -f "${homebrew_tools_dir}/sign_update" ] && [ -f "${homebrew_tools_dir}/generate_appcast" ]; then
                SPARKLE_TOOLS_DIR="${homebrew_tools_dir}"
                echo "✓ Found Homebrew Sparkle tools (${latest_version}): ${SPARKLE_TOOLS_DIR}"
                return 0
            fi
        fi
    fi
    
    # Fallback to manual build in DerivedData
    echo "Homebrew Sparkle not found, checking manual build..."
    local derived_data_base="${HOME}/Library/Developer/Xcode/DerivedData"
    local sparkle_pattern="*/SourcePackages/checkouts/Sparkle/build/*/Build/Products/Release"
    
    for path in ${derived_data_base}/${sparkle_pattern}/sign_update; do
        if [ -f "$path" ]; then
            SPARKLE_TOOLS_DIR="$(dirname "$path")"
            echo "✓ Found manual build Sparkle tools: ${SPARKLE_TOOLS_DIR}"
            return 0
        fi
    done
    
    return 1
}

# Find Sparkle tools
if ! find_sparkle_tools; then
    echo "Error: Sparkle tools not found!" >&2
    echo "Please install Sparkle via Homebrew:" >&2
    echo "  brew install --cask sparkle" >&2
    echo "Or build manually from the SPM checkout." >&2
    exit 1
fi

# Set tool paths
SIGN_UPDATE="${SPARKLE_TOOLS_DIR}/sign_update"
GENERATE_APPCAST="${SPARKLE_TOOLS_DIR}/generate_appcast"

# Verify tools exist
if [ ! -f "${SIGN_UPDATE}" ] || [ ! -f "${GENERATE_APPCAST}" ]; then
    echo "Error: Required Sparkle tools not found in ${SPARKLE_TOOLS_DIR}" >&2
    exit 1
fi

# Appcast configuration (matching your Info.plist)
APPCAST_URL="https://app.qalti.com/appcast.xml"
DOWNLOAD_BASE_URL="https://app.qalti.com/releases"

# Local file paths
APPCAST_FILE="${SCRIPT_DIR}/appcast.xml"
RELEASES_DIR="${SCRIPT_DIR}/releases"

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
# 6. Sign the DMG with Sparkle
##########################################################
echo "Signing DMG for Sparkle updates..."
SIGNATURE_FILE="${OUTPUT_DMG}.sparkle_signature"

# Remove existing signature file if it exists
if [ -f "${SIGNATURE_FILE}" ]; then
    rm -f "${SIGNATURE_FILE}"
fi

# Sign the DMG
"${SIGN_UPDATE}" "${OUTPUT_DMG}" > "${SIGNATURE_FILE}"

if [ ! -f "${SIGNATURE_FILE}" ] || [ ! -s "${SIGNATURE_FILE}" ]; then
    echo "Error: Failed to create signature file" >&2
    exit 1
fi

SIGNATURE=$(cat "${SIGNATURE_FILE}")
echo "DMG signature: ${SIGNATURE}"

##########################################################
# 7. Copy release notes for appcast generation
##########################################################
# Release notes should match the DMG filename for generate_appcast to find them
SOURCE_RELEASE_NOTES="${SCRIPT_DIR}/release_notes.html"
RELEASE_NOTES_FILE="${SCRIPT_DIR}/Qalti-${VERSION}.html"

if [ -f "${SOURCE_RELEASE_NOTES}" ]; then
    echo "Using existing release notes: ${SOURCE_RELEASE_NOTES}"
    cp "${SOURCE_RELEASE_NOTES}" "${RELEASE_NOTES_FILE}"
else
    echo "Warning: ${SOURCE_RELEASE_NOTES} not found, appcast may not include release notes" >&2
fi

##########################################################
# 8. Generate/update appcast.xml
##########################################################
echo "Generating/updating appcast.xml..."

# Create releases directory structure for appcast generation
if [ ! -d "${RELEASES_DIR}" ]; then
    mkdir -p "${RELEASES_DIR}"
fi

# Copy DMG to DMGCreator directory temporarily for appcast generation
TEMP_DMG="${SCRIPT_DIR}/Qalti-${VERSION}.dmg"
cp "${OUTPUT_DMG}" "${TEMP_DMG}"

# Generate appcast directly in DMGCreator directory
"${GENERATE_APPCAST}" \
    --download-url-prefix "${DOWNLOAD_BASE_URL}/" \
    --release-notes-url-prefix "https://app.qalti.com/releases/" \
    "${SCRIPT_DIR}"

# Check if appcast was generated
if [ -f "${APPCAST_FILE}" ]; then
    echo "Appcast updated: ${APPCAST_FILE}"
else
    echo "Warning: appcast.xml was not generated" >&2
fi

# Clean up temporary DMG from DMGCreator directory
if [ -f "${TEMP_DMG}" ]; then
    rm -f "${TEMP_DMG}"
fi

# Copy release notes to Downloads directory alongside DMG
if [ -f "${SOURCE_RELEASE_NOTES}" ]; then
    echo "Copying release notes to Downloads: ${OUTPUT_RELEASE_NOTES}"
    cp "${SOURCE_RELEASE_NOTES}" "${OUTPUT_RELEASE_NOTES}"
fi

# Clean up temporary version-specific release notes file
if [ -f "${RELEASE_NOTES_FILE}" ]; then
    echo "Cleaning up temporary release notes: ${RELEASE_NOTES_FILE}"
    rm -f "${RELEASE_NOTES_FILE}"
fi

# Clean up any appcast file that might have been created in releases directory
if [ -f "${RELEASES_DIR}/appcast.xml" ]; then
    echo "Cleaning up appcast from releases directory: ${RELEASES_DIR}/appcast.xml"
    rm -f "${RELEASES_DIR}/appcast.xml"
fi

##########################################################
# 9. Display summary information
##########################################################
echo ""
echo "========================================"
echo "RELEASE SUMMARY"
echo "========================================"
echo "Version: ${VERSION} (build ${BUILD_NUMBER})"
echo "DMG: ${OUTPUT_DMG}"
echo "Signature: ${SIGNATURE}"
echo "Appcast: ${APPCAST_FILE}"
echo "Release notes (original): ${SOURCE_RELEASE_NOTES}"
if [ -f "${OUTPUT_RELEASE_NOTES}" ]; then
    echo "Release notes (for upload): ${OUTPUT_RELEASE_NOTES}"
fi
echo "Sparkle tools: ${SPARKLE_TOOLS_DIR}"
echo ""
echo "Next steps:"
echo "1. Upload ${OUTPUT_DMG} to: ${DOWNLOAD_BASE_URL}/"
if [ -f "${OUTPUT_RELEASE_NOTES}" ]; then
    echo "2. Upload ${OUTPUT_RELEASE_NOTES} to: ${DOWNLOAD_BASE_URL}/"
    echo "3. Upload ${APPCAST_FILE} to: ${APPCAST_URL}"
    echo "4. Update release notes if needed: ${SOURCE_RELEASE_NOTES}"
    echo "5. Test the update mechanism"
else
    echo "2. Upload ${APPCAST_FILE} to: ${APPCAST_URL}"
    echo "3. Update release notes if needed: ${SOURCE_RELEASE_NOTES}"
    echo "4. Test the update mechanism"
fi
echo "========================================"

#######################
# 10. Cleanup app_folder
#######################
if [ -d "${APP_FOLDER}/Qalti.app" ]; then
    echo "Cleaning up: Removing ${APP_FOLDER}/Qalti.app"
    rm -rf "${APP_FOLDER}/Qalti.app"
fi

# Clean up any remaining temporary files
# (TEMP_DMG already cleaned up above)

echo "Done!"
