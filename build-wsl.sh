#!/bin/sh
# Wrapper script to run build.sh in WSL
# This script finds the correct path and runs the build

# Try different possible paths
PATHS="/mnt/e/PPROJECTS/scn /mnt/host/e/PPROJECTS/scn /host_mnt/e/PPROJECTS/scn"

for path in $PATHS; do
    if [ -d "$path" ]; then
        echo "Found project at: $path"
        cd "$path"
        chmod +x build.sh
        ./build.sh
        exit $?
    fi
done

echo "Could not find project directory"
exit 1