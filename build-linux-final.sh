#!/bin/bash
set -e

cd /mnt/e/PPROJECTS/scn

# Install dependencies
echo "Installing required tools..."
sudo apt-get update -qq
sudo apt-get install -y unzip curl git clang cmake ninja-build pkg-config libgtk-3-dev

# Install Flutter if needed
if [ ! -d "$HOME/flutter" ]; then
    echo "Installing Flutter..."
    cd ~
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    cd /mnt/e/PPROJECTS/scn
fi

# Add Flutter to PATH (must be after installation check)
export PATH="$PATH:$HOME/flutter/bin"

# Accept Flutter licenses
flutter doctor --android-licenses 2>&1 | head -n 5 || true

# Verify Flutter
echo "Flutter path: $(which flutter)"
flutter --version | head -n 1

# Run build
chmod +x build.sh
bash build.sh

echo ""
echo "Build complete! Checking results..."
if [ -f "scn-release-linux/scn" ]; then
    echo "✅ Linux build successful!"
    ls -lh scn-release-linux/scn
else
    echo "❌ Build failed - executable not found"
    exit 1
fi

