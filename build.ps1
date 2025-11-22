<#
.SYNOPSIS
    Universal build script for LocalSend on Windows and Linux

.DESCRIPTION
    This script automates the compilation and build process of LocalSend project
    for Windows and Linux platforms. Supports:
    - Windows: ZIP archive or EXE installer
    - Linux: AppImage

.PARAMETER Platform
    Target platform: 'windows', 'linux', or 'all' (default: 'all')

.PARAMETER BuildType
    Build type for Windows: 'zip' or 'exe' (default: 'zip')

.PARAMETER Clean
    Clean before build (default: true)

.PARAMETER SkipBuildRunner
    Skip build_runner execution (default: false)

.PARAMETER Project
    Project to build: 'scn' (default: 'scn')

.EXAMPLE
    .\work.ps1
    Builds for all platforms (Windows ZIP and Linux AppImage)

.EXAMPLE
    .\work.ps1 -Platform windows -BuildType exe
    Builds only Windows EXE installer

.EXAMPLE
    .\work.ps1 -Platform linux
    Builds only Linux AppImage

.EXAMPLE
    .\work.ps1 -Project scn -Platform windows
    Builds SCN project for Windows
#>

param(
    [ValidateSet('windows', 'linux', 'all')]
    [string]$Platform = 'all',
    
    [ValidateSet('zip', 'exe')]
    [string]$BuildType = 'zip',
    
    [switch]$Clean = $true,
    
    [switch]$SkipBuildRunner = $false,
    
    [switch]$AutoInstall = $false,
    
    [ValidateSet('scn')]
    [string]$Project = 'scn'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-Rust {
    Write-Info "Rust not found. Installing Rust..."
    
    if (Test-Command "winget") {
        Write-Info "Using winget to install Rust..."
        try {
            & winget install --id Rustlang.Rustup --silent --accept-package-agreements --accept-source-agreements
            Write-Success "Rust installed successfully!"
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Wait a bit for installation to complete
            Start-Sleep -Seconds 5
            
            # Wait a bit more for installation to complete
            Start-Sleep -Seconds 10
            
            # Refresh PATH again
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Try to find cargo in common locations
            $cargoPaths = @(
                "$env:USERPROFILE\.cargo\bin\cargo.exe",
                "$env:LOCALAPPDATA\Programs\Rust stable MSVC 64-bit\bin\cargo.exe"
            )
            
            foreach ($cargoPath in $cargoPaths) {
                if (Test-Path $cargoPath) {
                    $env:PATH = "$(Split-Path $cargoPath);$env:PATH"
                    break
                }
            }
            
            # Verify installation
            if (Test-Command "cargo") {
                Write-Success "Rust installation verified!"
                
                # Install MSVC target
                Write-Info "Installing MSVC target for Rust..."
                try {
                    & cargo --version 2>&1 | Out-Null
                    & rustup target add x86_64-pc-windows-msvc 2>&1 | Out-Null
                    & rustup default stable-x86_64-pc-windows-msvc 2>&1 | Out-Null
                    Write-Success "Rust MSVC toolchain configured!"
                }
                catch {
                    Write-Warning "Failed to configure Rust MSVC toolchain: $_"
                }
                
                return $true
            }
            else {
                Write-Warning "Rust installed but not found in PATH. Please restart your terminal."
                Write-Info "After restart, run: rustup target add x86_64-pc-windows-msvc"
                return $false
            }
        }
        catch {
            Write-ErrorMsg "Failed to install Rust via winget: $_"
            Write-Info "Please install Rust manually from https://rustup.rs/"
            return $false
        }
    }
    else {
        Write-Warning "winget not found. Cannot auto-install Rust."
        Write-Info "Please install Rust manually:"
        Write-Info "  1. Download from https://rustup.rs/"
        Write-Info "  2. Or install winget and run: winget install Rustlang.Rustup"
        return $false
    }
}

function Install-CMake {
    Write-Info "CMake not found. Installing CMake..."
    
    if (Test-Command "winget") {
        Write-Info "Using winget to install CMake..."
        try {
            & winget install --id Kitware.CMake --silent --accept-package-agreements --accept-source-agreements
            Write-Success "CMake installed successfully!"
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Wait a bit for installation to complete
            Start-Sleep -Seconds 5
            
            # Verify installation
            $cmakePath = $null
            $possiblePaths = @(
                "C:\Program Files\CMake\bin\cmake.exe",
                "C:\Program Files (x86)\CMake\bin\cmake.exe",
                "${env:ProgramFiles}\CMake\bin\cmake.exe"
            )
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $cmakePath = $path
                    $env:PATH = "$(Split-Path $path);$env:PATH"
                    break
                }
            }
            
            if ($null -ne $cmakePath) {
                Write-Success "CMake installation verified at: $cmakePath"
                return $cmakePath
            }
            else {
                Write-Warning "CMake installed but not found. Please restart your terminal."
                return $null
            }
        }
        catch {
            Write-ErrorMsg "Failed to install CMake via winget: $_"
            Write-Info "Please install CMake manually from https://cmake.org/download/"
            return $null
        }
    }
    else {
        Write-Warning "winget not found. Cannot auto-install CMake."
        Write-Info "Please install CMake manually:"
        Write-Info "  1. Download from https://cmake.org/download/"
        Write-Info "  2. Or install winget and run: winget install Kitware.CMake"
        return $null
    }
}

function Ensure-Rust {
    if (Test-Command "cargo") {
        $cargoVersion = & cargo --version 2>&1
        Write-Info "Rust found: $cargoVersion"
        
        # Check if Rust toolchain is properly configured for Windows
        $rustcVersion = & rustc --version 2>&1
        Write-Info "Rust compiler: $rustcVersion"
        
        # Check if MSVC toolchain is available
        $rustupTargets = & rustup target list --installed 2>&1
        if ($rustupTargets -match "x86_64-pc-windows-msvc") {
            Write-Info "MSVC target is installed: x86_64-pc-windows-msvc"
        }
        else {
            Write-Warning "MSVC target not found. Installing x86_64-pc-windows-msvc..."
            try {
                & rustup target add x86_64-pc-windows-msvc 2>&1 | Out-Null
                Write-Success "MSVC target installed successfully!"
            }
            catch {
                Write-Warning "Failed to install MSVC target: $_"
            }
        }
        
        # Set default toolchain to MSVC if not already set
        $defaultToolchain = & rustup show default 2>&1
        if ($defaultToolchain -notmatch "msvc") {
            Write-Info "Setting default toolchain to MSVC..."
            try {
                & rustup default stable-x86_64-pc-windows-msvc 2>&1 | Out-Null
                Write-Success "Default toolchain set to MSVC!"
            }
            catch {
                Write-Warning "Failed to set default toolchain: $_"
            }
        }
        
        return $true
    }
    else {
        Write-Warning "Rust (cargo) not found!"
        return Install-Rust
    }
}

function Ensure-CMake {
    $cmakePath = $null
    if (Test-Command "cmake") {
        $cmakePath = (Get-Command cmake).Source
        $cmakeVersion = & cmake --version 2>&1 | Select-Object -First 1
        Write-Info "CMake found: $cmakeVersion at $cmakePath"
        return $cmakePath
    }
    else {
        # Try to find CMake in common locations
        $possiblePaths = @(
            "C:\Program Files\CMake\bin\cmake.exe",
            "C:\Program Files (x86)\CMake\bin\cmake.exe",
            "${env:ProgramFiles}\CMake\bin\cmake.exe"
        )
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $cmakePath = $path
                $env:PATH = "$(Split-Path $path);$env:PATH"
                Write-Info "CMake found at: $cmakePath"
                return $cmakePath
            }
        }
        
        # CMake not found, try to install
        Write-Warning "CMake not found!"
        return Install-CMake
    }
}

function Ensure-VisualStudioBuildTools {
    # Check if Visual Studio BuildTools or Visual Studio is installed
    $vsPaths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community",
        "C:\Program Files\Microsoft Visual Studio\2022\Community",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
    )
    
    foreach ($path in $vsPaths) {
        if (Test-Path $path) {
            Write-Info "Visual Studio found at: $path"
            return $true
        }
    }
    
    # Check for MSBuild
    if (Test-Command "msbuild") {
        Write-Info "MSBuild found in PATH"
        return $true
    }
    
    # Try to find MSBuild
    $msbuildPaths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    
    foreach ($path in $msbuildPaths) {
        if (Test-Path $path) {
            Write-Info "MSBuild found at: $path"
            $env:PATH = "$(Split-Path $path);$env:PATH"
            return $true
        }
    }
    
    # Visual Studio not found, try to install
    Write-Warning "Visual Studio BuildTools not found!"
    
    if (Test-Command "winget") {
        Write-Info "Attempting to install Visual Studio BuildTools via winget..."
        Write-Warning "This will install a large package (~6GB). The installation may take a while."
        Write-Info "You can also install manually from: https://visualstudio.microsoft.com/downloads/"
        
        if ($AutoInstall) {
            $response = "Y"
        }
        else {
            $response = Read-Host "Do you want to install Visual Studio BuildTools now? (Y/N)"
        }
        
        if ($response -eq "Y" -or $response -eq "y") {
            try {
                & winget install --id Microsoft.VisualStudio.2022.BuildTools --silent --accept-package-agreements --accept-source-agreements --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
                Write-Success "Visual Studio BuildTools installation started!"
                Write-Info "Please wait for installation to complete, then restart your terminal and run the script again."
                return $false
            }
            catch {
                Write-ErrorMsg "Failed to install Visual Studio BuildTools via winget: $_"
                Write-Info "Please install Visual Studio BuildTools manually from https://visualstudio.microsoft.com/downloads/"
                return $false
            }
        }
        else {
            Write-Info "Skipping Visual Studio BuildTools installation."
            Write-Info "Please install Visual Studio BuildTools manually from https://visualstudio.microsoft.com/downloads/"
            return $false
        }
    }
    else {
        Write-Warning "winget not found. Cannot auto-install Visual Studio BuildTools."
        Write-Info "Please install Visual Studio BuildTools manually from https://visualstudio.microsoft.com/downloads/"
        return $false
    }
}

