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

Write-Host ""
Write-Host "======================================" -ForegroundColor Yellow
Write-Host "       SCN Build Script" -ForegroundColor Yellow  
Write-Host "======================================" -ForegroundColor Yellow

# Kill processes
function Clear-Processes {
    Get-Process -Name "dart", "flutter", "pub" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
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
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   [FAIL] pub get failed" -ForegroundColor Red
        Pop-Location
        return $false
    }
    
    Write-Host "   Building release..." -ForegroundColor Gray
    & $Flutter build windows --release
    
    $exe = Join-Path $ScnDir "build\windows\x64\runner\Release\scn.exe"
    if (Test-Path $exe) {
        Copy-Item (Join-Path $ScnDir "build\windows\x64\runner\Release\*") $outDir -Recurse -Force
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
`$FL pub get
`$FL build linux --release
echo "BUILD_OK"
"@
    
    $scriptFile = Join-Path $ProjectDir "._build.sh"
    $script.Replace("`r`n", "`n") | Set-Content $scriptFile -NoNewline -Encoding UTF8
    
    wsl bash -c "chmod +x '$wslPath/._build.sh' && '$wslPath/._build.sh'"
    
    Remove-Item $scriptFile -Force -ErrorAction SilentlyContinue
    
    $linuxExe = Join-Path $ScnDir "build\linux\x64\release\bundle\scn"
    if (Test-Path $linuxExe) {
        Copy-Item (Join-Path $ScnDir "build\linux\x64\release\bundle\*") $outDir -Recurse -Force
        Write-Host "   [OK] Linux build complete" -ForegroundColor Green
        Write-Host "   Output: $outDir" -ForegroundColor Gray
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
