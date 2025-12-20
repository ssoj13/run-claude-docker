# Plan 3: MCP Server Optimization and Improvements

## Problem

Current implementation uses `bunx` and `uvx` to run MCP servers:
```dockerfile
bunx @playwright/mcp@latest
bunx -y @modelcontextprotocol/server-sequential-thinking
bunx -y @modelcontextprotocol/server-filesystem
bunx -y @kazuph/mcp-fetch
bunx -y exa-mcp-server
uvx --from git+https://github.com/BeehiveInnovations/zen-mcp-server.git zen-mcp-server
```

And Rust MCP servers are built from git:
```dockerfile
RUN git clone ... && cargo build --release && cp ...
```

This leads to:
- Package downloads on every startup (bunx)
- Slow MCP server startup
- Long build times from source
- Network dependency at runtime

## Solution: Global MCP Server Installation

### 1. Rust MCP Servers (via cargo install)

**Replace git clone + cargo build with cargo install:**

```dockerfile
# Rust MCP servers - install via cargo install
RUN cargo install filesystem-mcp-rs memory-mcp-rs fetch-mcp-rs
```

Binaries will be in `~/.cargo/bin/`:
- `filesystem-mcp`
- `memory-mcp`
- `fetch-mcp`

**Remove JS versions** - they duplicate functionality:
- ~~@modelcontextprotocol/server-filesystem~~ -> filesystem-mcp (Rust)
- ~~@kazuph/mcp-fetch~~ -> fetch-mcp (Rust)

### 2. NPM-based MCP Servers (via bun install -g)

Only those not available in Rust:

```dockerfile
# Install MCP servers globally (unique only)
RUN bun install -g \
    @playwright/mcp@latest \
    @modelcontextprotocol/server-sequential-thinking \
    exa-mcp-server
```

### 3. Python-based MCP Servers (via uv tool install)

```dockerfile
# Install zen-mcp-server
RUN uv tool install git+https://github.com/BeehiveInnovations/zen-mcp-server.git
```

Binary will be in `~/.local/bin/zen-mcp-server`

### 4. Updated claude mcp add Commands

```dockerfile
# === Rust MCP servers (fast, native) ===

RUN claude mcp add filesystem \
    --scope user -- \
    /home/${USERNAME}/.cargo/bin/filesystem-mcp /home/${USERNAME}

RUN claude mcp add memory \
    --scope user -- \
    /home/${USERNAME}/.cargo/bin/memory-mcp

RUN claude mcp add fetch \
    --scope user -- \
    /home/${USERNAME}/.cargo/bin/fetch-mcp

# === JS MCP servers (unique only) ===

RUN claude mcp add playwright \
    --scope user -- \
    /home/${USERNAME}/.bun/bin/mcp-server-playwright

RUN claude mcp add sequential-thinking \
    --scope user -- \
    /home/${USERNAME}/.bun/bin/mcp-server-sequential-thinking

RUN claude mcp add exa \
    --scope user -- \
    /home/${USERNAME}/.bun/bin/exa-mcp-server

# === Python MCP servers ===

RUN claude mcp add zen \
    --scope user -- \
    /home/${USERNAME}/.local/bin/zen-mcp-server

# === HTTP MCP servers (no installation required) ===

RUN claude mcp add context7 \
    --scope user \
    --transport http \
    https://mcp.context7.com/mcp
```

### 5. What We Remove

- ~~filesystem-rs~~ -> rename to `filesystem`
- ~~memory-rs~~ -> rename to `memory`
- ~~fetch-rs~~ -> rename to `fetch`
- ~~bunx @modelcontextprotocol/server-filesystem~~ (duplicate)
- ~~bunx @kazuph/mcp-fetch~~ (duplicate)
- All `git clone` + `cargo build --release` code for MCP servers

## Additional Improvements

### 5. Codex / OpenAI CLI

Add OpenAI CLI for direct access to Codex API:

```dockerfile
# OpenAI CLI
RUN bun install -g openai

# Or via pip
RUN uv tool install openai
```

Add to FORWARDED_VARIABLES:
```bash
FORWARDED_VARIABLES=(
    ...
    "OPENAI_API_KEY"
)
```

### 6. AI Services Authentication

Add environment variables to FORWARDED_VARIABLES in run-claude.sh:

