<#
.SYNOPSIS
  Pack SCN sources for copying to another machine (build there).

.DESCRIPTION
  Creates a zip without flutter-sdk, releases, build artifacts, .git, test DLLs.
  build.ps1 will download Flutter 3.24.5 automatically on the target PC.

.EXAMPLE
  .\pack-transport.ps1
  .\pack-transport.ps1 -OutDir D:\usb\scn-pack
#>
param(
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if (-not $OutDir) {
    $OutDir = Join-Path $Root "transport"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$stageName = "scn-sources-$stamp"
$stage = Join-Path $OutDir $stageName
$zipPath = Join-Path $OutDir "$stageName.zip"

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

function Copy-TreeFiltered {
    param(
        [string]$Src,
        [string]$Dst,
        [string[]]$ExcludeDirNames,
        [string[]]$ExcludeFileGlobs
    )
    if (-not (Test-Path $Src)) { return }
    New-Item -ItemType Directory -Path $Dst -Force | Out-Null

    Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
        $name = $_.Name
        if ($_.PSIsContainer) {
            if ($ExcludeDirNames -contains $name) { return }
            Copy-TreeFiltered -Src $_.FullName -Dst (Join-Path $Dst $name) `
                -ExcludeDirNames $ExcludeDirNames -ExcludeFileGlobs $ExcludeFileGlobs
            return
        }
        foreach ($g in $ExcludeFileGlobs) {
            if ($name -like $g) { return }
        }
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dst $name) -Force
    }
}

$excludeDirs = @(
    '.git', '.cursor', '.idea', '.vscode',
    'flutter-sdk', 'submodules', 'releases', 'transport',
    'build', '.dart_tool', 'ephemeral',
    'node_modules', '__pycache__'
)

$excludeFiles = @(
    '*.log', '*.pdb', '*.ilk', '*.exp', '*.lib',
    '_test_*.dll', '_bisect.dll', '_test_pefile*.dll',
    'flutter_windows.dll', 'flutter_windows.dll.pdb',
    'Thumbs.db', '.DS_Store'
)

Write-Host "Staging sources -> $stage" -ForegroundColor Cyan

# Root files
@(
    'build.ps1', 'build.sh', 'generate_icon.ps1',
    'README.md', 'TRANSPORT_BUILD.md',
    '.gitignore', '.gitattributes', '.fvmrc', '.cursorrules',
    'pack-transport.ps1'
) | ForEach-Object {
    $p = Join-Path $Root $_
    if (Test-Path $p) {
        Copy-Item $p (Join-Path $stage $_) -Force
    }
}

# Core trees
Copy-TreeFiltered -Src (Join-Path $Root 'scn') -Dst (Join-Path $stage 'scn') `
    -ExcludeDirNames $excludeDirs -ExcludeFileGlobs $excludeFiles

Copy-TreeFiltered -Src (Join-Path $Root 'server') -Dst (Join-Path $stage 'server') `
    -ExcludeDirNames $excludeDirs -ExcludeFileGlobs $excludeFiles

Copy-TreeFiltered -Src (Join-Path $Root 'memory-bank') -Dst (Join-Path $stage 'memory-bank') `
    -ExcludeDirNames $excludeDirs -ExcludeFileGlobs $excludeFiles

# Smoke scripts only (no binary dumps)
$ltDst = Join-Path $stage '_loadtest'
New-Item -ItemType Directory -Path $ltDst -Force | Out-Null
Get-ChildItem (Join-Path $Root '_loadtest') -File -Filter '*.py' -EA SilentlyContinue |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $ltDst $_.Name) -Force }
Get-ChildItem (Join-Path $Root '_loadtest') -File -Filter '*.md' -EA SilentlyContinue |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $ltDst $_.Name) -Force }

# Tiny note inside archive
@"
SCN source pack created: $stamp
Build on target: see TRANSPORT_BUILD.md
Do NOT copy flutter-sdk / releases — build.ps1 downloads Flutter itself.
"@ | Set-Content -Encoding UTF8 (Join-Path $stage 'PACK_INFO.txt')

Write-Host "Compressing..." -ForegroundColor Cyan
# Compress-Archive struggles with long paths / large trees sometimes; use .NET
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stage,
    $zipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "[OK] $zipPath ($sizeMb MB)" -ForegroundColor Green
Write-Host "Folder (unpacked twin): $stage" -ForegroundColor Gray
Write-Host ""
Write-Host "On the other PC:" -ForegroundColor Yellow
Write-Host "  1. Unzip to e.g. C:\PROJECTS\scn"
Write-Host "  2. Install VS 2022 Build Tools (Desktop C++) + Python 3"
Write-Host "  3. .\build.ps1"
Write-Host "  4. Output: releases\windows\scn.exe"
