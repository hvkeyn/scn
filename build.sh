#!/bin/bash

# SCN Build Script for Linux
# Usage: ./build.sh [options]
# Can be run in WSL or native Linux

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
PLATFORM="linux"
CLEAN=true
SKIP_BUILD_RUNNER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-clean)
            CLEAN=false
            shift
            ;;
        --skip-build-runner)
            SKIP_BUILD_RUNNER=true
            shift
            ;;
        --help)
            echo "Usage: ./build.sh [options]"
            echo "Options:"
            echo "  --no-clean              Don't clean before build"
            echo "  --skip-build-runner     Skip build_runner"
            echo "  --help                  Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Functions
info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check Flutter - try multiple locations
FLUTTER_CMD=""
if command -v flutter &> /dev/null; then
    FLUTTER_CMD="flutter"
elif [ -f "../submodules/flutter/bin/flutter" ]; then
    FLUTTER_CMD="../submodules/flutter/bin/flutter"
elif [ -f "../../submodules/flutter/bin/flutter" ]; then
    FLUTTER_CMD="../../submodules/flutter/bin/flutter"
elif [ -f "$HOME/flutter/bin/flutter" ]; then
    FLUTTER_CMD="$HOME/flutter/bin/flutter"
elif [ -f "/mnt/host/e/PPROJECTS/scn/submodules/flutter/bin/flutter" ]; then
    FLUTTER_CMD="/mnt/host/e/PPROJECTS/scn/submodules/flutter/bin/flutter"
else
    error "Flutter not found! Please install Flutter SDK or ensure it's in PATH."
    error "Tried: flutter command, ../submodules/flutter/bin/flutter"
    exit 1
fi

info "Using Flutter: $($FLUTTER_CMD --version 2>&1 | head -n 1 || echo 'version check failed')"

# Navigate to project directory
if [ ! -f "scn/pubspec.yaml" ]; then
    error "Project not found at scn/"
    exit 1
fi

cd scn

# Increment build version
info "Incrementing build version..."
if [ -f "pubspec.yaml" ]; then
    VERSION_LINE=$(grep -E '^version:' pubspec.yaml | head -n 1)
    if [[ $VERSION_LINE =~ version:[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+) ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        PATCH=${BASH_REMATCH[3]}
        BUILD=${BASH_REMATCH[4]}
        BUILD=$((BUILD + 1))
        NEW_VERSION="$MAJOR.$MINOR.$PATCH+$BUILD"
        sed -i "s/^version:.*/version: $NEW_VERSION/" pubspec.yaml
        info "Version updated to: $NEW_VERSION"
    else
        warning "Could not parse version from pubspec.yaml: $VERSION_LINE"
    fi
fi

# Clean
if [ "$CLEAN" = true ]; then
    info "Cleaning project..."
    $FLUTTER_CMD clean > /dev/null 2>&1
    
    if [ -d "build/linux" ]; then
        rm -rf build/linux
    fi
fi

# Get dependencies
info "Getting dependencies..."
$FLUTTER_CMD pub get
if [ $? -ne 0 ]; then
    error "Failed to get dependencies"
    exit 1
fi

# Build
info "Building Linux application..."
$FLUTTER_CMD build linux --release
if [ $? -ne 0 ]; then
    error "Flutter build failed"
    exit 1
fi

success "Linux build completed!"

# Show output location
BUILD_PATH="build/linux/x64/release/bundle"
EXECUTABLE="$BUILD_PATH/scn"
if [ -f "$EXECUTABLE" ]; then
    info "Executable: $(realpath $EXECUTABLE)"
fi

# Create release package
info "Creating release package..."
RELEASE_DIR="../scn-release-linux"
if [ -d "$RELEASE_DIR" ]; then
    rm -rf "$RELEASE_DIR"
fi
mkdir -p "$RELEASE_DIR"

# Copy files
cp -r "$BUILD_PATH"/* "$RELEASE_DIR/"

# Make executable
if [ -f "$RELEASE_DIR/scn" ]; then
    chmod +x "$RELEASE_DIR/scn"
fi

# Create README
cat > "$RELEASE_DIR/README.txt" << 'EOF'
SCN - Linux Release Package
===========================

This folder contains all necessary files to run SCN on Linux.

STRUCTURE:
----------
- scn                    - Main executable
- lib/                   - Application libraries
- data/                  - Application data
  - flutter_assets/     - Resources

RUN:
----
Make executable (if needed):
  chmod +x scn

Run:
  ./scn

REQUIREMENTS:
-------------
- Linux (Ubuntu 20.04+, Debian 11+, or similar)
- GTK 3.0 or higher
- glibc 2.31 or higher

NOTES:
------
- All files must remain in this folder
- Do not move individual files - application will not start
- The data/ folder contains critical files

VERSION:
--------
SCN 1.0.0
Secure Connection Network - Simplified version without Rust dependencies
EOF

RELEASE_FULL_PATH=$(realpath "$RELEASE_DIR")
success "Release package created at: $RELEASE_FULL_PATH"

# Calculate size
TOTAL_SIZE=$(du -sh "$RELEASE_DIR" | cut -f1)
info "Total package size: $TOTAL_SIZE"

cd ..

success "All builds completed successfully!"

