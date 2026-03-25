#!/bin/bash
# Xcode-compatible build script
# Enhanced with optional derived data cleaning

set -e

# Parse command line arguments
CLEAN_BUILD=true
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-clean)
            CLEAN_BUILD=false
            shift
            ;;
        --help|-h)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ $HELP == true ]]; then
    echo "🍎 Xcode-Compatible Build Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --no-clean    Skip cleaning DerivedData (faster incremental builds)"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                # Clean build (default)"
    echo "  $0 --no-clean    # Incremental build (faster)"
    exit 0
fi

echo "🔧 Setting up Xcode-compatible build environment..."

# Use Xcode's environment settings
export DEVELOPER_DIR="$(xcode-select -p)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$DEVELOPER_DIR/usr/bin:$DEVELOPER_DIR/Tools"

# Remove rbenv/gem paths that cause xcpretty issues
export PATH=$(echo $PATH | tr ':' '\n' | grep -v rbenv | grep -v gem | tr '\n' ':')

# Set locale properly 
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo "🚀 Building with Xcode-like environment..."

cd "$(dirname "$0")/.."  # Go to repo root

# Conditional clean build
if [[ $CLEAN_BUILD == true ]]; then
    if [ -d "xcodeproject/DerivedData_local" ]; then
        echo "🧹 Cleaning previous build (use --no-clean to skip)..."
        rm -rf xcodeproject/DerivedData_local
    fi
else
    echo "🏗️  Running incremental build (DerivedData preserved)..."
fi

# Build with minimal PATH (like Xcode)
xcodebuild \
  -project xcodeproject/Qalti.xcodeproj \
  -scheme Qalti \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath xcodeproject/DerivedData_local \
  build

echo "✅ Build completed successfully!"
echo "📍 App location: xcodeproject/DerivedData_local/Build/Products/Debug/Qalti.app"