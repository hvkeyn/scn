#!/bin/bash
#
# SCN Build Script - полностью автономная сборка для Linux
#
# Автоматически устанавливает Flutter если нужно и собирает проект
#
# Usage:
#   ./build.sh              # Build for Linux (default)
#   ./build.sh --windows    # Build for Windows (cross-compile)
#   ./build.sh --all        # Build all platforms
#   ./build.sh --clean      # Clean before building
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCN_DIR="$PROJECT_DIR/scn"
FLUTTER_DIR="$PROJECT_DIR/flutter-sdk"
RELEASES_DIR="$PROJECT_DIR/releases"
FLUTTER_VERSION="3.24.5"

echo ""
echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}       SCN Build Script${NC}"
echo -e "${YELLOW}======================================${NC}"

# Install dependencies
install_deps() {
    echo -e "\n${CYAN}>> Installing build dependencies...${NC}"
    
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq \
            curl git unzip xz-utils zip \
            clang cmake ninja-build pkg-config \
            libgtk-3-dev liblzma-dev libstdc++-12-dev \
            2>/dev/null || true
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm \
            curl git unzip zip \
            clang cmake ninja pkgconf gtk3 \
            2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y \
            curl git unzip zip \
            clang cmake ninja-build pkgconfig gtk3-devel \
            2>/dev/null || true
    fi
    
    echo -e "   ${GREEN}[OK]${NC} Dependencies installed"
}

# Find or install Flutter
get_flutter() {
    echo -e "\n${CYAN}>> Checking Flutter...${NC}"
    
    # 1. Check system Flutter
    if command -v flutter &>/dev/null; then
        echo -e "   ${GREEN}[OK]${NC} System Flutter: $(which flutter)"
        echo "flutter"
        return 0
    fi
    
    # 2. Check local Flutter SDK
    if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
        if "$FLUTTER_DIR/bin/dart" --version &>/dev/null; then
            echo -e "   ${GREEN}[OK]${NC} Local Flutter SDK"
            echo "$FLUTTER_DIR/bin/flutter"
            return 0
        fi
        # SDK broken
        echo -e "   ${YELLOW}Local SDK broken, reinstalling...${NC}"
        rm -rf "$FLUTTER_DIR"
    fi
    
    # 3. Install Flutter
    echo -e "   ${YELLOW}Flutter not found. Installing...${NC}"
    
    install_deps
    
    local FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
    local FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER_TAR"
    
    echo -e "   ${GRAY}Downloading Flutter $FLUTTER_VERSION...${NC}"
    
    cd "$PROJECT_DIR"
    curl -LO "$FLUTTER_URL" 2>/dev/null || wget -q "$FLUTTER_URL"
    
    echo -e "   ${GRAY}Extracting...${NC}"
    tar xf "$FLUTTER_TAR"
    mv flutter "$FLUTTER_DIR"
    rm -f "$FLUTTER_TAR"
    
    # Enable Linux desktop
    "$FLUTTER_DIR/bin/flutter" config --enable-linux-desktop 2>/dev/null || true
    "$FLUTTER_DIR/bin/flutter" precache --linux 2>/dev/null || true
    
    echo -e "   ${GREEN}[OK]${NC} Flutter installed successfully!"
    echo "$FLUTTER_DIR/bin/flutter"
}

# Update version
update_version() {
    local pubspec="$SCN_DIR/pubspec.yaml"
    local version=$(grep -oP 'version:\s*\K\d+\.\d+\.\d+\+\d+' "$pubspec" 2>/dev/null || echo "")
    
    if [ -n "$version" ]; then
        local base=$(echo "$version" | cut -d'+' -f1)
        local build=$(echo "$version" | cut -d'+' -f2)
        local new_build=$((build + 1))
        local new_version="${base}+${new_build}"
        
        sed -i "s/version:.*/version: $new_version/" "$pubspec"
        echo -e "\n${MAGENTA}Version: $new_version${NC}"
    fi
}

