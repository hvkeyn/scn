# SCN Test Mode - Launch multiple instances for local testing
# Usage: .\test-mode.ps1 [number_of_instances]

param(
    [int]$Instances = 2
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           SCN TEST MODE - Local Network Simulation           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting $Instances test instances..." -ForegroundColor Yellow
Write-Host ""

# Kill any existing scn.exe processes first
$existingProcesses = Get-Process -Name "scn" -ErrorAction SilentlyContinue
if ($existingProcesses) {
    Write-Host "Stopping existing SCN instances..." -ForegroundColor Yellow
    $existingProcesses | Stop-Process -Force
    Start-Sleep -Seconds 1
}

# Launch instances
for ($i = 0; $i -lt $Instances; $i++) {
    $port = 53317 + ($i * 10)
    $meshPort = 53318 + ($i * 10)
    
    Write-Host "Instance #$($i + 1):" -ForegroundColor Green
    Write-Host "  HTTP Port: $port" -ForegroundColor Gray
    Write-Host "  Mesh Port: $meshPort" -ForegroundColor Gray
    
    # Start instance in new window
    if (Test-Path "$ScriptDir\build\windows\x64\runner\Release\scn.exe") {
        Start-Process -FilePath "$ScriptDir\build\windows\x64\runner\Release\scn.exe" `
            -ArgumentList "--instance=$i" `
            -WindowStyle Normal
    } else {
        Write-Host "  Starting via Flutter..." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$ScriptDir'; flutter run --dart-entrypoint-args='--instance=$i'"
    }
    
    # Wait a bit between launches
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "All instances started!" -ForegroundColor Green
Write-Host ""
Write-Host "To connect instances:" -ForegroundColor Yellow
Write-Host "  1. In Instance #1: Settings > Add Remote Peer > 127.0.0.1:53327" -ForegroundColor Gray
Write-Host "  2. Or use the 'Test: Connect localhost' button in Settings" -ForegroundColor Gray
Write-Host ""
Write-Host "Ports used:" -ForegroundColor Yellow
for ($i = 0; $i -lt $Instances; $i++) {
    $port = 53317 + ($i * 10)
    Write-Host "  Instance #$($i + 1): localhost:$port" -ForegroundColor Gray
}
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

