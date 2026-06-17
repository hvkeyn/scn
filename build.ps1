<#
.SYNOPSIS
    SCN Build Script - полностью автономная сборка

.DESCRIPTION
    Автоматически устанавливает Flutter если нужно и собирает проект

.PARAMETER Windows
    Build for Windows

.PARAMETER Linux  
    Build for Linux (requires WSL)

.PARAMETER All
    Build for all platforms

.PARAMETER Clean
    Clean before building

.EXAMPLE
    .\build.ps1              # Windows (default)
    .\build.ps1 -All         # All platforms
#>

param(
    [switch]$Windows,
    [switch]$Linux,
    [switch]$All,
    [switch]$Clean
)

$ErrorActionPreference = "Continue"

# Paths
$ProjectDir = $PSScriptRoot
$ScnDir = Join-Path $ProjectDir "scn"
$FlutterDir = Join-Path $ProjectDir "flutter-sdk"
$ReleasesDir = Join-Path $ProjectDir "releases"
$FlutterVersion = "3.24.5"
$FlutterZipUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
$env:DART_SUPPRESS_ANALYTICS = "true"

Write-Host ""
Write-Host "======================================" -ForegroundColor Yellow
Write-Host "       SCN Build Script" -ForegroundColor Yellow  
Write-Host "======================================" -ForegroundColor Yellow

function Configure-Flutter {
    param([string]$Flutter)

    & $Flutter --disable-analytics 2>$null | Out-Null
    & $Flutter config --no-analytics 2>$null | Out-Null
    & $Flutter config --no-cli-animations 2>$null | Out-Null
}

# Чистит pub-кеши, где Flutter 3.24.5 пишет битые JSON без поля
# advisoriesUpdated. Из-за этого readAdvisoriesFromCache падает с
# "Null check operator used on a null value". Удаляем:
#  - <pub-cache>/advisories          (новый формат, если есть)
#  - <pub-cache>/hosted/pub.dev/.cache (versions/advisories per package)
function Reset-PubAdvisoriesCache {
    $cacheRoots = @()
    if ($env:PUB_CACHE) { $cacheRoots += $env:PUB_CACHE }
    if ($env:LOCALAPPDATA) { $cacheRoots += (Join-Path $env:LOCALAPPDATA "Pub\Cache") }
    if ($env:APPDATA) { $cacheRoots += (Join-Path $env:APPDATA "Pub\Cache") }
    if ($env:USERPROFILE) { $cacheRoots += (Join-Path $env:USERPROFILE ".pub-cache") }

    $cleared = $false
    foreach ($root in $cacheRoots | Select-Object -Unique) {
        if (-not (Test-Path $root)) { continue }

        $advisories = Join-Path $root "advisories"
        if (Test-Path $advisories) {
            try {
                Remove-Item -Recurse -Force $advisories -ErrorAction Stop
                Write-Host "   Cleared $advisories" -ForegroundColor Gray
                $cleared = $true
            } catch {
                Write-Host "   [WARN] Could not clear $advisories : $_" -ForegroundColor Yellow
            }
        }

        $hostedCache = Join-Path $root "hosted\pub.dev\.cache"
        if (Test-Path $hostedCache) {
            try {
                Get-ChildItem -Path $hostedCache -Filter "*.json" -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction Stop
                Write-Host "   Cleared $hostedCache" -ForegroundColor Gray
                $cleared = $true
            } catch {
                Write-Host "   [WARN] Could not clear $hostedCache : $_" -ForegroundColor Yellow
            }
        }
    }
    return $cleared
}

