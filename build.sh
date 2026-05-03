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
SUDO_USER_NAME="${SUDO_USER:-}"

echo ""
echo -e "${YELLOW}======================================${NC}"
echo -e "${YELLOW}       SCN Build Script${NC}"
echo -e "${YELLOW}======================================${NC}"

run_without_root_if_needed() {
    if [ "$(id -u)" -ne 0 ]; then
        return 0
    fi

    if [ -n "$SUDO_USER_NAME" ] && [ "$SUDO_USER_NAME" != "root" ] && command -v sudo &>/dev/null; then
        echo -e "   ${YELLOW}[WARN]${NC} Build was started as root; restarting as $SUDO_USER_NAME for Flutter."
        local group
        group="$(id -gn "$SUDO_USER_NAME" 2>/dev/null || echo "$SUDO_USER_NAME")"
        chown -R "$SUDO_USER_NAME:$group" "$PROJECT_DIR" 2>/dev/null || true
        exec env -u TMPDIR -u TMP -u TEMP \
            sudo -H -u "$SUDO_USER_NAME" \
            env TMPDIR=/tmp TMP=/tmp TEMP=/tmp bash "$0" "$@"
    fi

    echo -e "   ${RED}[FAIL]${NC} Do not run Flutter build as root."
    echo -e "   ${GRAY}Run: ./build.sh --linux${NC}"
    exit 1
}

prepare_user_environment() {
    local tmp="${TMPDIR:-}"
    if [ -z "$tmp" ] || [ ! -d "$tmp" ] || [ ! -w "$tmp" ] || [ "$tmp" = "/tmp/.private/root" ]; then
        local private_tmp="/tmp/.private/$(id -un 2>/dev/null || echo user)"
        if [ -d "$private_tmp" ] && [ -w "$private_tmp" ]; then
            tmp="$private_tmp"
        else
            tmp="/tmp"
        fi
    fi

    export TMPDIR="$tmp"
    export TMP="$tmp"
    export TEMP="$tmp"
    export FLUTTER_SUPPRESS_ANALYTICS=true
    export DART_SUPPRESS_ANALYTICS=true
}

configure_flutter() {
    local FL="$1"
    "$FL" --disable-analytics >/dev/null 2>&1 || true
    "$FL" config --no-analytics >/dev/null 2>&1 || true
    "$FL" config --no-cli-animations >/dev/null 2>&1 || true
}

run_with_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        echo -e "   ${RED}[FAIL]${NC} sudo is required to install build dependencies." >&2
        return 1
    fi
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "   ${RED}[FAIL]${NC} Required command not found: $cmd" >&2
        return 1
    fi
}

pkg_config_exists_any() {
    local module
    for module in "$@"; do
        if pkg-config --exists "$module"; then
            return 0
        fi
    done
    return 1
}

apt_install_any() {
    local label="$1"
    shift

    local pkg
    for pkg in "$@"; do
        if run_with_sudo apt-get install -y -qq "$pkg"; then
            return 0
        fi
    done

    echo -e "   ${RED}[FAIL]${NC} Unable to install $label. Tried packages: $*" >&2
    return 1
}

apt_install_optional_any() {
    local label="$1"
    shift

    local pkg
    for pkg in "$@"; do
        if run_with_sudo apt-get install -y -qq "$pkg"; then
            return 0
        fi
    done

    echo -e "   ${YELLOW}[WARN]${NC} Optional dependency was not installed: $label ($*)"
    return 0
}