function Test-IsWindows {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $IsWindows
    }
    else {
        return ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    }
}

function Test-IsLinux {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return $IsLinux
    }
    else {
        return ([Environment]::OSVersion.Platform -eq [PlatformID]::Unix)
    }
}

function Get-FlutterCommand {
    if (Test-Command "fvm") {
        Write-Info "Using fvm for Flutter management"
        return "fvm flutter"
    }
    elseif (Test-Command "flutter") {
        Write-Info "Using system Flutter"
        return "flutter"
    }
    elseif (Test-Path "submodules\flutter\bin\flutter.bat") {
        Write-Info "Using Flutter from submodules"
        return "submodules\flutter\bin\flutter.bat"
    }
    elseif (Test-Path "submodules/flutter/bin/flutter") {
        Write-Info "Using Flutter from submodules"
        return "submodules/flutter/bin/flutter"
    }
    else {
        throw "Flutter not found! Install Flutter, fvm, or initialize submodules (git submodule update --init)."
    }
}

function Invoke-FlutterCommand {
    param(
        [string]$Command,
        [string]$WorkingDirectory = "app"
    )
    
    $flutterCmd = Get-FlutterCommand
    $fullCommand = "$flutterCmd $Command"
    Write-Info "Executing: $fullCommand (in $WorkingDirectory)"
    
    # Get full path to Flutter BEFORE changing to working directory
    $flutterPath = $flutterCmd
    if ($flutterCmd -like "*\*" -or $flutterCmd -like "*/*") {
        # This is a file path - get full path from project root
        if (-not ([System.IO.Path]::IsPathRooted($flutterCmd))) {
            $rootDir = (Get-Location).Path
            $flutterPath = Join-Path $rootDir $flutterCmd
            if (-not (Test-Path $flutterPath)) {
                throw "Flutter not found at path: $flutterPath"
            }
            $flutterPath = (Resolve-Path $flutterPath).Path
        }
    }
    
    Push-Location $WorkingDirectory
    try {
        # Call Flutter with arguments
        $cmdParts = $Command -split ' '
        & $flutterPath $cmdParts
        
        $commandSuccess = $?
        if (-not $commandSuccess) {
            throw "Command failed: $fullCommand"
        }
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            throw "Command exited with error code ${exitCode}: $fullCommand"
        }
    }
    finally {
        Pop-Location
    }
}