# Запускает `flutter pub get` и при характерной для Flutter 3.24.5
# ошибке (Null check operator used on a null value в readAdvisoriesFromCache)
# чистит кеш и повторяет один раз.
function Invoke-PubGet {
    param(
        [string]$Flutter,
        [string]$Cwd
    )

    Push-Location $Cwd
    try {
        $out = & $Flutter pub get 2>&1
        $exit = $LASTEXITCODE
        $out | ForEach-Object { Write-Host $_ }
        if ($exit -eq 0) { return $true }

        $joined = ($out | Out-String)
        $isAdvisoryBug = ($joined -match "readAdvisoriesFromCache" ) -or
                        ($joined -match "advisoriesUpdated must be a String") -or
                        ($joined -match "Null check operator used on a null value")
        if (-not $isAdvisoryBug) {
            return $false
        }

        Write-Host "   Detected pub advisories cache bug; clearing cache and retrying..." -ForegroundColor Yellow
        Reset-PubAdvisoriesCache | Out-Null

        # Доп. флаг отключает онлайн-проверку advisories во время решения.
        $env:PUB_ALLOW_PRERELEASE_SDK = "quiet"
        $out2 = & $Flutter pub get --no-precompile 2>&1
        $exit2 = $LASTEXITCODE
        $out2 | ForEach-Object { Write-Host $_ }
        if ($exit2 -eq 0) { return $true }

        $joined2 = ($out2 | Out-String)
        if ($joined2 -match "readAdvisoriesFromCache" -or
            $joined2 -match "advisoriesUpdated must be a String" -or
            $joined2 -match "Null check operator used on a null value") {
            Write-Host "   Pub advisories bug persists; trying offline mode..." -ForegroundColor Yellow
            Reset-PubAdvisoriesCache | Out-Null
            $out3 = & $Flutter pub get --offline 2>&1
            $exit3 = $LASTEXITCODE
            $out3 | ForEach-Object { Write-Host $_ }
            if ($exit3 -eq 0) { return $true }
        }

        return $false
    } finally {
        Pop-Location
    }
}

# Kill processes
function Clear-Processes {
    Get-Process -Name "dart", "flutter", "pub" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

function Stop-SCNProcesses {
    $running = Get-Process -Name "scn" -ErrorAction SilentlyContinue
    if (-not $running) {
        return $true
    }

    Write-Host "   Stopping running SCN before copying release..." -ForegroundColor Gray
    foreach ($proc in $running) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            Write-Host "   [FAIL] Cannot stop scn.exe (PID $($proc.Id)): $_" -ForegroundColor Red
            Write-Host "   Close SCN manually or run this script as Administrator, then rebuild." -ForegroundColor Yellow
            return $false
        }
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name "scn" -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 300
            return $true
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host "   [FAIL] scn.exe is still running; release files are locked." -ForegroundColor Red
    Write-Host "   Close SCN manually or run this script as Administrator, then rebuild." -ForegroundColor Yellow
    return $false
}