# Install dependencies
install_deps() {
    echo -e "\n${CYAN}>> Installing build dependencies...${NC}"

    local need_install=0
    for cmd in curl git unzip tar xz clang cmake ninja pkg-config; do
        if ! command -v "$cmd" &>/dev/null; then
            need_install=1
        fi
    done
    if command -v pkg-config &>/dev/null && ! pkg-config --exists gtk+-3.0; then
        need_install=1
    fi
    if command -v pkg-config &>/dev/null && ! pkg-config --exists libpcre2-8; then
        need_install=1
    fi
    if command -v pkg-config &>/dev/null &&
        ! pkg_config_exists_any ayatana-appindicator3-0.1 appindicator3-0.1; then
        need_install=1
    fi

    if [ "$need_install" = "0" ]; then
        echo -e "   ${GREEN}[OK]${NC} Dependencies already installed"
        return 0
    fi
    
    if command -v apt-get &>/dev/null; then
        run_with_sudo apt-get update -qq
        apt_install_any curl curl
        apt_install_any git git
        apt_install_any unzip unzip
        apt_install_any zip zip
        apt_install_any xz xz-utils xz
        apt_install_any clang clang
        apt_install_any cmake cmake
        apt_install_any ninja ninja-build ninja
        apt_install_any pkg-config pkg-config pkgconfig
        apt_install_any "GTK 3 development files" libgtk-3-dev libgtk+3-devel gtk3-devel
        apt_install_any "PCRE2 development files" libpcre2-dev libpcre2-devel pcre2-devel
        apt_install_any "AppIndicator development files" \
            libayatana-appindicator3-dev libayatana-appindicator3-devel \
            libayatana-appindicator-gtk3-devel ayatana-appindicator3-devel \
            libappindicator3-dev libappindicator3-devel \
            libappindicator-gtk3-devel appindicator3-devel libappindicator-devel
        apt_install_optional_any "liblzma development files" liblzma-dev liblzma-devel
        apt_install_optional_any "libstdc++ development files" libstdc++-12-dev libstdc++-devel
    elif command -v pacman &>/dev/null; then
        run_with_sudo pacman -Sy --noconfirm \
            curl git unzip zip xz \
            clang cmake ninja pkgconf gtk3 pcre2 libayatana-appindicator
    elif command -v dnf &>/dev/null; then
        run_with_sudo dnf install -y \
            curl git unzip zip xz \
            clang cmake ninja-build pkgconfig gtk3-devel pcre2-devel \
            libayatana-appindicator-gtk3-devel
    elif command -v zypper &>/dev/null; then
        run_with_sudo zypper --non-interactive install \
            curl git unzip zip xz \
            clang cmake ninja pkg-config gtk3-devel pcre2-devel \
            libayatana-appindicator3-devel
    else
        echo -e "   ${YELLOW}[WARN]${NC} Unknown package manager. Install manually: curl git unzip tar xz clang cmake ninja pkg-config GTK 3 dev libraries"
    fi

    require_command curl
    require_command git
    require_command unzip
    require_command tar
    require_command xz
    require_command clang
    require_command cmake
    require_command ninja
    require_command pkg-config
    if ! pkg-config --exists gtk+-3.0; then
        echo -e "   ${RED}[FAIL]${NC} GTK 3 development files were not found (pkg-config gtk+-3.0)." >&2
        return 1
    fi
    if ! pkg-config --exists libpcre2-8; then
        echo -e "   ${RED}[FAIL]${NC} PCRE2 development files were not found (pkg-config libpcre2-8)." >&2
        return 1
    fi
    if ! pkg_config_exists_any ayatana-appindicator3-0.1 appindicator3-0.1; then
        echo -e "   ${RED}[FAIL]${NC} AppIndicator development files were not found." >&2
        echo -e "   ${GRAY}Need pkg-config module: ayatana-appindicator3-0.1 or appindicator3-0.1${NC}" >&2
        return 1
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
    configure_flutter "$FLUTTER_DIR/bin/flutter"
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
        rm -rf "$RELEASES_DIR/linux"
        mkdir -p "$RELEASES_DIR/linux"
        cp -a build/linux/x64/release/bundle/. "$RELEASES_DIR/linux/"
        chmod +x "$RELEASES_DIR/linux/scn"
        cat > "$RELEASES_DIR/linux/run_scn.sh" <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
chmod +x ./scn 2>/dev/null || true
exec ./scn "$@"
EOF
        chmod +x "$RELEASES_DIR/linux/run_scn.sh"
        cat > "$RELEASES_DIR/linux/README_LINUX.txt" <<'EOF'
SCN Linux bundle

Run from this directory:
  ./scn

If the executable bit was lost after copying/unzipping:
  chmod +x ./scn
  ./scn

Or use:
  bash run_scn.sh
EOF
        tar -C "$RELEASES_DIR" -czf "$RELEASES_DIR/scn-linux-x64.tar.gz" linux
        local SIZE=$(du -h "$RELEASES_DIR/linux/scn" | cut -f1)
        echo -e "   ${GREEN}[OK]${NC} Linux build complete ($SIZE)"
        echo -e "   ${GRAY}Output: $RELEASES_DIR/linux/scn${NC}"
        echo -e "   ${GRAY}Archive: $RELEASES_DIR/scn-linux-x64.tar.gz${NC}"
        echo -e "   ${GRAY}Run: cd $RELEASES_DIR/linux && ./scn${NC}"
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

run_without_root_if_needed "$@"
prepare_user_environment

# Default: Linux only
if [ "$BUILD_LINUX" = "0" ] && [ "$BUILD_WINDOWS" = "0" ]; then
    BUILD_LINUX=1
fi

install_deps

# Get Flutter. The helper prints progress messages, so keep only its final
# line as the executable path while still showing progress in the terminal.
FLUTTER=$(get_flutter | tee /dev/stderr | tail -n 1)

if [ -z "$FLUTTER" ]; then
    echo -e "\n${RED}[ERROR]${NC} Cannot install Flutter!"
    echo -e "  ${GRAY}Please install manually: https://docs.flutter.dev/get-started/install${NC}"
    exit 1
fi
configure_flutter "$FLUTTER"

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
