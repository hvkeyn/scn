#!/bin/bash
# Script to run Linux build in WSL

export PATH="$PATH:$HOME/flutter/bin"

cd /mnt/e/PPROJECTS/scn

echo "Current directory: $(pwd)"
echo "Flutter path: $(which flutter || echo 'Flutter not in PATH')"

# Install Flutter if needed
if [ ! -d "$HOME/flutter" ]; then
    echo "Installing Flutter..."
    cd ~
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    cd /mnt/e/PPROJECTS/scn
fi

# Make build script executable
chmod +x build.sh

# Run build
./build.sh

