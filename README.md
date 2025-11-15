# Changelog / Fixes Applied

## WSL2 Docker Issues Fixed

### 1. Auto-recovery from stale bind-mount paths
**Problem**: WSL2 Docker Desktop uses dynamic bind-mount paths that change on restart, causing containers to fail with mount errors.

**Solution**:
- Added automatic detection of mount/bind-mount errors in container start
- Script now auto-removes stale containers and creates fresh ones
- Fixed `set -e` (errexit) issue that prevented error handling from working

### 2. Neovim version compatibility
**Problem**: LazyVim requires Neovim >= 0.11.2, but Ubuntu 25.04 ships with older version.

**Solution**: Install latest Neovim (v0.11.5) from GitHub releases instead of apt package.

### 3. UID conflicts
**Problem**: Ubuntu 25.04 base image has 'ubuntu' user with UID=1000, causing conflicts.

**Solution**: Delete ubuntu user before creating container user with explicit UID=1000 to match host.

### 4. Permission issues on mounted volumes
**Problem**: Container user had UID=1001, host user UID=1000, causing permission denied errors.

**Solution**: Explicitly set container user to UID=1000 to match host user.

## Package Management Improvements

### Replaced pip with uv
- **uv** is 10-100x faster than pip (written in Rust)
- Installed for both root and user accounts
- Supports `uvx` command (like npx for Python packages)

## MCP Servers Added

Added 5 new Model Context Protocol servers to Claude Code:

1. **sequential-thinking** - Step-by-step reasoning and problem solving
2. **filesystem** - File system operations with home directory access
3. **fetch** - Web content fetching capabilities
4. **zen** - Advanced AI workflows (installed via uvx from git)
5. **exa** - Enhanced search capabilities

Existing MCP servers:
- unsplash (Go binary)
- context7 (HTTP)
- playwright (npm)

## Tools Added

- **mc** (Midnight Commander) - Classic two-panel file manager
- **far2l** - Modern FAR Manager port for Linux

## Windows PowerShell Support

Created `run-claude.ps1` script for running containers from Windows:

**Features**:
- Full color support (`TERM=xterm-256color`, `COLORTERM=truecolor`)
- Container reuse (creates once, reattaches on subsequent runs)
- Automatic volume mounting for workspace and Claude config
- Works with same Docker image as WSL2

**Usage**:
```powershell
# From PowerShell
cd C:\Users\joss1
.\run-claude.ps1
```

## Image Location

The Docker image `claude-code-joss:latest` is shared between WSL2 and Windows:
- Built in WSL2: `./run-claude.sh --build`
- Used in Windows: `.\run-claude.ps1`
- Visible in Docker Desktop GUI

## Full Rebuild Command

```bash
# Remove old container and image
docker rm -f <container-name>
docker rmi claude-code-joss:latest

# Rebuild from scratch
./run-claude.sh --rebuild
```

## Technical Details

**Auto-recovery mechanism** (lines 1464-1467, 1507-1510 in run-claude.sh):
```bash
# Disable errexit temporarily to capture exit code
set +e
START_OUTPUT=$(timeout 10 docker start "$CONTAINER_NAME" </dev/null 2>&1)
START_EXIT_CODE=$?
set -e

# Check for mount errors and auto-remove stale containers
if [[ $START_EXIT_CODE -ne 0 ]]; then
  if [[ "$START_OUTPUT" =~ mount|bind-mounts ]]; then
    docker rm -f "$CONTAINER_NAME"
    return 1  # Let script create fresh container
  fi
fi
```

**Key fixes**:
- `set +e` / `set -e` wrapper prevents script exit on docker start failure
- `timeout 10` prevents infinite hang in WSL2
- `</dev/null` closes stdin to prevent Docker from waiting for input
- Regex pattern `mount|bind-mounts` detects WSL2 specific errors