function Build-Simple {
    param([string]$Type)
    
    Write-Info "Starting Windows build for SCN ($Type)..."
    
    if (-not (Test-Path "scn\pubspec.yaml")) {
        throw "Project not found at scn\"
    }
    
    # Get Flutter command and resolve path
    $flutterCmd = Get-FlutterCommand
    $flutterPath = $flutterCmd
    
    # Resolve Flutter path if it's a relative path
    if ($flutterCmd -like "*\*" -or $flutterCmd -like "*/*") {
        if (-not ([System.IO.Path]::IsPathRooted($flutterCmd))) {
            $rootDir = (Get-Location).Path
            $flutterPath = Join-Path $rootDir $flutterCmd
            if (-not (Test-Path $flutterPath)) {
                throw "Flutter not found at path: $flutterPath"
            }
            $flutterPath = (Resolve-Path $flutterPath).Path
        }
    }
    
    Push-Location "scn"
    try {
        if ($Clean) {
            Write-Info "Cleaning project..."
            & $flutterPath clean 2>&1 | Out-Null
            
            if (Test-Path "build\windows") {
                Remove-Item "build\windows" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Info "Getting dependencies..."
        & $flutterPath pub get
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get dependencies"
        }
        
        Write-Info "Building Windows application..."
        & $flutterPath build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed with exit code: $LASTEXITCODE"
        }
        
        Write-Success "Windows build completed!"
        
        # Show output location
        $buildPath = "build\windows\x64\runner\Release"
        $exeFile = Join-Path $buildPath "scn.exe"
        if (Test-Path $exeFile) {
            $exeFullPath = (Resolve-Path $exeFile).Path
            Write-Info "Executable: $exeFullPath"
        }
        
        # Create release package
        Write-Info "Creating release package..."
        $releaseDir = Join-Path (Get-Location).Path "..\scn-release"
        if (Test-Path $releaseDir) {
            # Try to remove, but don't fail if files are locked
            try {
                Remove-Item $releaseDir -Recurse -Force -ErrorAction Stop
            } catch {
                # If removal fails, try to remove individual files
                Write-Warning "Could not remove release directory, cleaning files individually..."
                Get-ChildItem -Path $releaseDir -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $releaseDir -Recurse -Directory | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not (Test-Path $releaseDir)) {
            New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
        }
        
        # Copy all files from Release (this includes flutter_windows.dll)
        Copy-Item -Path "$buildPath\*" -Destination $releaseDir -Recurse -Force
        
        # flutter_windows.dll should already be in the root from Copy-Item above
        # No need to copy it again
        
        # Copy logo assets from original project if they exist (optional)
        $originalAssets = Join-Path (Get-Location).Path "..\app\assets\img"
        if (Test-Path $originalAssets) {
            try {
                $targetAssets = Join-Path $releaseDir "data\flutter_assets\assets\img"
                New-Item -ItemType Directory -Path $targetAssets -Force | Out-Null
                Copy-Item -Path "$originalAssets\logo*" -Destination $targetAssets -Force -ErrorAction SilentlyContinue
                Write-Info "Copied logo assets"
            } catch {
                # Ignore errors when copying optional assets
            }
        }
        
        # Create README
        $readmeContent = @"
SCN - Запускающая папка
========================

Эта папка содержит все необходимые файлы для запуска SCN.

СТРУКТУРА:
----------
- scn.exe                 - Главный исполняемый файл
- flutter_windows.dll     - Flutter движок для Windows
- data/                   - Данные приложения
  - app.so               - Скомпилированный Dart код (AOT)
  - icudtl.dat           - Данные ICU для интернационализации
  - flutter_assets/      - Ресурсы приложения

ЗАПУСК:
-------
Просто запустите scn.exe двойным кликом или из командной строки:
  .\scn.exe

ТРЕБОВАНИЯ:
-----------
- Windows 10 или новее
- Visual C++ Redistributable (обычно уже установлен)

ПРИМЕЧАНИЯ:
-----------
- Все файлы должны оставаться в этой папке
- Не перемещайте отдельные файлы - приложение не запустится
- Папка data/ содержит критически важные файлы

ВЕРСИЯ:
-------
SCN 1.0.0
Secure Connection Network - упрощенная версия без Rust зависимостей
"@
        Set-Content -Path (Join-Path $releaseDir "README.txt") -Value $readmeContent -Encoding UTF8
        
        $releaseFullPath = (Resolve-Path $releaseDir).Path
        Write-Success "Release package created at: $releaseFullPath"
        
        # Calculate total size
        $totalSize = (Get-ChildItem -Path $releaseDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Info "Total package size: $totalSizeMB MB"
    }
    finally {
        Pop-Location
    }
}

function Build-Windows {
    param([string]$Type)
    
    Write-Info "Starting Windows build ($Type)..."
    
    # Ensure Visual Studio BuildTools is installed
    if (-not (Ensure-VisualStudioBuildTools)) {
        Write-Warning "Visual Studio BuildTools may not be installed. Build may fail."
        Write-Info "Install Visual Studio BuildTools from: https://visualstudio.microsoft.com/downloads/"
        Write-Info "Make sure to include 'Desktop development with C++' workload."
    }
    
    # Ensure Rust is installed (only for original app)
    if (-not (Ensure-Rust)) {
        throw "Rust is required but could not be installed. Please install Rust manually from https://rustup.rs/"
    }
    
    # Ensure CMake is installed
    $cmakePath = Ensure-CMake
    if ($null -eq $cmakePath) {
        throw "CMake is required but could not be installed. Please install CMake manually from https://cmake.org/download/"
    }
    else {
        # Set CMAKE environment variable to force using the found CMake
        $cmakeDir = Split-Path $cmakePath
        $env:CMAKE = $cmakePath
        $env:CMAKE_COMMAND = $cmakePath
        $env:CMAKE_PROGRAM = $cmakePath
        Write-Info "Setting CMAKE environment variable to: $cmakePath"
        
        # Also add to PATH at the beginning to prioritize it
        $env:PATH = "$cmakeDir;$env:PATH"
        
        # Try to create a symbolic link to CMake in Visual Studio location if it doesn't exist
        $vsCmakePath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        $vsCmakeDir = Split-Path $vsCmakePath
        if (-not (Test-Path $vsCmakePath) -and (Test-Path $cmakePath)) {
            try {
                if (-not (Test-Path $vsCmakeDir)) {
                    New-Item -ItemType Directory -Path $vsCmakeDir -Force -ErrorAction SilentlyContinue | Out-Null
                }
                if (-not (Test-Path $vsCmakePath)) {
                    # Create a hard link (works better than symlink on Windows)
                    $cmd = "cmd /c mklink /H `"$vsCmakePath`" `"$cmakePath`""
                    Invoke-Expression $cmd -ErrorAction SilentlyContinue
                    if (Test-Path $vsCmakePath) {
                        Write-Info "Created link to CMake at Visual Studio location"
                    }
                }
            }
            catch {
                Write-Warning "Could not create CMake link at Visual Studio location: $_"
            }
        }
    }
    
    if ($Clean) {
        Write-Info "Cleaning project..."
        Invoke-FlutterCommand "clean"
        
        # Clean build directory to avoid CMake cache issues
        Push-Location "app"
        try {
            if (Test-Path "build\windows") {
                Write-Info "Cleaning Windows build directory and CMake cache..."
                Remove-Item "build\windows" -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Also clean CMake cache files if they exist
            if (Test-Path "build\windows\x64\CMakeCache.txt") {
                Remove-Item "build\windows\x64\CMakeCache.txt" -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path "build\windows\x64\CMakeFiles") {
                Remove-Item "build\windows\x64\CMakeFiles" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Info "Getting dependencies..."
    Invoke-FlutterCommand "pub get"
    
    if (-not $SkipBuildRunner) {
        Write-Info "Running build_runner..."
        Invoke-FlutterCommand "pub run build_runner build -d"
    }
    
    Write-Info "Building Windows application..."
    
    # Set CMake path before building to ensure correct CMake is used
    if ($null -ne $cmakePath) {
        $env:CMAKE_PROGRAM = $cmakePath
        $env:CMAKE = $cmakePath
        $env:CMAKE_COMMAND = $cmakePath
        Write-Info "Using CMake: $cmakePath"
        
        # Ensure CMake is in PATH at the beginning
        $cmakeDir = Split-Path $cmakePath
        $env:PATH = "$cmakeDir;$env:PATH"
    }
    
    # Ensure Rust is in PATH for cargokit
    if (Test-Command "cargo") {
        $cargoPath = (Get-Command cargo).Source
        $cargoDir = Split-Path $cargoPath
        if ($env:PATH -notlike "*$cargoDir*") {
            $env:PATH = "$cargoDir;$env:PATH"
            Write-Info "Added Rust to PATH: $cargoDir"
        }
        
        # Also ensure rustup is in PATH
        if (Test-Command "rustup") {
            $rustupPath = (Get-Command rustup).Source
            $rustupDir = Split-Path $rustupPath
            if ($env:PATH -notlike "*$rustupDir*") {
                $env:PATH = "$rustupDir;$env:PATH"
            }
        }
        
        # Set Rust environment variables for cargokit
        $env:CARGO_HOME = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { "$env:USERPROFILE\.cargo" }
        $env:RUSTUP_HOME = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { "$env:USERPROFILE\.rustup" }
        Write-Info "Set CARGO_HOME: $env:CARGO_HOME"
        Write-Info "Set RUSTUP_HOME: $env:RUSTUP_HOME"
    }
    
    # Function to fix CMake paths in generated files
    function Fix-CMakePaths {
        param(
            [string]$BuildDir,
            [string]$CmakeExePath
        )
        
        if (-not (Test-Path $BuildDir)) {
            Write-Warning "Fix-CMakePaths: BuildDir does not exist: $BuildDir"
            return
        }
        
        if ([string]::IsNullOrEmpty($CmakeExePath)) {
            Write-Warning "Fix-CMakePaths: CmakeExePath is empty"
            return
        }
        
        # Write-Info "Searching for .vcxproj files in: $BuildDir"  # Commented to reduce spam during monitoring
        
        try {
            $vcxprojFiles = Get-ChildItem -Path $BuildDir -Filter "*.vcxproj" -Recurse -ErrorAction SilentlyContinue
            $fileCount = ($vcxprojFiles | Measure-Object).Count
            Write-Info "Found $fileCount .vcxproj file(s) to check"
            
            if ($fileCount -eq 0) {
                Write-Warning "No .vcxproj files found in $BuildDir"
                return
            }
            
            $fixedCount = 0
            foreach ($file in $vcxprojFiles) {
                try {
                    $content = Get-Content $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    $originalContent = $content
                    
                    # Replace Visual Studio Community CMake path with our CMake
                    # Need to escape special regex characters in the replacement string
                    $cmakePathEscaped = [regex]::Escape($CmakeExePath)
                    
                    # Pattern to match Visual Studio Community CMake paths
                    # Try multiple patterns to catch all variations
                    $patterns = @(
                        # Exact path with CommonExtensions
                        'C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake\.exe',
                        'C:\\Program Files \(x86\)\\Microsoft Visual Studio\\2022\\Community\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake\.exe',
                        # Generic pattern for any path containing Community and cmake.exe
                        'C:\\Program Files\\Microsoft Visual Studio\\2022\\Community[^"]*cmake\.exe',
                        'C:\\Program Files \(x86\)\\Microsoft Visual Studio\\2022\\Community[^"]*cmake\.exe',
                        # BuildTools patterns
                        'C:\\Program Files\\Microsoft Visual Studio\\2022\\BuildTools[^"]*cmake\.exe',
                        'C:\\Program Files \(x86\)\\Microsoft Visual Studio\\2022\\BuildTools[^"]*cmake\.exe',
                        # Escape the path for regex (handle backslashes)
                        [regex]::Escape('C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'),
                        [regex]::Escape('C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
                    )
                    
                    $wasFixed = $false
                    foreach ($pattern in $patterns) {
                        if ($content -match $pattern) {
                            $content = $content -replace $pattern, $CmakeExePath
                            $wasFixed = $true
                        }
                    }
                    
                    # Also try a more generic approach - find any path containing "Visual Studio" and "cmake.exe"
                    if (-not $wasFixed) {
                        # Pattern to match paths in quotes containing Visual Studio and cmake.exe
                        $genericPattern = '"([^"]*Microsoft Visual Studio[^"]*cmake\.exe)"'
                        if ($content -match $genericPattern) {
                            $matches = [regex]::Matches($content, $genericPattern)
                            foreach ($match in $matches) {
                                $oldPath = $match.Groups[1].Value
                                if ($oldPath -ne $CmakeExePath -and $oldPath -like "*Community*") {
                                    # Replace the path inside quotes
                                    $content = $content -replace [regex]::Escape($oldPath), $CmakeExePath
                                    $wasFixed = $true
                                }
                            }
                        }
                        
                        # Also try without quotes
                        if (-not $wasFixed) {
                            $noQuotePattern = '([A-Z]:\\[^"<>\r\n]*Microsoft Visual Studio[^"<>\r\n]*cmake\.exe)'
                            if ($content -match $noQuotePattern) {
                                $matches = [regex]::Matches($content, $noQuotePattern)
                                foreach ($match in $matches) {
                                    $oldPath = $match.Groups[1].Value
                                    if ($oldPath -ne $CmakeExePath -and $oldPath -like "*Community*") {
                                        $content = $content -replace [regex]::Escape($oldPath), $CmakeExePath
                                        $wasFixed = $true
                                    }
                                }
                            }
                        }
                    }
                    
                    if ($content -ne $originalContent) {
                        Set-Content $file.FullName -Value $content -NoNewline -Encoding UTF8 -ErrorAction Stop
                        Write-Info "Fixed CMake path in: $($file.Name)"
                        $fixedCount++
                    }
                }
                catch {
                    Write-Warning "Could not fix CMake path in $($file.Name): $_"
                }
            }
            
            Write-Info "Fixed CMake paths in $fixedCount file(s)"
        }
        catch {
            Write-Warning "Error searching for .vcxproj files: $_"
        }
    }
    
    # Try to fix CMake paths before build (if files already exist from previous build)
    Push-Location "app"
    try {
        $buildDir = "build\windows\x64"
        if (Test-Path $buildDir) {
            if ($null -ne $cmakePath -and $cmakePath -ne "") {
                Write-Info "Checking for existing .vcxproj files to fix..."
                Fix-CMakePaths -BuildDir $buildDir -CmakeExePath $cmakePath
            }
            else {
                Write-Warning "CMake path is not set, skipping path fix"
            }
        }
    }
    catch {
        Write-Warning "Could not fix CMake paths before build: $_"
    }
    finally {
        Pop-Location
    }
    
    # Build with Flutter - use background monitoring to fix paths as files are generated
    if ($null -ne $cmakePath -and $cmakePath -ne "") {
        Write-Info "Starting build with CMake path monitoring..."
        
        # Start Flutter build in background
        $flutterCmd = Get-FlutterCommand
        $flutterPath = $flutterCmd
        if ($flutterCmd -like "*\*" -or $flutterCmd -like "*/*") {
            if (-not ([System.IO.Path]::IsPathRooted($flutterCmd))) {
                $rootDir = (Get-Location).Path
                $flutterPath = Join-Path $rootDir $flutterCmd
                if (Test-Path $flutterPath) {
                    $flutterPath = (Resolve-Path $flutterPath).Path
                }
            }
        }
        
        # Debug info before build setup
        Write-Info "Checking Flutter environment before build..."
        
        # Prepare environment variables before build to avoid cargokit errors
        try {
            $realFlutterPath = $null
            if ($flutterPath -and (Test-Path $flutterPath)) {
                 $realFlutterPath = (Resolve-Path $flutterPath).Path
            } elseif ($flutterCmd -eq "flutter" -or $flutterCmd -eq "flutter.bat") {
                 $cmd = Get-Command $flutterCmd -ErrorAction SilentlyContinue
                 if ($cmd) { $realFlutterPath = $cmd.Source }
            }
            
            if ($realFlutterPath) {
                # flutter/bin/flutter.bat -> flutter root
                # Use Resolve-Path to ensure no ".." in the path, which confuses some tools
                $flutterRoot = Split-Path (Split-Path $realFlutterPath)
                $env:FLUTTER_ROOT = $flutterRoot
                Write-Info "Set FLUTTER_ROOT environment variable: $env:FLUTTER_ROOT"
                
                # CRITICAL FIX: Patch cargokit.cmake to include FLUTTER_ROOT in environment variables
                # This is the root cause - CMake doesn't pass FLUTTER_ROOT to run_build_tool.cmd
                $cargokitCmake = Join-Path (Get-Location).Path "app\rust_builder\cargokit\cmake\cargokit.cmake"
                if (Test-Path $cargokitCmake) {
                    Write-Info "Patching cargokit.cmake to include FLUTTER_ROOT..."
                    $cmakeContent = Get-Content $cargokitCmake -Raw
                    
                    # Check if FLUTTER_ROOT is already in CARGOKIT_ENV
                    $wasPatched = $false
                    if ($cmakeContent -notmatch '"FLUTTER_ROOT=') {
                        # Find the line with CARGOKIT_ROOT_PROJECT_DIR (last in the list) and add FLUTTER_ROOT after it
                        $flutterRootEscaped = $env:FLUTTER_ROOT -replace '\\', '/'  # Use forward slashes for CMake (works on Windows too)
                        
                        # Read file as lines to make replacement easier
                        $lines = Get-Content $cargokitCmake
                        $newLines = @()
                        $found = $false
                        
                        foreach ($line in $lines) {
                            $newLines += $line
                            # If we find CARGOKIT_ROOT_PROJECT_DIR line, add FLUTTER_ROOT after it
                            if ($line -match 'CARGOKIT_ROOT_PROJECT_DIR' -and -not $found) {
                                # Extract indentation from the current line
                                $indent = $line -replace '^(\s+).*', '$1'
                                $newLines += "$indent`"FLUTTER_ROOT=$flutterRootEscaped`""
                                $found = $true
                                Write-Info "Found CARGOKIT_ROOT_PROJECT_DIR line, adding FLUTTER_ROOT after it"
                            }
                        }
                        
                        if ($found) {
                            # Save without BOM to avoid issues with batch files
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            [System.IO.File]::WriteAllLines($cargokitCmake, $newLines, $utf8NoBom)
                            
                            # Verify the patch was applied
                            $verifyContent = Get-Content $cargokitCmake -Raw
                            if ($verifyContent -match '"FLUTTER_ROOT=') {
                                Write-Info "Successfully patched cargokit.cmake with FLUTTER_ROOT: $flutterRootEscaped"
                                $wasPatched = $true
                            } else {
                                Write-Warning "Patch was applied but FLUTTER_ROOT not found in file - verification failed"
                            }
                        } else {
                            Write-Warning "Failed to patch cargokit.cmake - CARGOKIT_ROOT_PROJECT_DIR line not found"
                        }
                    } else {
                        Write-Info "cargokit.cmake already contains FLUTTER_ROOT"
                    }
                    
                    # Force CMake to regenerate by removing cache and generated project files if we patched
                    if ($wasPatched) {
                        Push-Location "app"
                        try {
                            $cmakeCache = "build\windows\x64\CMakeCache.txt"
                            if (Test-Path $cmakeCache) {
                                Write-Info "Removing CMakeCache.txt to force regeneration with patched cargokit.cmake..."
                                Remove-Item $cmakeCache -Force -ErrorAction SilentlyContinue
                            }
                            
                            # Also remove generated .vcxproj files for cargokit targets to force regeneration
                            $cargokitProjFiles = Get-ChildItem -Path "build\windows\x64\plugins" -Filter "*cargokit*.vcxproj" -Recurse -ErrorAction SilentlyContinue
                            if ($cargokitProjFiles) {
                                Write-Info "Removing $($cargokitProjFiles.Count) generated cargokit .vcxproj files to force regeneration..."
                                $cargokitProjFiles | Remove-Item -Force -ErrorAction SilentlyContinue
                            }
                        } finally {
                            Pop-Location
                        }
                    }
                }
                
                # Also patch run_build_tool.cmd as a fallback and remove BOM if present
                $cargokitRunTool = Join-Path (Get-Location).Path "app\rust_builder\cargokit\run_build_tool.cmd"
                if (Test-Path $cargokitRunTool) {
                    Write-Info "Checking and patching run_build_tool.cmd..."
                    
                    # First, remove BOM if present (this fixes the "я╗┐@echo" error)
                    try {
                        $bytes = [System.IO.File]::ReadAllBytes($cargokitRunTool)
                        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                            Write-Info "Removing BOM from run_build_tool.cmd..."
                            $content = [System.IO.File]::ReadAllText($cargokitRunTool, [System.Text.Encoding]::UTF8)
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            [System.IO.File]::WriteAllText($cargokitRunTool, $content, $utf8NoBom)
                            Write-Info "BOM removed successfully"
                        }
                    } catch {
                        Write-Warning "Could not check/remove BOM: $_"
                    }
                    
                    # Now patch if needed
                    $content = Get-Content $cargokitRunTool -Raw
                    
                    # Add FLUTTER_ROOT if not set, right after setlocal
                    if ($content -notmatch 'if.*FLUTTER_ROOT.*==.*""') {
                        $flutterRootVal = $env:FLUTTER_ROOT
                        $patch = "@echo off`r`nsetlocal`r`n`r`nif `"%FLUTTER_ROOT%`" == `"`" SET FLUTTER_ROOT=$flutterRootVal`r`n"
                        
                        if ($content -match "@echo off\r\nsetlocal") {
                            $newContent = $content -replace "@echo off\r\nsetlocal", $patch
                        } elseif ($content -match "@echo off\nsetlocal") {
                            $newContent = $content -replace "@echo off\nsetlocal", $patch
                        } else {
                            $newContent = $content
                        }
                        
                        if ($newContent -ne $content) {
                            # Save without BOM to avoid issues with batch files
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            [System.IO.File]::WriteAllText($cargokitRunTool, $newContent, $utf8NoBom)
                            Write-Info "Patched run_build_tool.cmd with FLUTTER_ROOT fallback"
                        }
                    }
                }
                
                # Also ensure Dart is available in PATH (cargokit might need it)
                $dartBin = Join-Path $env:FLUTTER_ROOT "bin\cache\dart-sdk\bin"
                if (Test-Path $dartBin) {
                    if ($env:PATH -notlike "*$dartBin*") {
                        $env:PATH = "$dartBin;$env:PATH"
                        Write-Info "Added Dart to PATH: $dartBin"
                    }
                }
            }
            else {
                # Fallback: try to guess from project structure if we couldn't resolve from command
                $possibleFlutter = Join-Path (Get-Location).Path "submodules\flutter"
                if (Test-Path $possibleFlutter) {
                    $env:FLUTTER_ROOT = (Resolve-Path $possibleFlutter).Path
                    Write-Info "Fallback: Set FLUTTER_ROOT from submodules: $env:FLUTTER_ROOT"
                    
                    $dartBin = Join-Path $env:FLUTTER_ROOT "bin\cache\dart-sdk\bin"
                    if (Test-Path $dartBin -and $env:PATH -notlike "*$dartBin*") {
                        $env:PATH = "$dartBin;$env:PATH"
                        Write-Info "Added Dart to PATH: $dartBin"
                    }
                }
            }
        } catch {
            Write-Warning "Failed to setup Flutter environment variables: $_"
        }
        
        Write-Info "Build Environment State:"
        Write-Info "  FLUTTER_ROOT: $env:FLUTTER_ROOT"
        
        Push-Location "app"
        try {
            # Pre-create cargokit output directories and placeholder files to avoid MSBuild errors
            $pluginDir = "build\windows\x64\plugins\rust_lib_localsend_app"
            if (-not (Test-Path $pluginDir)) {
                New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
            }
            
            # Create placeholder files that MSBuild expects
            @("Release", "Debug", "Profile") | ForEach-Object {
                $configDir = Join-Path $pluginDir $_
                if (-not (Test-Path $configDir)) {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                }
            }
            
            # Create CMakeFiles directory and required files
            $cmakeFilesDir = Join-Path $pluginDir "CMakeFiles"
            if (-not (Test-Path $cmakeFilesDir)) {
                New-Item -ItemType Directory -Path $cmakeFilesDir -Force | Out-Null
            }
            
            # Create _phony_ file
            $phonyFile = Join-Path $pluginDir "_phony_"
            if (-not (Test-Path $phonyFile)) {
                "" | Out-File -FilePath $phonyFile -Encoding ASCII
            }
            
            # Create rust_lib_localsend_app_cargokit file
            $cargokitFile = Join-Path $cmakeFilesDir "rust_lib_localsend_app_cargokit"
            if (-not (Test-Path $cargokitFile)) {
                "" | Out-File -FilePath $cargokitFile -Encoding ASCII
            }
            
            # Create generate.stamp file
            $stampFile = Join-Path $cmakeFilesDir "generate.stamp"
            if (-not (Test-Path $stampFile)) {
                "" | Out-File -FilePath $stampFile -Encoding ASCII
            }
            
            Write-Info "Pre-created cargokit directories and placeholder files"
            
            $buildDir = "build\windows\x64"
            $buildProcess = Start-Process -FilePath $flutterPath -ArgumentList "build","windows" -NoNewWindow -PassThru -RedirectStandardOutput "build_output.txt" -RedirectStandardError "build_error.txt"
            
            # Monitor and fix paths while build is running
            $maxWait = 600  # 10 minutes max
            $waited = 0
            $checkInterval = 1  # Check every 1 second (more frequent)
            $lastFixTime = 0
            $fixInterval = 2  # Fix paths every 2 seconds (very frequent to catch files as they're generated)
            
            while (-not $buildProcess.HasExited -and $waited -lt $maxWait) {
                Start-Sleep -Seconds $checkInterval
                $waited += $checkInterval
                
                # Fix paths frequently while build is running
                if (($waited - $lastFixTime) -ge $fixInterval) {
                    if (Test-Path $buildDir) {
                        # Use the same Fix-CMakePaths function for consistency
                        # Suppress output to avoid spam during monitoring
                        try {
                            Fix-CMakePaths -BuildDir $buildDir -CmakeExePath $cmakePath | Out-Null
                        }
                        catch {
                            # Ignore errors during monitoring
                        }
                        $lastFixTime = $waited
                    }
                }
            }
            
            # Wait for process to complete
            if (-not $buildProcess.HasExited) {
                $buildProcess.WaitForExit()
            }
            
            # Final fix pass
            if (Test-Path $buildDir) {
                Fix-CMakePaths -BuildDir $buildDir -CmakeExePath $cmakePath
            }
            
            # Check exit code
            if ($buildProcess.ExitCode -ne 0) {
                if (Test-Path "build_error.txt") {
                    $errorOutput = Get-Content "build_error.txt" -Raw -ErrorAction SilentlyContinue
                    if ($errorOutput) {
                        Write-Warning "Build errors: $errorOutput"
                        
                        # Check if error is related to Rust
                        if ($errorOutput -match "rust_lib_localsend_app|rust|cargo") {
                            Write-Info "Rust build error detected. Checking Rust environment..."
                            
                            # Check Rust installation
                            if (Test-Command "cargo") {
                                Write-Info "Rust is installed. Checking toolchain..."
                                try {
                                    $rustupShow = & rustup show 2>&1
                                    Write-Info "Rust toolchain info:"
                                    Write-Info $rustupShow
                                }
                                catch {
                                    Write-Warning "Could not get Rust toolchain info: $_"
                                }
                                
                                # Try to build Rust library manually to see the actual error
                                Write-Info "Attempting to build Rust library manually to diagnose the issue..."
                                
                                # Check if rust directory exists (it's in app/rust, not rust)
                                $rustDir = "..\rust"
                                if (-not (Test-Path $rustDir)) {
                                    $rustDir = "rust"
                                }
                                if (-not (Test-Path $rustDir)) {
                                    Write-Warning "Rust directory not found. Current directory: $(Get-Location)"
                                    Write-Info "Skipping manual Rust build test."
                                }
                                else {
                                    Push-Location $rustDir
                                    try {
                                        Write-Info "Running: cargo build --release (in $(Get-Location))"
                                        Write-Info "This may take a while if crates.io index needs updating..."
                                        
                                        # Run cargo build with timeout to avoid hanging
                                        $job = Start-Job -ScriptBlock {
                                            param($rustDir)
                                            Set-Location $rustDir
                                            & cargo build --release 2>&1 | Out-String
                                        } -ArgumentList (Get-Location).Path
                                        
                                        # Wait up to 5 minutes for cargo build
                                        $job | Wait-Job -Timeout 300 | Out-Null
                                        
                                        if ($job.State -eq "Running") {
                                            Stop-Job $job
                                            Remove-Job $job
                                            Write-Warning "Cargo build timed out after 5 minutes. This may indicate network issues or a very large dependency tree."
                                            Write-Info "Try running 'cargo build --release' manually in the rust directory to see the full output."
                                        }
                                        else {
                                            $cargoBuildOutput = Receive-Job $job
                                            Remove-Job $job
                                            
                                            if ($LASTEXITCODE -ne 0) {
                                                Write-Warning "Cargo build failed with exit code: $LASTEXITCODE"
                                                Write-Info "Cargo build output:"
                                                Write-Info $cargoBuildOutput
                                            }
                                            else {
                                                Write-Success "Manual Rust build succeeded! The issue may be with the build environment or cargokit configuration."
                                            }
                                        }
                                    }
                                    catch {
                                        Write-Warning "Manual Rust build failed: $_"
                                        Write-Info "Error details: $($_.Exception.Message)"
                                        Write-Info "Try running 'cargo build --release' manually in the rust directory to see the full output."
                                    }
                                    finally {
                                        Pop-Location
                                    }
                                }
                                
                                # Check if there are any specific Rust compilation errors in the build output
                                if (Test-Path "build_output.txt") {
                                    $rustErrors = Select-String -Path "build_output.txt" -Pattern "error\[|error:|cargo|rustc|CARGOKIT|build_tool" -Context 2,2
                                    if ($rustErrors) {
                                        Write-Info "Rust-related errors found in build output:"
                                        Write-Info $rustErrors
                                    }
                                }
                                
                                # Check cargokit temp directory for logs and errors
                                $cargokitTempDirs = @(
                                    "build\windows\x64\plugins\rust_lib_localsend_app\cargokit_build",
                                    "build\windows\x64\plugins\rust_lib_localsend_app"
                                )
                                
                                # Also check CMakeFiles directories with cargokit in name
                                $cmakeFilesDir = "build\windows\x64\CMakeFiles"
                                if (Test-Path $cmakeFilesDir) {
                                    $cargokitDirs = Get-ChildItem -Path $cmakeFilesDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*cargokit*" }
                                    foreach ($dir in $cargokitDirs) {
                                        $cargokitTempDirs += $dir.FullName
                                    }
                                }
                                
                                foreach ($tempDirPath in $cargokitTempDirs) {
                                    if (Test-Path $tempDirPath) {
                                        $tempDir = Get-Item $tempDirPath
                                        Write-Info "Checking cargokit directory: $($tempDir.FullName)"
                                        
                                        # Look for all files and filter by extension/name
                                        $allFiles = Get-ChildItem -Path $tempDir.FullName -Recurse -File -ErrorAction SilentlyContinue
                                        
                                        # Find log files
                                        $logFiles = $allFiles | Where-Object { 
                                            $_.Extension -eq ".log" -or 
                                            $_.Extension -eq ".txt" -or 
                                            $_.Name -like "*error*" -or 
                                            $_.Name -like "*output*" 
                                        }
                                        
                                        foreach ($logFile in $logFiles) {
                                            Write-Info "Found log file: $($logFile.FullName)"
                                            try {
                                                $logContent = Get-Content $logFile.FullName -Tail 100 -ErrorAction SilentlyContinue
                                                if ($logContent) {
                                                    Write-Info "Last 100 lines of $($logFile.Name):"
                                                    Write-Info $logContent
                                                }
                                            }
                                            catch {
                                                Write-Warning "Could not read log file: $_"
                                            }
                                        }
                                        
                                        # Check for stderr/stdout files
                                        $stdFiles = $allFiles | Where-Object { $_.Name -like "*stderr*" -or $_.Name -like "*stdout*" }
                                        foreach ($stdFile in $stdFiles) {
                                            Write-Info "Found std file: $($stdFile.FullName)"
                                            try {
                                                $stdContent = Get-Content $stdFile.FullName -Tail 100 -ErrorAction SilentlyContinue
                                                if ($stdContent) {
                                                    Write-Info "Content of $($stdFile.Name):"
                                                    Write-Info $stdContent
                                                }
                                            }
                                            catch {
                                                Write-Warning "Could not read std file: $_"
                                            }
                                        }
                                    }
                                }
                                
                                # Check the .rule files for clues
                                $ruleFiles = @(
                                    "build\windows\x64\CMakeFiles\539918c56e7985d6854505ab08f5ca24\rust_lib_localsend_app.dll.rule",
                                    "build\windows\x64\CMakeFiles\d4b818ce06e83b961c57e32dcf7a9a32\rust_lib_localsend_app_cargokit.rule"
                                )
                                foreach ($ruleFile in $ruleFiles) {
                                    if (Test-Path $ruleFile) {
                                        Write-Info "Checking rule file: $ruleFile"
                                        try {
                                            $ruleContent = Get-Content $ruleFile -ErrorAction SilentlyContinue
                                            if ($ruleContent) {
                                                Write-Info "Rule file content:"
                                                Write-Info $ruleContent
                                            }
                                        }
                                        catch {
                                            Write-Warning "Could not read rule file: $_"
                                        }
                                    }
                                }
                                
                                # Try to manually run cargokit build tool to see the actual error
                                Write-Info "Attempting to manually run cargokit build tool to diagnose the issue..."
                                # Note: We're already in the "app" directory from line 734, so no need to Push-Location again
                                try {
                                    $currentDir = (Get-Location).Path
                                    $cargokitBuildTool = Join-Path $currentDir "rust_builder\cargokit\run_build_tool.cmd"
                                    
                                    if (Test-Path $cargokitBuildTool) {
                                        # Find the actual manifest directory from the CMakeLists.txt or plugin symlink
                                        $manifestDir = $null
                                        $pluginSymlink = "windows\flutter\ephemeral\.plugin_symlinks\rust_lib_localsend_app"
                                        if (Test-Path $pluginSymlink) {
                                            $cmakeListsPath = Join-Path $pluginSymlink "windows\CMakeLists.txt"
                                            if (Test-Path $cmakeListsPath) {
                                                $cmakeContent = Get-Content $cmakeListsPath -Raw
                                                
                                                # Parse apply_cargokit(target manifest_dir ...)
                                                # Supports both quoted and unquoted arguments
                                                # Example: apply_cargokit(${PROJECT_NAME} ../../../../../../rust rust_lib_localsend_app "")
                                                if ($cmakeContent -match 'apply_cargokit\s*\(\s*\S+\s+([^)\s]+)') {
                                                    $foundDir = $matches[1].Trim('"').Trim("'")
                                                    # Basic validation to avoid invalid path characters
                                                    if ($foundDir -notmatch '[<>:"|?*]') {
                                                        $manifestDir = $foundDir
                                                        Write-Info "Found manifest directory from CMakeLists.txt: $manifestDir"
                                                    }
                                                }
                                                # Fallback for old format with quotes if regex above didn't match or path was invalid
                                                elseif ($cmakeContent -match 'apply_cargokit[^)]*"([^"]+)"') {
                                                    $foundDir = $matches[1]
                                                    if ($foundDir -notmatch '[<>:"|?*]') {
                                                        $manifestDir = $foundDir
                                                        Write-Info "Found manifest directory from CMakeLists.txt (quoted): $manifestDir"
                                                    }
                                                }
                                            }
                                        }
                                        
                                        # Resolve manifest directory path
                                        $manifestDirFull = $null
                                        
                                        # 1. Try relative to CMakeLists.txt if found there
                                        if ($manifestDir -and $cmakeListsPath) {
                                            $cmakeListsAbsPath = Join-Path $currentDir $cmakeListsPath
                                            if (Test-Path $cmakeListsAbsPath) {
                                                try {
                                                    $cmakeListsDir = Split-Path $cmakeListsAbsPath
                                                    $potentialPath = Join-Path $cmakeListsDir $manifestDir
                                                    if (Test-Path $potentialPath) {
                                                        $manifestDirFull = (Resolve-Path $potentialPath).Path
                                                    }
                                                } catch {
                                                    Write-Warning "Could not resolve path relative to CMakeLists.txt: $_"
                                                }
                                            }
                                        }
                                        
                                        # 2. Try default location relative to project root (app/rust)
                                        if (-not $manifestDirFull) {
                                            try {
                                                $potentialPath = Join-Path $currentDir "rust"
                                                if (Test-Path $potentialPath) {
                                                    $manifestDirFull = $potentialPath
                                                }
                                            } catch {}
                                        }
                                        
                                        # 3. Try relative to current dir if manifestDir is just a name like "rust"
                                        if (-not $manifestDirFull -and $manifestDir -and $manifestDir -notmatch '\.\.') {
                                            try {
                                                $potentialPath = Join-Path $currentDir $manifestDir
                                                if (Test-Path $potentialPath) {
                                                    $manifestDirFull = $potentialPath
                                                }
                                            } catch {}
                                        }

                                        # Verify manifest directory exists
                                        if (-not $manifestDirFull -or -not (Test-Path $manifestDirFull)) {
                                            Write-Warning "Manifest directory not found via standard paths"
                                            Write-Info "Trying alternative paths..."
                                            $altPaths = @(
                                                Join-Path $currentDir "rust",
                                                Join-Path (Get-Location).Path "..\rust",
                                                Join-Path (Get-Location).Path "..\..\rust"
                                            )
                                            foreach ($altPath in $altPaths) {
                                                if (Test-Path $altPath) {
                                                    $manifestDirFull = $altPath
                                                    Write-Info "Found manifest directory at: $manifestDirFull"
                                                    break
                                                }
                                            }
                                        }
                                        
                                        if (-not (Test-Path $manifestDirFull)) {
                                            Write-Warning "Could not find Rust manifest directory. Skipping cargokit test."
                                        }
                                        else {
                                            # Set up environment variables similar to what CMake would set
                                            $env:CARGOKIT_CMAKE = $cmakePath
                                            $env:CARGOKIT_CONFIGURATION = "Release"
                                            $env:CARGOKIT_MANIFEST_DIR = $manifestDirFull
                                            $env:CARGOKIT_TARGET_PLATFORM = "windows-x64"
                                            $env:CARGOKIT_ROOT_PROJECT_DIR = $currentDir
                                            
                                            $tempDir = "build\windows\x64\plugins\rust_lib_localsend_app\cargokit_build"
                                            $tempDirFull = Join-Path $currentDir $tempDir
                                            if (-not (Test-Path $tempDirFull)) {
                                                New-Item -ItemType Directory -Force -Path $tempDirFull | Out-Null
                                            }
                                            $env:CARGOKIT_TARGET_TEMP_DIR = $tempDirFull
                                            
                                            $outputDir = "build\windows\x64\Release"
                                            $outputDirFull = Join-Path $currentDir $outputDir
                                            if (-not (Test-Path $outputDirFull)) {
                                                New-Item -ItemType Directory -Force -Path $outputDirFull | Out-Null
                                            }
                                            $env:CARGOKIT_OUTPUT_DIR = $outputDirFull
                                            $env:CARGOKIT_TOOL_TEMP_DIR = Join-Path $tempDirFull "tool"
                                            
                                            # Ensure FLUTTER_ROOT is set correctly for cargokit and resolve absolute path
                                            $flutterPath = Join-Path (Get-Location).Path "..\submodules\flutter\bin\flutter.bat"
                                            if (Test-Path $flutterPath) {
                                                $resolvedFlutterPath = (Resolve-Path $flutterPath).Path
                                                $env:FLUTTER_ROOT = (Split-Path (Split-Path $resolvedFlutterPath))
                                                Write-Info "Set FLUTTER_ROOT: $env:FLUTTER_ROOT"
                                                
                                                # Verify Dart execution
                                                $dartExe = Join-Path $env:FLUTTER_ROOT "bin\cache\dart-sdk\bin\dart.exe"
                                                Write-Info "Verifying Dart execution: & `"$dartExe`" --version"
                                                try {
                                                    & $dartExe --version 2>&1 | Out-String | Write-Info
                                                } catch {
                                                    Write-Warning "Failed to run Dart directly: $_"
                                                }
                                            }
                                            elseif (-not $env:FLUTTER_ROOT) {
                                                Write-Warning "Could not determine FLUTTER_ROOT. Cargokit might fail."
                                            }
                                            
                                            Write-Info "Running cargokit build tool: $cargokitBuildTool"
                                            
                                            # Ensure temp directories exist
                                            if (-not (Test-Path $env:CARGOKIT_TOOL_TEMP_DIR)) {
                                                Write-Info "Creating temp directory: $env:CARGOKIT_TOOL_TEMP_DIR"
                                                New-Item -ItemType Directory -Force -Path $env:CARGOKIT_TOOL_TEMP_DIR | Out-Null
                                            }
                                            
                                            Write-Info "Environment:"
                                            Write-Info "  CARGOKIT_CMAKE: $env:CARGOKIT_CMAKE"
                                            # ... (rest of logs)
                                            
                                            # Use Start-Process for better control and to capture output reliably
                                            try {
                                                $pInfo = New-Object System.Diagnostics.ProcessStartInfo
                                                $pInfo.FileName = "cmd.exe"
                                                $pInfo.Arguments = "/c `"$cargokitBuildTool`" build-cmake"
                                                $pInfo.RedirectStandardOutput = $true
                                                $pInfo.RedirectStandardError = $true
                                                $pInfo.UseShellExecute = $false
                                                $pInfo.CreateNoWindow = $true
                                                
                                                # Pass environment variables explicitly if needed, but they are inherited by default
                                                # We rely on inheritance here since we set $env:VAR in the current process
                                                
                                                $p = [System.Diagnostics.Process]::Start($pInfo)
                                                $stdout = $p.StandardOutput.ReadToEnd()
                                                $stderr = $p.StandardError.ReadToEnd()
                                                $p.WaitForExit()
                                                
                                                Write-Info "Cargokit stdout:"
                                                Write-Info $stdout
                                                if ($stderr) {
                                                    Write-Info "Cargokit stderr:"
                                                    Write-Info $stderr
                                                }
                                                
                                                if ($p.ExitCode -ne 0) {
                                                    Write-Warning "Cargokit build tool failed with exit code: $($p.ExitCode)"
                                                } else {
                                                    Write-Success "Cargokit build tool succeeded!"
                                                }
                                            } catch {
                                                Write-Warning "Failed to launch cargokit process: $_"
                                            }
                                        }
                                    }
                                    else {
                                        Write-Warning "Cargokit build tool not found at: $cargokitBuildTool"
                                        Write-Info "Searched in: $currentDir"
                                    }
                                }
                                catch {
                                    Write-Warning "Failed to run cargokit build tool: $_"
                                    Write-Info "Error details: $($_.Exception.Message)"
                                    Write-Info "Stack trace: $($_.ScriptStackTrace)"
                                }
                                # Note: No Pop-Location needed here since we didn't Push-Location (we're already in "app" directory)
                            }
                            else {
                                Write-Warning "Rust (cargo) not found! Attempting to install..."
                                Ensure-Rust
                            }
                        }
                    }
                }
                
                if (Test-Path "build_output.txt") {
                    $output = Get-Content "build_output.txt" -Tail 50 -ErrorAction SilentlyContinue
                    if ($output) {
                        Write-Info "Last 50 lines of build output:"
                        Write-Info $output
                    }
                }
                
                # Check if executable was created despite the error
                $buildPath = "build\windows\x64\runner\Release"
                $exeFile = Join-Path $buildPath "localsend_app.exe"
                if (Test-Path $exeFile) {
                    $exeFullPath = (Resolve-Path $exeFile).Path
                    Write-Warning "Build failed, but executable file exists at: $exeFullPath"
                    Write-Info "You can try to use it, but it may be incomplete or broken."
                }
                
                # Read and display error output if available
                $errorMessage = "Flutter build failed"
                $exitCode = if ($null -ne $buildProcess.ExitCode) { $buildProcess.ExitCode } else { "unknown" }
                $errorMessage += " with exit code: $exitCode"
                
                if (Test-Path "build_error.txt") {
                    $errorOutput = Get-Content "build_error.txt" -Raw -ErrorAction SilentlyContinue
                    if ($errorOutput -and $errorOutput.Trim()) {
                        Write-Host ""
                        Write-Host "=== Build Error Output ===" -ForegroundColor Red
                        Write-Host $errorOutput -ForegroundColor Red
                        Write-Host "==========================" -ForegroundColor Red
                        $errorMessage += "`n`nError output:`n$errorOutput"
                    }
                }
                
                if (Test-Path "build_output.txt") {
                    $output = Get-Content "build_output.txt" -Tail 100 -ErrorAction SilentlyContinue
                    if ($output -and $output.Count -gt 0) {
                        Write-Host ""
                        Write-Host "=== Last 100 lines of Build Output ===" -ForegroundColor Yellow
                        Write-Host ($output -join "`n") -ForegroundColor Yellow
                        Write-Host "======================================" -ForegroundColor Yellow
                    }
                }

                $debugLog = "E:\PPROJECTS\scn\cargokit_debug.log"
                $envLog = "E:\PPROJECTS\scn\cargokit_env.log"
                $exitLog = "E:\PPROJECTS\scn\cargokit_exit.log"

                if (Test-Path $debugLog) {
                    Write-Host ""
                    Write-Host "=== Cargokit Debug Log ===" -ForegroundColor Cyan
                    Get-Content $debugLog | Write-Host -ForegroundColor Cyan
                    Write-Host "==========================" -ForegroundColor Cyan
                }

                if (Test-Path $envLog) {
                    Write-Host ""
                    Write-Host "=== Cargokit Environment Dump (FLUTTER related) ===" -ForegroundColor Cyan
                    Get-Content $envLog | Select-String "FLUTTER" | Write-Host -ForegroundColor Cyan
                    Write-Host "================================================" -ForegroundColor Cyan
                }

                if (Test-Path $exitLog) {
                    Write-Host ""
                    Write-Host "=== Cargokit Exit Code Log ===" -ForegroundColor Cyan
                    Get-Content $exitLog | Write-Host -ForegroundColor Cyan
                    Write-Host "=============================" -ForegroundColor Cyan
                }

                # Check if cargokit output files were created
                # Note: We're already in "app" directory from line 900, so no Push-Location needed
                $cargokitOutputDirs = @(
                    "build\windows\x64\plugins\rust_lib_localsend_app\Release",
                    "build\windows\x64\plugins\rust_lib_localsend_app\Debug",
                    "build\windows\x64\plugins\rust_lib_localsend_app"
                )
                foreach ($dir in $cargokitOutputDirs) {
                    if (Test-Path $dir) {
                        $dllFiles = Get-ChildItem -Path $dir -Filter "rust_lib_localsend_app.dll" -ErrorAction SilentlyContinue
                        $libFiles = Get-ChildItem -Path $dir -Filter "rust_lib_localsend_app.lib" -ErrorAction SilentlyContinue
                        if ($dllFiles -or $libFiles) {
                            Write-Host ""
                            Write-Host "=== Cargokit Output Files Found ===" -ForegroundColor Green
                            if ($dllFiles) { Write-Host "DLL: $($dllFiles[0].FullName)" -ForegroundColor Green }
                            if ($libFiles) { Write-Host "LIB: $($libFiles[0].FullName)" -ForegroundColor Green }
                            Write-Host "===================================" -ForegroundColor Green
                        }
                    }
                }
                
                throw $errorMessage
            }
        }
        catch {
            Pop-Location
            throw
        }
        finally {
            Pop-Location
        }
    }
    else {
        # Fallback to normal build if CMake path is not set
        Invoke-FlutterCommand "build windows"
    }
    
    # After successful build, fix CMake paths in generated files for future builds
    Push-Location "app"
    try {
        $buildDir = "build\windows\x64"
        if (Test-Path $buildDir -and $null -ne $cmakePath) {
            Fix-CMakePaths -BuildDir $buildDir -CmakeExePath $cmakePath
        }
    }
    catch {
        Write-Warning "Could not fix CMake paths: $_"
    }
    finally {
        Pop-Location
    }
    
    Push-Location "app"
    try {
        $buildPath = "build\windows\x64\runner\Release"
        
        if (-not (Test-Path $buildPath)) {
            throw "Build path not found: $buildPath"
        }
        
        # Show executable file location
        $exeFile = Join-Path $buildPath "localsend_app.exe"
        if (Test-Path $exeFile) {
            $exeFullPath = (Resolve-Path $exeFile).Path
            Write-Success "Executable file location: $exeFullPath"
            
            # Copy required DLLs if they're missing (INSTALL step may have failed)
            Write-Info "Checking for required DLLs..."
            $requiredDlls = @(
                @{ Name = "flutter_windows.dll"; Source = "build\windows\x64\flutter\Release\flutter_windows.dll" },
                @{ Name = "rust_lib_localsend_app.dll"; Source = "build\windows\x64\plugins\rust_lib_localsend_app\Release\rust_lib_localsend_app.dll" }
            )
            
            $dllsCopied = $false
            foreach ($dll in $requiredDlls) {
                $targetDll = Join-Path $buildPath $dll.Name
                if (-not (Test-Path $targetDll)) {
                    $sourceDll = Join-Path (Get-Location) $dll.Source
                    if (Test-Path $sourceDll) {
                        Copy-Item -Path $sourceDll -Destination $targetDll -Force
                        Write-Success "Copied $($dll.Name) to $buildPath"
                        $dllsCopied = $true
                    } else {
                        Write-Warning "$($dll.Name) not found at expected location: $sourceDll"
                        # Try to find it elsewhere
                        $foundDll = Get-ChildItem -Path "build\windows\x64" -Recurse -Filter $dll.Name -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($foundDll) {
                            Copy-Item -Path $foundDll.FullName -Destination $targetDll -Force
                            Write-Success "Copied $($dll.Name) from $($foundDll.FullName) to $buildPath"
                            $dllsCopied = $true
                        } else {
                            Write-Warning "$($dll.Name) not found anywhere in build directory"
                        }
                    }
                } else {
                    Write-Info "$($dll.Name) already exists in $buildPath"
                }
            }
            
            if ($dllsCopied) {
                Write-Info "DLLs copied successfully. The executable should now work."
            }
        }
        else {
            Write-Warning "Executable file not found at: $exeFile"
            Write-Info "Build may not have completed successfully."
        }
        
        if ($Type -eq 'zip') {
            $version = (Get-Content "pubspec.yaml" | Select-String "version:" | ForEach-Object { ($_ -split ':')[1].Trim() })
            $zipName = "LocalSend-$version-windows-x86-64.zip"
            
            Write-Info "Creating ZIP archive: $zipName"
            
            if (Test-Path $zipName) {
                Remove-Item $zipName -Force
            }
            
            Compress-Archive -Path "$buildPath\*" -DestinationPath $zipName -CompressionLevel Optimal
            $zipFullPath = (Resolve-Path $zipName -ErrorAction SilentlyContinue).Path
            if (-not $zipFullPath) {
                $zipFullPath = Join-Path (Get-Location).Path $zipName
            }
            Write-Success "ZIP archive created: $zipFullPath"
            Write-Info "You can find the executable at: $exeFullPath"
        }
        elseif ($Type -eq 'exe') {
            Write-Info "Preparing EXE installer creation..."
            
            if (-not (Test-Command "iscc")) {
                throw "Inno Setup Compiler (iscc) not found! Install Inno Setup and add to PATH."
            }
            
            $tempDir = "D:\inno"
            $resultDir = "D:\inno-result"
            
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
            
            Write-Info "Copying build files..."
            Copy-Item -Path "$buildPath\*" -Destination $tempDir -Recurse
            Copy-Item -Path "assets\packaging\logo.ico" -Destination $tempDir -ErrorAction SilentlyContinue
            
            $scriptsDllPath = "..\scripts\windows\x64"
            if (Test-Path $scriptsDllPath) {
                Copy-Item -Path "$scriptsDllPath\*" -Destination $tempDir -Recurse
            }
            
            if (Test-Path $resultDir) {
                Remove-Item $resultDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
            
            Write-Info "Compiling EXE installer..."
            Push-Location ".."
            try {
                & iscc ".\scripts\compile_windows_exe-inno.iss"
                if (-not $? -or ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0)) {
                    throw "Inno Setup compilation error"
                }
            }
            finally {
                Pop-Location
            }
            
                   Write-Success "EXE installer created in: $resultDir"
                   Write-Info "You can find the executable at: $exeFullPath"
               }
           }
           finally {
               Pop-Location
           }
           
           Write-Success "Windows build completed!"
           Write-Host ""
           Write-Host "========================================" -ForegroundColor Green
           Write-Info "Build output locations:"
           if ($Type -eq 'zip') {
               if ($zipFullPath) {
                   Write-Info "  ZIP archive: $zipFullPath"
               }
           }
           elseif ($Type -eq 'exe') {
               Write-Info "  EXE installer: $resultDir"
           }
           if ($exeFullPath) {
               Write-Info "  Executable: $exeFullPath"
           }
           Write-Host "========================================" -ForegroundColor Green
           Write-Host ""
       }

function Build-Linux {
    Write-Info "Starting Linux build (AppImage)..."
    
    if (-not (Test-Command "appimage-builder")) {
        Write-Warning "appimage-builder not found!"
        Write-Info "Install appimage-builder:"
        Write-Info "  sudo apt install libfuse2"
        Write-Info "  wget https://github.com/AppImageCrafters/appimage-builder/releases/download/v1.1.0/appimage-builder-1.1.0-x86_64.AppImage"
        Write-Info "  chmod +x appimage-builder-1.1.0-x86_64.AppImage"
        Write-Info "  sudo mv appimage-builder-1.1.0-x86_64.AppImage /usr/local/bin/appimage-builder"
        throw "appimage-builder is not installed"
    }
    
    if ($Clean) {
        Write-Info "Cleaning project..."
        Invoke-FlutterCommand "clean"
    }
    
    Write-Info "Getting dependencies..."
    Invoke-FlutterCommand "pub get"
    
    if (-not $SkipBuildRunner) {
        Write-Info "Running build_runner..."
        Invoke-FlutterCommand "pub run build_runner build -d"
    }
    
    Write-Info "Building Linux application..."
    Invoke-FlutterCommand "build linux"
    
    Push-Location "app"
    try {
        $bundlePath = "build/linux/x64/release/bundle"
        
        if (-not (Test-Path $bundlePath)) {
            throw "Build path not found: $bundlePath"
        }
        
        if (Test-Path "AppDir") {
            Remove-Item "AppDir" -Recurse -Force
        }
        if (Test-Path "appimage-build") {
            Remove-Item "appimage-build" -Recurse -Force
        }
        
        Write-Info "Preparing AppDir..."
        New-Item -ItemType Directory -Force -Path "AppDir" | Out-Null
        Copy-Item -Path "$bundlePath/*" -Destination "AppDir" -Recurse
        
        $arch = "x86_64"
        if ((Test-IsLinux) -or (Test-Command "uname")) {
            try {
                $unameOutput = & uname -m 2>$null
                if ($unameOutput -like "*arm*" -or $unameOutput -like "*aarch64*") {
                    $arch = "arm_64"
                    Write-Info "Detected ARM architecture: $unameOutput"
                }
                else {
                    Write-Info "Detected architecture: $unameOutput"
                }
            }
            catch {
                Write-Warning "Failed to detect architecture, using x86_64"
            }
        }
        
        $recipeFile = "..\scripts\appimage\AppImageBuilder_$arch.yml"
        
        if (-not (Test-Path $recipeFile)) {
            Write-Warning "Recipe for architecture $arch not found, using x86_64"
            $recipeFile = "..\scripts\appimage\AppImageBuilder_x86_64.yml"
        }
        
        Write-Info "Creating AppImage (architecture: $arch)..."
        & appimage-builder --recipe $recipeFile
        
        if (-not $? -or ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0)) {
            throw "AppImage creation error"
        }
        
        $appImageFiles = Get-ChildItem -Filter "*.AppImage" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*LocalSend*" }
        
        if ($appImageFiles) {
            $appImage = $appImageFiles[0]
            Write-Info "Setting execute permissions for: $($appImage.Name)"
            if ((Test-IsLinux)) {
                & chmod +x $appImage.FullName 2>$null
            }
            elseif (Test-Command "chmod") {
                & chmod +x $appImage.FullName 2>$null
            }
            Write-Success "AppImage created: $($appImage.FullName)"
        }
        else {
            Write-Warning "AppImage file not found, but build completed"
            Write-Info "Check appimage-builder output for details"
        }
        
        if (Test-Path "AppDir") {
            Remove-Item "AppDir" -Recurse -Force
        }
        if (Test-Path "appimage-build") {
            Remove-Item "appimage-build" -Recurse -Force
        }
    }
    finally {
        Pop-Location
    }
    
    Write-Success "Linux build completed!"
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "  SCN Build Script" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

# Check project exists
if ($Project -eq 'scn') {
    if (-not (Test-Path "scn\pubspec.yaml")) {
        throw "Project not found at scn\"
    }
}

$buildWindows = ($Platform -eq 'windows' -or $Platform -eq 'all')
$buildLinux = ($Platform -eq 'linux' -or $Platform -eq 'all')

# Linux build not yet supported
if ($buildLinux) {
    Write-Warning "Linux build not yet supported. Skipping..."
    $buildLinux = $false
}

$isWindows = Test-IsWindows
$isLinux = Test-IsLinux

if ($buildWindows -and -not $isWindows) {
    Write-Warning "Windows build on Linux may not work correctly"
}

if ($buildLinux -and $isWindows) {
    Write-Warning "Linux build on Windows may not work correctly"
    Write-Info "Consider using WSL or Linux machine for Linux build"
}

$startTime = Get-Date

try {
    if ($buildWindows) {
        if ($Project -eq 'scn') {
            Build-Simple -Type $BuildType
        } else {
            Build-Windows -Type $BuildType
        }
        Write-Host ""
    }
    
    if ($buildLinux) {
        Build-Linux
        Write-Host ""
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Success "All builds completed successfully!"
    $durationStr = "{0:mm\:ss}" -f $duration
    Write-Info "Execution time: $durationStr"
    
    # Show build output locations
    Write-Host ""
    Write-Info "Build output locations:"
    if ($buildWindows) {
        if ($Project -eq 'scn') {
            Push-Location "scn"
            try {
                $buildPath = "build\windows\x64\runner\Release"
                $exeFile = Join-Path $buildPath "scn.exe"
                if (Test-Path $exeFile) {
                    $exeFullPath = (Resolve-Path $exeFile).Path
                    Write-Info "  Windows executable: $exeFullPath"
                }
            }
            catch {
                # Ignore errors when showing output locations
            }
            finally {
                Pop-Location
            }
        } else {
            Push-Location "app"
            try {
                $buildPath = "build\windows\x64\runner\Release"
                $exeFile = Join-Path $buildPath "localsend_app.exe"
                if (Test-Path $exeFile) {
                    $exeFullPath = (Resolve-Path $exeFile).Path
                    Write-Info "  Windows executable: $exeFullPath"
                }
                
                if ($BuildType -eq 'zip') {
                    $version = (Get-Content "pubspec.yaml" | Select-String "version:" | ForEach-Object { ($_ -split ':')[1].Trim() })
                    $zipName = "LocalSend-$version-windows-x86-64.zip"
                    if (Test-Path $zipName) {
                        $zipFullPath = (Resolve-Path $zipName).Path
                        Write-Info "  Windows ZIP archive: $zipFullPath"
                    }
                }
                elseif ($BuildType -eq 'exe') {
                    $resultDir = "D:\inno-result"
                    if (Test-Path $resultDir) {
                        Write-Info "  Windows EXE installer: $resultDir"
                    }
                }
            }
            catch {
                # Ignore errors when showing output locations
            }
            finally {
                Pop-Location
            }
        }
    }
    
    if ($buildLinux) {
        Push-Location "app"
        try {
            $appImageFiles = Get-ChildItem -Filter "*.AppImage" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*LocalSend*" }
            if ($appImageFiles) {
                $appImage = $appImageFiles[0]
                $appImageFullPath = (Resolve-Path $appImage.FullName).Path
                Write-Info "  Linux AppImage: $appImageFullPath"
            }
        }
        catch {
            # Ignore errors when showing output locations
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Host "========================================`n" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    $errorDetails = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $errorDetails += "`nInner exception: $($_.Exception.InnerException.Message)"
    }
    Write-ErrorMsg "Build error: $errorDetails"
    
    # If error message contains newlines, it might have detailed output - display it
    if ($errorDetails -match "`n") {
        Write-Host ""
        Write-Host "=== Detailed Error Information ===" -ForegroundColor Red
        Write-Host $errorDetails -ForegroundColor Red
        Write-Host "==================================" -ForegroundColor Red
    }
    
    # Show build output locations even if build failed
    Write-Host ""
    Write-Info "Checking for partially built files..."
    if ($buildWindows -and $Project -eq 'scn') {
        Push-Location "scn"
        try {
            $buildPath = "build\windows\x64\runner\Release"
            $exeFile = Join-Path $buildPath "scn.exe"
            if (Test-Path $exeFile) {
                $exeFullPath = (Resolve-Path $exeFile).Path
                Write-Warning "Partially built executable found at: $exeFullPath"
                Write-Info "  Note: This file may be incomplete or broken due to build failure."
            }
            else {
                Write-Info "  Executable not found. Build did not complete successfully."
            }
        }
        catch {
            # Ignore errors
        }
        finally {
            Pop-Location
        }
    }
    
    Write-Host "========================================`n" -ForegroundColor Red
    exit 1
}
