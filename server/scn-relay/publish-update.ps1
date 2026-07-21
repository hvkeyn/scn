<#
.SYNOPSIS
  Publish a Windows portable zip to the local relay updates/ folder.

.EXAMPLE
  .\publish-update.ps1 -SourceZip C:\PROJECTS\scn\releases\windows_build223.zip -Build 223
#>
param(
  [Parameter(Mandatory = $true)][string]$SourceZip,
  [Parameter(Mandatory = $true)][int]$Build,
  [string]$Version = "1.0.0",
  [string]$UpdatesDir = (Join-Path $PSScriptRoot "updates"),
  [string]$PublicBase = "http://5.187.4.132:53319"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $SourceZip)) { throw "Zip not found: $SourceZip" }
New-Item -ItemType Directory -Force -Path $UpdatesDir | Out-Null

$destZip = Join-Path $UpdatesDir "scn-windows.zip"
Copy-Item -Force $SourceZip $destZip
$hash = (Get-FileHash -Algorithm SHA256 $destZip).Hash.ToLowerInvariant()

$manifest = @{
  version = $Version
  build = $Build
  versionString = "$Version+$Build"
  url = "$PublicBase/scn/scn-windows.zip"
  sha256 = $hash
  mandatory = $false
  changes = @(
    "Build $Build"
  )
} | ConvertTo-Json -Depth 5

$manifestPath = Join-Path $UpdatesDir "update.json"
Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
Write-Host "Published:"
Write-Host "  $destZip"
Write-Host "  $manifestPath"
Write-Host "  sha256=$hash"
Write-Host "Clients check: $PublicBase/scn/update.json"
