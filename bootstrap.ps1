# Claude Code Docker Bootstrap Script
# Rebuilds the image from scratch every time

param(
    [string]$ImageName = "claude-code-joss:latest",
    [switch]$NoPull,
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

# Remove existing containers (both labeled and by name pattern)
Write-Host "[1/4] Removing existing containers..." -ForegroundColor Yellow
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
Write-Host "[2/4] Removing existing image..." -ForegroundColor Yellow
$null = docker image inspect $ImageName 2>&1
if ($LASTEXITCODE -eq 0) {
    $null = docker rmi -f $ImageName 2>&1
    Write-Host "      Removed image: $ImageName" -ForegroundColor Green
} else {
    Write-Host "      No image to remove" -ForegroundColor Gray
}

# Build new image using WSL
Write-Host "[3/4] Building new image (this may take a while)..." -ForegroundColor Yellow
Write-Host ""

$buildArgs = "--rebuild"
if ($Verbose) {
    $buildArgs += " --verbose"
}

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
Write-Host "[4/4] Build complete!" -ForegroundColor Green
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
