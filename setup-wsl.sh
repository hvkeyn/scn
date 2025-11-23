#!/bin/bash
# Setup script for WSL Ubuntu

set -e

echo "Setting up Flutter in WSL..."

# Install Flutter
if [ ! -d "$HOME/flutter" ]; then
    echo "Cloning Flutter..."
    cd ~
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Install dependencies
echo "Installing Linux dependencies..."
sudo apt update -qq
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev

# Verify Flutter
echo "Verifying Flutter installation..."
flutter --version | head -n 1

echo "Setup complete!"