```bash
FORWARDED_VARIABLES=(
    "ANTHROPIC_API_KEY"
    "OPENAI_API_KEY"
    "GITHUB_TOKEN"
    "QWEN_API_KEY"
    "GEMINI_API_KEY"
    "GOOGLE_API_KEY"
    "EXA_API_KEY"
    "NUGET_API_KEY"
    "UNSPLASH_ACCESS_KEY"
    "ANTHROPIC_MODEL"
    "TERM"
)
```

### 7. Docker Build Optimization

#### Multi-stage caching
```dockerfile
# Separate stage for bun packages
FROM user-env AS bun-packages
RUN bun install -g \
    @playwright/mcp@latest \
    @modelcontextprotocol/server-sequential-thinking \
    exa-mcp-server \
    @githubnext/github-copilot-cli

# Separate stage for Python tools
FROM bun-packages AS python-tools
RUN uv tool install git+https://github.com/BeehiveInnovations/zen-mcp-server.git
```

#### BuildKit cache mounts
```dockerfile
# syntax=docker/dockerfile:1.4
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    cargo build --release
```

### 8. Fixing Aliases

Replace bunx with direct calls:

```bash
# Before
alias qwen="bunx @qwenlm/cli || echo 'Qwen CLI not available'"
alias gemini="bunx @google/generative-ai || echo 'Google Gemini not available'"

# After
alias qwen="qwen-cli || echo 'Qwen CLI not available'"
alias gemini="gemini-cli || echo 'Google Gemini not available'"
```

### 9. Add GitHub MCP

```dockerfile
RUN bun install -g @modelcontextprotocol/server-github

RUN claude mcp add github \
    --scope user -- \
    /home/${USERNAME}/.bun/bin/mcp-server-github
```

### 10. Playwright Browser Installation

Playwright requires browsers to work:

```dockerfile
# After installing playwright mcp
RUN bunx playwright install chromium --with-deps
```

## Completed Changes

### Required - DONE
1. [x] Replace `git clone + cargo build` with `cargo install filesystem-mcp-rs memory-mcp-rs fetch-mcp-rs`
2. [x] Install JS MCP packages globally: `bun install -g @playwright/mcp @modelcontextprotocol/server-sequential-thinking exa-mcp-server`
3. [x] Install zen-mcp-server via `uv tool install`
4. [x] Update `claude mcp add` commands with direct binary paths
5. [x] Remove JS duplicates (filesystem, fetch) - use only Rust versions
6. [x] Rename MCP servers: filesystem-rs -> filesystem, memory-rs -> memory, fetch-rs -> fetch
7. [x] Add missing API keys to FORWARDED_VARIABLES
8. [x] Fix aliases in .zshrc (remove bunx, delete non-working qwen/gemini)

### Optional - TODO
9. [ ] Add OpenAI CLI for Codex
10. [ ] Install Playwright browsers (`bunx playwright install chromium --with-deps`)
11. [ ] Add GitHub MCP server
12. [ ] Optimize Docker build with cache mounts

---

# Complete Container Feature List

## Base Image
- **Ubuntu 25.04** - latest version

## Runtimes and Languages

| Component | Version | Path |
|-----------|---------|------|
| **Bun** | latest | `~/.bun/bin/` |
| **Rust** | stable + nightly | `~/.cargo/bin/` |
| **Go** | 1.21.5 | `/usr/local/go/bin/` |
| **Python 3** | system | `/usr/bin/python3` |
| **uv** | latest | `~/.cargo/bin/` |

## Development Tools

| Tool | Description |
|------|-------------|
| **git** | Version control |
| **cmake** | Build system |
| **gcc/g++** | C/C++ compilers |
| **build-essential** | Build tools |
| **vcpkg** | C++ package manager (`/opt/vcpkg`) |
| **ripgrep** | Fast grep (`rg`) |
| **fd-find** | Fast find (`fd`) |
| **fzf** | Fuzzy finder |
| **jq** | JSON processor |
| **tree** | Directory tree |
| **htop** | Process viewer |
| **git-delta** | Git diff viewer |

## Editors

| Editor | Description |
|--------|-------------|
| **Neovim** | Latest from GitHub releases |
| **LazyVim** | Neovim config framework |
| **vim** | Classic editor |
| **mc** | Midnight Commander |
| **far2l** | FAR Manager |

