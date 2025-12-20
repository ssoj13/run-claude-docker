# Claude Code Docker Bootstrap Script
# Rebuilds the image from scratch every time

param(
    [string]$ImageName = "claude-code-joss:latest",
    [switch]$Clear,
    [switch]$Rebuild,
    [switch]$Verbose
)

# Don't stop on non-critical errors
$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Docker Bootstrap" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check for WSL
$wslPath = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $wslPath) {
    Write-Host "Error: WSL is required to run this script" -ForegroundColor Red
    exit 1
}

# If -Rebuild, do full cleanup
if ($Rebuild) {
    Write-Host "[1/6] FULL REBUILD: Removing ALL containers..." -ForegroundColor Red
    docker ps -aq | ForEach-Object { docker stop $_ 2>$null; docker rm -f $_ 2>$null } | Out-Null
    Write-Host "      All containers removed" -ForegroundColor Green

    Write-Host "[2/6] FULL REBUILD: Removing ALL images..." -ForegroundColor Red
    docker images -q | ForEach-Object { docker rmi -f $_ 2>$null } | Out-Null
    Write-Host "      All images removed" -ForegroundColor Green

    Write-Host "[3/6] FULL REBUILD: Pruning Docker system..." -ForegroundColor Red
    docker builder prune -af 2>$null | Out-Null
    docker system prune -af --volumes 2>$null | Out-Null
    Write-Host "      Docker system pruned" -ForegroundColor Green

    Write-Host "[4/6] Building new image (this may take a while)..." -ForegroundColor Yellow
} else {
    # Remove existing containers (both labeled and by name pattern)
    Write-Host "[1/5] Removing existing containers..." -ForegroundColor Yellow
    $labeledContainers = docker ps -aq --filter "label=run-claude.managed=true" 2>$null
    $namedContainers = docker ps -aq --filter "name=claude-code" 2>$null
    $allContainers = @($labeledContainers) + @($namedContainers) | Where-Object { $_ } | Select-Object -Unique

    if ($allContainers) {
        foreach ($c in $allContainers) {
            docker stop $c 2>$null | Out-Null
            docker rm -f $c 2>$null | Out-Null
        }
        Write-Host "      Removed $($allContainers.Count) container(s)" -ForegroundColor Green
    } else {
        Write-Host "      No containers to remove" -ForegroundColor Gray
    }

    # Remove existing image (force)
    Write-Host "[2/5] Removing existing image..." -ForegroundColor Yellow
    $null = docker image inspect $ImageName 2>&1
    if ($LASTEXITCODE -eq 0) {
        $null = docker rmi -f $ImageName 2>&1
        Write-Host "      Removed image: $ImageName" -ForegroundColor Green
    } else {
        Write-Host "      No image to remove" -ForegroundColor Gray
    }

    # Clear build cache if requested
    if ($Clear) {
        Write-Host "[3/5] Clearing Docker build cache..." -ForegroundColor Yellow
        docker builder prune -af 2>$null | Out-Null
        Write-Host "      Build cache cleared" -ForegroundColor Green
    } else {
        Write-Host "[3/5] Skipping cache clear (use -Clear to enable)" -ForegroundColor Gray
    }

    Write-Host "[4/5] Building new image (this may take a while)..." -ForegroundColor Yellow
}

Write-Host ""

# Convert Windows path to WSL path
$wslScriptDir = wsl wslpath -u `"$ScriptDir`"

# Run build in WSL
$buildCmd = "cd $wslScriptDir && ./run-claude.sh --build"
if ($Verbose) {
    Write-Host "Running: wsl bash -c `"$buildCmd`"" -ForegroundColor Gray
}

wsl bash -c $buildCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Error: Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
if ($Rebuild) {
    Write-Host "[6/6] Build complete!" -ForegroundColor Green
} else {
    Write-Host "[5/5] Build complete!" -ForegroundColor Green
}
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Image ready: $ImageName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run:" -ForegroundColor White
Write-Host "  .\run-claude.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "Or in WSL:" -ForegroundColor White
Write-Host "  ./run-claude.sh" -ForegroundColor Yellow
Write-Host ""
Write-Host "Options:" -ForegroundColor White
Write-Host "  -Clear    Clear build cache only" -ForegroundColor Gray
Write-Host "  -Rebuild  Full rebuild (removes ALL Docker data)" -ForegroundColor Gray
Write-Host "  -Verbose  Show commands being executed" -ForegroundColor Gray
Write-Host ""
