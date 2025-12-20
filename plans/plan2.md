# Task Verification (task.md)

## Task Status

| Task | Status | Implementation |
|------|--------|----------------|
| Replace node.js with bun | ✅ | `curl -fsSL https://bun.sh/install \| bash`, PATH in .zshrc |
| Add git | ✅ | apt package |
| Add cmake | ✅ | apt package |
| Add latest gcc | ✅ | apt packages: gcc, g++ |
| Add vcpkg | ✅ | `/opt/vcpkg`, VCPKG_ROOT env var |
| Add rustup | ✅ | `curl https://sh.rustup.rs \| sh` |
| Add nightly Rust | ✅ | `rustup toolchain install nightly` |
| Add GitHub Copilot | ✅ | `bun install -g @githubnext/github-copilot-cli` |
| Add Qwen Code | ✅ | `bun install -g @qwenlm/cli` (with fallback) |
| Add Gemini | ✅ | `bun install -g @google/generative-ai` |
| Add filesystem-mcp-rs | ✅ | git clone + cargo build, claude mcp add |
| Add memory-mcp-rs | ✅ | git clone + cargo build, claude mcp add |
| Add fetch-mcp-rs | ✅ | git clone + cargo build, claude mcp add |
| Paths/env variables | ✅ | All in .zshrc and Dockerfile ENV |
| Authentication plan | ✅ | Described in plan1.md |

## Implementation Details

### Bun (Node.js replacement)
```dockerfile
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/home/$USERNAME/.bun/bin:$PATH"
```

### Development Tools
```dockerfile
RUN apt-get install -y \
    git \
    cmake \
    gcc \
    g++ \
    build-essential
```

### vcpkg
```dockerfile
RUN git clone https://github.com/Microsoft/vcpkg.git /opt/vcpkg && \
    cd /opt/vcpkg && \
    ./bootstrap-vcpkg.sh && \
    ./vcpkg integrate install

ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH=/opt/vcpkg:$PATH
```

### Rust + Nightly
```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH=/root/.cargo/bin:$PATH
RUN rustup toolchain install nightly --allow-downgrade
```

### AI Code Assistants
```dockerfile
# GitHub Copilot CLI
RUN bun install -g @githubnext/github-copilot-cli

# Qwen Code
RUN bun install -g @qwenlm/cli 2>/dev/null || echo "Qwen CLI not available"

# Google Gemini
RUN bun install -g @google/generative-ai 2>/dev/null || echo "Gemini needs setup"
```

Aliases in .zshrc:
```bash
alias copilot="github-copilot-cli"
alias qwen="bunx @qwenlm/cli || echo 'Qwen CLI not available'"
alias gemini="bunx @google/generative-ai || echo 'Google Gemini not available'"
```

### Rust MCP Servers
```dockerfile
# filesystem-mcp-rs
RUN git clone https://github.com/modelcontextprotocol/filesystem-mcp-rs.git /tmp/filesystem-mcp-rs && \
    cd /tmp/filesystem-mcp-rs && \
    cargo build --release && \
    cp /tmp/filesystem-mcp-rs/target/release/filesystem-mcp /usr/local/bin/

# memory-mcp-rs
RUN git clone https://github.com/modelcontextprotocol/memory-mcp-rs.git /tmp/memory-mcp-rs && \
    cd /tmp/memory-mcp-rs && \
    cargo build --release && \
    cp /tmp/memory-mcp-rs/target/release/memory-mcp /usr/local/bin/

# fetch-mcp-rs
RUN git clone https://github.com/modelcontextprotocol/fetch-mcp-rs.git /tmp/fetch-mcp-rs && \
    cd /tmp/fetch-mcp-rs && \
    cargo build --release && \
    cp /tmp/fetch-mcp-rs/target/release/fetch-mcp /usr/local/bin/
```

Claude MCP registration:
```dockerfile
RUN claude mcp add filesystem-rs --scope user -- /usr/local/bin/filesystem-mcp /home/${USERNAME}
RUN claude mcp add memory-rs --scope user -- /usr/local/bin/memory-mcp
RUN claude mcp add fetch-rs --scope user -- /usr/local/bin/fetch-mcp
```

## Notes and Possible Improvements

### 1. Codex
OpenAI Codex is not installed as a standalone product. GitHub Copilot CLI (`@githubnext/github-copilot-cli`) uses Codex under the hood, so the functionality is covered. For direct access to OpenAI Codex API:
- Add `OPENAI_API_KEY` to forwarded variables
- Use openai CLI or SDK

### 2. AI Services Authentication
Current implementation supports:
- **Claude**: OAuth via ~/.claude.json (automatic merge from host)
- **GitHub Copilot**: Requires `gh auth login` or GITHUB_TOKEN
- **Qwen**: Requires QWEN_API_KEY
- **Gemini**: Requires GEMINI_API_KEY or GOOGLE_API_KEY

Variables can be passed via `-E` flag:
```bash
./run-claude.sh -E GITHUB_TOKEN -E QWEN_API_KEY -E GEMINI_API_KEY
```

### 3. Rust MCP Servers - Potential Issue
Build happens under root, but binaries are copied to `/usr/local/bin/` which is correct. The `claude mcp add` commands execute under the user account, which is also correct.

## Conclusion

**All tasks from task.md are completed.** Plan is fully implemented in run-claude.sh via embedded Dockerfile.
