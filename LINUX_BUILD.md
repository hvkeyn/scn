# Linux Build Instructions for SCN

## Prerequisites

1. **Install Ubuntu WSL** (if not already installed):
   ```powershell
   wsl --install -d Ubuntu
   ```

2. **Install Flutter in WSL**:
   ```bash
   # In WSL Ubuntu
   cd ~
   git clone https://github.com/flutter/flutter.git -b stable
   export PATH="$PATH:`pwd`/flutter/bin"
   flutter doctor
   ```

3. **Install Linux dependencies**:
   ```bash
   sudo apt update
   sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev
   ```

## Building

1. **Open WSL Ubuntu**:
   ```powershell
   wsl -d Ubuntu
   ```

2. **Navigate to project**:
   ```bash
   cd /mnt/e/PPROJECTS/scn
   # Or if /mnt/e doesn't work:
   cd /mnt/host/e/PPROJECTS/scn
   ```

3. **Run build script**:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

## Alternative: Use build.ps1 from Windows

The build.ps1 script will attempt to use WSL automatically, but you need:
- Ubuntu WSL installed (not just docker-desktop)
- Flutter installed in WSL

