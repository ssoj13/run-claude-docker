param(
    [switch]$Fix,
    [switch]$Bootstrap
)

function Show-Help {
    Write-Host "docker-fix.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\\docker-fix.ps1 -Fix [-Bootstrap]" -ForegroundColor Yellow
    Write-Host "  .\\docker-fix.ps1 -Bootstrap" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "What it does:" -ForegroundColor White
    Write-Host "  -Fix        Creates ~/.docker/config.json in WSL without credsStore and pulls ubuntu:25.04" -ForegroundColor Gray
    Write-Host "  -Bootstrap  Runs bootstrap.ps1 after applying the fix" -ForegroundColor Gray
    Write-Host ""
}

if (-not $Fix -and -not $Bootstrap) {
    Show-Help
    exit 0
}

if ($Bootstrap) {
    $Fix = $true
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Docker Fix for run-claude-docker" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking WSL..." -ForegroundColor Yellow
$wslPath = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wslPath) {
    Write-Host "Error: WSL is not installed" -ForegroundColor Red
    exit 1
}
Write-Host "WSL found" -ForegroundColor Green

Write-Host "Checking Docker in WSL..." -ForegroundColor Yellow
try {
    $dockerVersion = wsl -e bash -c "docker --version 2>/dev/null"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Docker not found in WSL" -ForegroundColor Red
        exit 1
    }
    Write-Host "Docker found: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "Error checking Docker in WSL" -ForegroundColor Red
    exit 1
}

if ($Fix) {
    Write-Host "Applying fix in WSL..." -ForegroundColor Yellow

    $wslDists = wsl -l --quiet | Where-Object { $_ -ne "" }
    if ($wslDists.Count -eq 0) {
        Write-Host "No active WSL distributions found" -ForegroundColor Red
        exit 1
    }

    foreach ($dist in $wslDists) {
        Write-Host "Configuring: $dist" -ForegroundColor Yellow
        wsl -d $dist -e bash -c "mkdir -p ~/.docker"
        $dockerConfig = '{"credsStore":""}'
        wsl -d $dist -e bash -c "echo '$dockerConfig' > ~/.docker/config.json"
        Write-Host "Docker config updated for $dist" -ForegroundColor Green
    }

    Write-Host "Pulling ubuntu:25.04..." -ForegroundColor Yellow
    $pullResult = wsl -e bash -c "docker pull ubuntu:25.04"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error pulling ubuntu:25.04" -ForegroundColor Red
        Write-Host $pullResult
        exit 1
    }
    Write-Host "Base image pulled" -ForegroundColor Green
}

if ($Bootstrap) {
    Write-Host ""
    Write-Host "Running bootstrap.ps1..." -ForegroundColor Cyan
    & "$PSScriptRoot\\bootstrap.ps1"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