function Copy-ReleaseDirectory {
    param(
        [string]$SourceDir,
        [string]$OutDir
    )

    $tmpDir = Join-Path $ReleasesDir ("windows.tmp-" + [guid]::NewGuid().ToString("N"))
    $oldDir = Join-Path $ReleasesDir ("windows.old-" + [guid]::NewGuid().ToString("N"))

    try {
        New-Item -ItemType Directory -Path $tmpDir -Force -ErrorAction Stop | Out-Null
        Copy-Item (Join-Path $SourceDir "*") $tmpDir -Recurse -Force -ErrorAction Stop

        if (Test-Path $OutDir) {
            Rename-Item $OutDir $oldDir -ErrorAction Stop
        }
        Rename-Item $tmpDir $OutDir -ErrorAction Stop

        if (Test-Path $oldDir) {
            Remove-Item $oldDir -Recurse -Force -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Host "   [FAIL] Cannot copy Windows release: $_" -ForegroundColor Red
        Write-Host "   Usually this means SCN is still running from releases\windows." -ForegroundColor Yellow
        Write-Host "   Close SCN manually or run this script as Administrator, then rebuild." -ForegroundColor Yellow

        if ((Test-Path $OutDir) -eq $false -and (Test-Path $oldDir)) {
            Rename-Item $oldDir $OutDir -ErrorAction SilentlyContinue
        }
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $oldDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# Find or install Flutter
function Get-Flutter {
    Write-Host "`n>> Checking Flutter..." -ForegroundColor Cyan
    
    # 1. Check system Flutter
    $sysFlutter = Get-Command flutter -ErrorAction SilentlyContinue
    if ($sysFlutter) {
        Write-Host "   [OK] System Flutter: $($sysFlutter.Source)" -ForegroundColor Green
        return "flutter"
    }
    
    # 2. Check local Flutter SDK
    $localFlutter = Join-Path $FlutterDir "bin\flutter.bat"
    if (Test-Path $localFlutter) {
        $dartExe = Join-Path $FlutterDir "bin\cache\dart-sdk\bin\dart.exe"
        if (Test-Path $dartExe) {
            # Verify dart.exe works
            try {
                $result = & $dartExe --version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   [OK] Local Flutter SDK" -ForegroundColor Green
                    return $localFlutter
                }
            } catch {}
        }
        # SDK is broken, remove it
        Write-Host "   Local SDK broken, reinstalling..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $FlutterDir -ErrorAction SilentlyContinue
    }
    
    # 3. Download Flutter
    Write-Host "   Flutter not found. Installing..." -ForegroundColor Yellow
    
    $zipPath = Join-Path $ProjectDir "flutter.zip"
    
    Write-Host "   Downloading Flutter $FlutterVersion..." -ForegroundColor Gray
    Write-Host "   URL: $FlutterZipUrl" -ForegroundColor Gray
    
    try {
        # Download with progress
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $FlutterZipUrl -OutFile $zipPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        
        Write-Host "   Extracting..." -ForegroundColor Gray
        
        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $ProjectDir -Force
        
        # Rename to flutter-sdk
        $extractedDir = Join-Path $ProjectDir "flutter"
        if (Test-Path $extractedDir) {
            if (Test-Path $FlutterDir) {
                Remove-Item -Recurse -Force $FlutterDir
            }
            Rename-Item $extractedDir $FlutterDir
        }
        
        # Cleanup
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        
        $localFlutter = Join-Path $FlutterDir "bin\flutter.bat"
        if (Test-Path $localFlutter) {
            Configure-Flutter -Flutter $localFlutter
            Write-Host "   Precaching Flutter..." -ForegroundColor Gray
            & $localFlutter precache --windows 2>&1 | Out-Null
            
            Write-Host "   [OK] Flutter installed successfully!" -ForegroundColor Green
            return $localFlutter
        }
    }
    catch {
        Write-Host "   [FAIL] Download failed: $_" -ForegroundColor Red
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
    
    return $null
}

# Increment version
function Update-Version {
    $pubspec = Join-Path $ScnDir "pubspec.yaml"
    $content = Get-Content $pubspec -Raw
    if ($content -match 'version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
        $ver = $Matches[1]
        $build = [int]$Matches[2] + 1
        $content = $content -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $ver+$build"
        Set-Content $pubspec $content -NoNewline
        Write-Host "`nVersion: $ver+$build" -ForegroundColor Magenta
    }
}

# Win7 PE import patch (CMake install step) needs Python + lief.
function Ensure-Win7PatchDeps {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Host "   [WARN] Python not found; Win7 PE patch may fail at install" -ForegroundColor Yellow
        Write-Host "   Install Python 3 and run: pip install lief" -ForegroundColor Gray
        return $false
    }

    & python -c "import lief" 2>$null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    Write-Host "   Installing lief for Win7 PE patch..." -ForegroundColor Gray
    & python -m pip install lief
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAIL] pip install lief failed" -ForegroundColor Red
        return $false
    }

    & python -c "import lief" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAIL] lief is not importable after install" -ForegroundColor Red
        return $false
    }

    Write-Host "   [OK] lief ready" -ForegroundColor Green
    return $true
}