## Shell Environment

| Component | Description |
|-----------|-------------|
| **zsh** | Default shell |
| **oh-my-zsh** | Zsh framework |
| **zsh-autosuggestions** | Command suggestions |
| **zsh-syntax-highlighting** | Syntax highlighting |
| **Custom prompt** | `[run-claude]` prefix |

## AI Tools

| Tool | Location |
|------|----------|
| **Claude CLI** | `~/.local/bin/claude` |
| **GitHub Copilot CLI** | `~/.bun/bin/github-copilot-cli` |
| **gh CLI** | System package |

## MCP Servers

### Rust-based (fast, native)
| MCP Server | Path | Description |
|------------|------|-------------|
| **filesystem** | `~/.cargo/bin/filesystem-mcp` | File operations |
| **memory** | `~/.cargo/bin/memory-mcp` | Knowledge graph |
| **fetch** | `~/.cargo/bin/fetch-mcp` | HTTP requests |

### JS-based (globally installed)
| MCP Server | Path | Description |
|------------|------|-------------|
| **playwright** | `~/.bun/bin/mcp-server-playwright` | Browser automation |
| **sequential-thinking** | `~/.bun/bin/mcp-server-sequential-thinking` | Chain of thought |
| **exa** | `~/.bun/bin/exa-mcp-server` | Web search |

### Python-based
| MCP Server | Path | Description |
|------------|------|-------------|
| **zen** | `~/.local/bin/zen-mcp-server` | Productivity tools |

### Go-based
| MCP Server | Path | Description |
|------------|------|-------------|
| **unsplash** | `/usr/local/bin/unsplash-mcp-server` | Stock photos |

### HTTP-based (remote)
| MCP Server | URL | Description |
|------------|-----|-------------|
| **context7** | `https://mcp.context7.com/mcp` | Documentation lookup |

## Environment Variables (forwarded)

```bash
ANTHROPIC_API_KEY    # Claude API
OPENAI_API_KEY       # OpenAI/Codex API
GITHUB_TOKEN         # GitHub authentication
QWEN_API_KEY         # Qwen API
GEMINI_API_KEY       # Google Gemini API
GOOGLE_API_KEY       # Google API
EXA_API_KEY          # Exa search API
NUGET_API_KEY        # NuGet packages
UNSPLASH_ACCESS_KEY  # Unsplash photos
ANTHROPIC_MODEL      # Model override
TERM                 # Terminal type
```

## Container Features

### Authentication
- Claude OAuth config merge from host (`~/.claude.json`)
- Automatic `bypassPermissionsModeAccepted: true`
- SSH agent forwarding
- GPG agent forwarding
- Git config mounting

### Volumes (auto-mounted)
| Host | Container | Mode |
|------|-----------|------|
| `~/.claude/` | `~/.claude/` | rw |
| `~/.ssh/` | `~/.ssh/` | ro |
| `~/.gitconfig` | `~/.gitconfig` | ro |
| `~/.gnupg/` | `~/.gnupg/` | rw |
| Workspace | `~/<basename>` | rw |

### Aliases
```bash
claude          # With --dangerously-skip-permissions (if DANGEROUS_MODE)
claude-safe     # Without dangerous mode
copilot         # GitHub Copilot CLI
gh-copilot      # gh copilot command
vim, vi         # -> nvim
ll              # ls -la
```

## Script Features (run-claude.sh)

| Flag | Description |
|------|-------------|
| `-w, --workspace` | Set workspace path |
| `-n, --name` | Container name |
| `-i, --image` | Image name |
| `--rm` | Remove after exit |
| `--build` | Build image only |
| `--rebuild` | Force rebuild |
| `--pull` | Pull from registry |
| `--recreate` | Remove and recreate container |
| `--safe` | Disable dangerous mode |
| `--aws` | Forward AWS credentials |
| `-E VAR` | Forward extra env variable |
| `--extra-package PKG` | Add Ubuntu package (build only) |
| `--verbose` | Show docker commands |
| `--dry-run` | Preview without executing |
| `--remove-containers` | Clean up stopped containers |
| `--export-dockerfile` | Export Dockerfile |
| `--push-to REPO` | Push to registry |
| `--generate-completions` | Shell completions (bash/zsh) |
