# Remaining Optional Tasks - ALL COMPLETED

## 1. OpenAI CLI for Codex API ✅
**Status:** DONE

```dockerfile
RUN uv tool install openai
```

Alias added: `alias openai="~/.local/bin/openai"`

---

## 2. Playwright Browser Installation ✅
**Status:** DONE

```dockerfile
RUN bunx playwright install chromium --with-deps
```

Chromium browser installed for full Playwright MCP functionality.

---

## 3. GitHub MCP Server ✅
**Status:** DONE

```dockerfile
RUN bun install -g @modelcontextprotocol/server-github

RUN claude mcp add github \
    --scope user -- \
    /home/${USERNAME}/.bun/bin/mcp-server-github
```

---

## 4. BuildKit Cache Mounts ✅
**Status:** DONE

Added `# syntax=docker/dockerfile:1.4` to Dockerfile header.

Cache mounts added for:
- Cargo registry and git: `--mount=type=cache,target=/home/${USERNAME}/.cargo/registry`
- Bun install cache: `--mount=type=cache,target=/home/${USERNAME}/.bun/install/cache`

---

## Summary

All optional tasks have been implemented. The container now includes:

| Feature | Status |
|---------|--------|
| OpenAI CLI | ✅ Installed via uv |
| Playwright browsers | ✅ Chromium installed |
| GitHub MCP server | ✅ Registered with Claude |
| BuildKit caching | ✅ Enabled for cargo & bun |

## Build Command

```bash
DOCKER_BUILDKIT=1 ./run-claude.sh --rebuild
```

Note: BuildKit is enabled by default in modern Docker versions.