# Build Linux
build_linux() {
    local FL="$1"
    
    echo -e "\n${CYAN}>> Building Linux...${NC}"
    
    mkdir -p "$RELEASES_DIR/linux"
    cd "$SCN_DIR"
    
    if [ "$CLEAN" = "1" ]; then
        echo -e "   ${GRAY}Cleaning...${NC}"
        $FL clean >/dev/null 2>&1 || true
    fi
    
    echo -e "   ${GRAY}Getting dependencies...${NC}"
    $FL pub get
    
    echo -e "   ${GRAY}Building release...${NC}"
    $FL build linux --release
    
    if [ -f "build/linux/x64/release/bundle/scn" ]; then
        cp -r build/linux/x64/release/bundle/* "$RELEASES_DIR/linux/"
        local SIZE=$(du -h "$RELEASES_DIR/linux/scn" | cut -f1)
        echo -e "   ${GREEN}[OK]${NC} Linux build complete ($SIZE)"
        echo -e "   ${GRAY}Output: $RELEASES_DIR/linux/scn${NC}"
        return 0
    fi
    
    echo -e "   ${RED}[FAIL]${NC} Linux build failed"
    return 1
}

# Build Windows (cross-compile - limited support)
build_windows() {
    local FL="$1"
    
    echo -e "\n${CYAN}>> Building Windows...${NC}"
    echo -e "   ${YELLOW}Note: Cross-compilation from Linux has limited support${NC}"
    echo -e "   ${YELLOW}For best results, build on Windows using build.ps1${NC}"
    
    # Check if wine is available for cross-compile
    if ! command -v wine &>/dev/null; then
        echo -e "   ${RED}[FAIL]${NC} Wine not installed (required for cross-compile)"
        return 1
    fi
    
    mkdir -p "$RELEASES_DIR/windows"
    cd "$SCN_DIR"
    
    $FL pub get
    $FL build windows --release 2>&1 || {
        echo -e "   ${RED}[FAIL]${NC} Windows cross-compile not available"
        return 1
    }
    
    if [ -f "build/windows/x64/runner/Release/scn.exe" ]; then
        cp -r build/windows/x64/runner/Release/* "$RELEASES_DIR/windows/"
        echo -e "   ${GREEN}[OK]${NC} Windows build complete"
        return 0
    fi
    
    echo -e "   ${RED}[FAIL]${NC} Windows build failed"
    return 1
}

# ==================== MAIN ====================

# Parse arguments
BUILD_LINUX=0
BUILD_WINDOWS=0
CLEAN=0

for arg in "$@"; do
    case $arg in
        --linux|-l) BUILD_LINUX=1 ;;
        --windows|-w) BUILD_WINDOWS=1 ;;
        --all|-a) BUILD_LINUX=1; BUILD_WINDOWS=1 ;;
        --clean|-c) CLEAN=1 ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "  --linux, -l    Build for Linux"
            echo "  --windows, -w  Build for Windows (cross-compile)"
            echo "  --all, -a      Build all platforms"
            echo "  --clean, -c    Clean before building"
            exit 0
            ;;
    esac
done

# Default: Linux only
if [ "$BUILD_LINUX" = "0" ] && [ "$BUILD_WINDOWS" = "0" ]; then
    BUILD_LINUX=1
fi

# Get Flutter
FLUTTER=$(get_flutter)

if [ -z "$FLUTTER" ]; then
    echo -e "\n${RED}[ERROR]${NC} Cannot install Flutter!"
    echo -e "  ${GRAY}Please install manually: https://docs.flutter.dev/get-started/install${NC}"
    exit 1
fi

update_version

# Execute builds
LINUX_OK=0
WINDOWS_OK=0

if [ "$BUILD_LINUX" = "1" ]; then
    build_linux "$FLUTTER" && LINUX_OK=1
fi

if [ "$BUILD_WINDOWS" = "1" ]; then
    build_windows "$FLUTTER" && WINDOWS_OK=1
fi

# Summary
echo -e "\n${YELLOW}======================================${NC}"
echo -e "${YELLOW}       Summary${NC}"
echo -e "${YELLOW}======================================${NC}"

EXIT_CODE=0

if [ "$BUILD_LINUX" = "1" ]; then
    if [ "$LINUX_OK" = "1" ]; then
        echo -e "   ${GREEN}[OK]${NC} Linux"
    else
        echo -e "   ${RED}[FAIL]${NC} Linux"
        EXIT_CODE=1
    fi
fi

if [ "$BUILD_WINDOWS" = "1" ]; then
    if [ "$WINDOWS_OK" = "1" ]; then
        echo -e "   ${GREEN}[OK]${NC} Windows"
    else
        echo -e "   ${RED}[FAIL]${NC} Windows"
        EXIT_CODE=1
    fi
fi

echo ""
exit $EXIT_CODE
