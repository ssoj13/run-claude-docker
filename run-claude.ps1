# Claude Code Docker Runner for Windows PowerShell
# Usage: .\run-claude.ps1 [workspace-path]

param(
    [string]$WorkspacePath = $PWD
)

$ContainerName = "claude-code-windows"
$ImageName = "claude-code-joss:latest"
$ClaudeConfig = "$env:USERPROFILE\.claude"

# Check if container exists and is running
$existing = docker ps -a --format "{{.Names}}" | Select-String -Pattern "^${ContainerName}$"

if ($existing) {
    Write-Host "Container $ContainerName already exists" -ForegroundColor Magenta

    $running = docker ps --format "{{.Names}}" | Select-String -Pattern "^${ContainerName}$"

    if ($running) {
        Write-Host "Attaching to running container..." -ForegroundColor Cyan
        docker exec -it `
            -e "TERM=xterm-256color" `
            -e "COLORTERM=truecolor" `
            $ContainerName /usr/local/bin/claude-exec
    } else {
        Write-Host "Starting stopped container..." -ForegroundColor Cyan
        docker start -i $ContainerName
    }
} else {
    Write-Host "Creating new container..." -ForegroundColor Green

    docker run -it `
        --name $ContainerName `
        --network host `
        -v "${WorkspacePath}:/workspace" `
        -v "${ClaudeConfig}:/home/claude-user/.claude" `
        -e "TERM=xterm-256color" `
        -e "COLORTERM=truecolor" `
        $ImageName
}