# Build Windows
function Build-Windows {
    param([string]$Flutter)
    
    Write-Host "`n>> Building Windows..." -ForegroundColor Cyan
    
    $outDir = Join-Path $ReleasesDir "windows"
    New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue | Out-Null
    
    Push-Location $ScnDir
    
    if ($Clean) {
        Write-Host "   Cleaning..." -ForegroundColor Gray
        & $Flutter clean 2>$null
    }
    
    Write-Host "   Getting dependencies..." -ForegroundColor Gray
    Pop-Location
    if (-not (Invoke-PubGet -Flutter $Flutter -Cwd $ScnDir)) {
        Write-Host "   [FAIL] pub get failed" -ForegroundColor Red
        return $false
    }
    Push-Location $ScnDir

    if (-not (Ensure-Win7PatchDeps)) {
        Pop-Location
        return $false
    }
    
    Write-Host "   Building release..." -ForegroundColor Gray
    & $Flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAIL] Flutter Windows release build failed" -ForegroundColor Red
        Pop-Location
        return $false
    }
    
    $exe = Join-Path $ScnDir "build\windows\x64\runner\Release\scn.exe"
    if (Test-Path $exe) {
        if (-not (Stop-SCNProcesses)) {
            Pop-Location
            return $false
        }

        $releaseSource = Join-Path $ScnDir "build\windows\x64\runner\Release"
        if (-not (Copy-ReleaseDirectory -SourceDir $releaseSource -OutDir $outDir)) {
            Pop-Location
            return $false
        }

        $size = [math]::Round((Get-Item (Join-Path $outDir "scn.exe")).Length / 1MB, 1)
        Write-Host "   [OK] Windows build complete ($size MB)" -ForegroundColor Green
        Write-Host "   Output: $outDir\scn.exe" -ForegroundColor Gray
        Pop-Location
        return $true
    }
    
    Write-Host "   [FAIL] Windows build failed" -ForegroundColor Red
    Pop-Location
    return $false
}

# Build Linux
function Build-Linux {
    param([string]$Flutter)
    
    Write-Host "`n>> Building Linux via WSL..." -ForegroundColor Cyan
    
    $distros = wsl --list --quiet 2>$null
    if (-not $distros) {
        Write-Host "   [FAIL] WSL not installed" -ForegroundColor Red
        return $false
    }
    
    $outDir = Join-Path $ReleasesDir "linux"
    New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue | Out-Null
    
    $wslPath = ($ProjectDir -replace '\\', '/') -replace '^([A-Za-z]):', { '/mnt/' + $_.Groups[1].Value.ToLower() }
    
    Write-Host "   WSL path: $wslPath" -ForegroundColor Gray
    
    # Check if flutter exists in WSL
    $script = @"
#!/bin/bash
set -e

# Install Flutter if not present
install_flutter() {
    echo "Installing Flutter in WSL..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev 2>/dev/null || true
    
    if ! command -v flutter &>/dev/null; then
        if [ ! -d ~/flutter ]; then
            git clone https://github.com/flutter/flutter.git -b stable ~/flutter --depth 1
        fi
        export PATH="`$PATH:`$HOME/flutter/bin"
    fi
}

# Find flutter
if command -v flutter &>/dev/null; then
    FL=flutter
elif [ -x ~/flutter/bin/flutter ]; then
    FL=~/flutter/bin/flutter
    export PATH="`$PATH:`$HOME/flutter/bin"
else
    install_flutter
    FL=~/flutter/bin/flutter
fi

cd "$wslPath/scn"
`$FL config --enable-linux-desktop 2>/dev/null || true

# Workaround Flutter 3.24.5 pub-advisories bug
reset_pub_cache() {
    for root in "`$HOME/.pub-cache" "`${PUB_CACHE:-}"; do
        [ -d "`$root" ] || continue
        rm -rf "`$root/advisories" 2>/dev/null || true
        if [ -d "`$root/hosted/pub.dev/.cache" ]; then
            rm -f "`$root/hosted/pub.dev/.cache"/*.json 2>/dev/null || true
        fi
    done
}

pub_get_with_retry() {
    local out
    out=`$(`$FL pub get 2>&1) && { echo "`$out"; return 0; }
    echo "`$out"
    if echo "`$out" | grep -qE "readAdvisoriesFromCache|advisoriesUpdated must be a String|Null check operator used on a null value"; then
        echo "Detected pub advisories cache bug; clearing cache and retrying..."
        reset_pub_cache
        `$FL pub get && return 0
        `$FL pub get --offline && return 0
    fi
    return 1
}

pub_get_with_retry || exit 1
`$FL build linux --release
echo "BUILD_OK"
"@
    
    $scriptFile = Join-Path $ProjectDir "._build.sh"
    $script.Replace("`r`n", "`n") | Set-Content $scriptFile -NoNewline -Encoding UTF8
    
    wsl bash -c "chmod +x '$wslPath/._build.sh' && '$wslPath/._build.sh'"
    
    Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
    
    $linuxExe = Join-Path $ScnDir "build\linux\x64\release\bundle\scn"
    if (Test-Path $linuxExe) {
        $packageScript = @"
#!/bin/bash
set -e
bundle="$wslPath/scn/build/linux/x64/release/bundle"
out="$wslPath/releases/linux"
archive="$wslPath/releases/scn-linux-x64.tar.gz"
rm -rf "`$out"
mkdir -p "`$out"
cp -a "`$bundle"/. "`$out"/
chmod +x "`$out/scn"
cat > "`$out/run_scn.sh" <<'EOF'
#!/usr/bin/env bash
set -e
cd "`$(dirname "`$0")"
chmod +x ./scn 2>/dev/null || true
exec ./scn "`$@"
EOF
chmod +x "`$out/run_scn.sh"
cat > "`$out/README_LINUX.txt" <<'EOF'
SCN Linux bundle

Run from this directory:
  ./scn

If the executable bit was lost after copying/unzipping:
  chmod +x ./scn
  ./scn

Or use:
  bash run_scn.sh
EOF
tar -C "$wslPath/releases" -czf "`$archive" linux
"@
        $packageScriptFile = Join-Path $ProjectDir "._package_linux.sh"
        $packageScript.Replace("`r`n", "`n") | Set-Content $packageScriptFile -NoNewline -Encoding UTF8
        wsl bash -c "chmod +x '$wslPath/._package_linux.sh' && '$wslPath/._package_linux.sh'"
        $packageExitCode = $LASTEXITCODE
        Remove-Item $packageScriptFile -Force -ErrorAction SilentlyContinue
        if ($packageExitCode -ne 0) {
            Write-Host "   [FAIL] Linux release packaging failed" -ForegroundColor Red
            return $false
        }
        Write-Host "   [OK] Linux build complete" -ForegroundColor Green
        Write-Host "   Output: $outDir\scn" -ForegroundColor Gray
        Write-Host "   Launcher: $outDir\run_scn.sh" -ForegroundColor Gray
        Write-Host "   Archive: $ReleasesDir\scn-linux-x64.tar.gz" -ForegroundColor Gray
        return $true
    }
    
    Write-Host "   [FAIL] Linux build failed" -ForegroundColor Red
    return $false
}

# ==================== MAIN ====================

Clear-Processes

$Flutter = Get-Flutter

if (-not $Flutter) {
    Write-Host "`n[ERROR] Cannot install Flutter!" -ForegroundColor Red
    Write-Host "  Please install manually: https://docs.flutter.dev/get-started/install" -ForegroundColor Gray
    exit 1
}

Configure-Flutter -Flutter $Flutter

Update-Version

# Determine targets
$buildWin = $false
$buildLin = $false

if ($All) { $buildWin = $true; $buildLin = $true }
elseif ($Windows -or $Linux) { $buildWin = $Windows; $buildLin = $Linux }
else { $buildWin = $true }

# Execute builds
$results = @{}

if ($buildWin) { $results["Windows"] = Build-Windows -Flutter $Flutter }
if ($buildLin) { $results["Linux"] = Build-Linux -Flutter $Flutter }

# Summary
Write-Host "`n======================================" -ForegroundColor Yellow
Write-Host "       Summary" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow

$allOk = $true
foreach ($p in $results.Keys) {
    if ($results[$p]) {
        Write-Host "   [OK] $p" -ForegroundColor Green
    } else {
        Write-Host "   [FAIL] $p" -ForegroundColor Red
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) { exit 0 } else { exit 1 }
