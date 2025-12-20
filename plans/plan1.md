# Plan for Container Modification (Revised)

## Overview
This plan outlines the modifications needed to enhance the Claude Code Docker container by adding new tools, replacing Node.js with Bun, and incorporating additional AI services.

## 1. Add Development Tools

### Git
- Already partially present in base Ubuntu, ensure latest version
- Configure global git settings for the claude-user

### CMake
- Install latest CMake version
- Add to PATH and verify installation

### Latest GCC
- Install latest GCC compiler suite
- Ensure C++ support is included
- Verify installation with test compilation

### vcpkg
- Install Microsoft's vcpkg package manager
- Set up environment variables for vcpkg
- Integrate with CMake for package management

## 2. Install Rust and Add Rust-based MCP Servers

### Rustup and Nightly Rust
- Install rustup for Rust toolchain management
- Configure for claude-user
- Install nightly Rust toolchain alongside stable
- Set up PATH for Rust tools and environment variables

### Add Rust-based MCP Servers
- Clone and build filesystem-mcp-rs from source
- Clone and build memory-mcp-rs from source
- Clone and build fetch-mcp-rs from source
- Install binaries to appropriate location
- Configure with Claude MCP system

## 3. Replace Node.js with Bun and Add AI Code Assistants

### Replace Node.js with Bun
- Remove fnm installation lines from Dockerfile
- Install Bun runtime instead of Node.js
- Update all npm package installations to use Bun equivalents
- Ensure compatibility with existing MCP servers

### Add AI Code Assistants
- Install GitHub Copilot/Codex
  - Install GitHub Copilot CLI or VS Code extension support
  - Set up authentication mechanism
  - Configure for use within the container environment
- Install Qwen Code
  - Install Qwen Code CLI or appropriate interface
  - Set up authentication mechanism
  - Configure for container environment
- Install Google Gemini
  - Install Gemini CLI or API client
  - Set up authentication mechanism
  - Configure for container environment
- Install GitHub Copilot
  - Install Copilot CLI tools
  - Set up authentication mechanism
  - Configure for container environment

## 4. Environment Variables and Path Configuration

### PATH Management
- Ensure all new tools are added to PATH
- Verify order of PATH entries for precedence
- Test that all tools are accessible from command line

### Environment Variables
- Set up required environment variables for each tool
- Ensure variables persist for both root and user sessions
- Document all new environment variables

## 5. Authentication System for Multiple AI Services

### Current Claude Authentication
- Claude uses OAuth-based authentication stored in ~/.claude.json
- Configuration includes oauthAccount, userID, hasSeenTasksHint, hasCompletedOnboarding, lastOnboardingVersion, subscriptionNoticeCount, hasAvailableSubscription, s1mAccessCache
- Host configuration (~/.claude.host.json) is merged with container during startup in the entrypoint script
- The entrypoint script extracts specific config keys from the host file and merges them with container config
- Bypass permissions mode is automatically enabled with "bypassPermissionsModeAccepted": true

### Entry Point Authentication Process
```bash
# Extract specific config keys from host file
CONFIG_KEYS="oauthAccount hasSeenTasksHint userID hasCompletedOnboarding lastOnboardingVersion subscriptionNoticeCount hasAvailableSubscription s1mAccessCache"

# Build jq expression for extraction
JQ_EXPR=""
for key in $CONFIG_KEYS; do
  if [ -n "$JQ_EXPR" ]; then JQ_EXPR="$JQ_EXPR, "; fi
  JQ_EXPR="$JQ_EXPR\"$key\": .$key"
done

# Extract config data and add bypass permissions
HOST_CONFIG=$(jq -c "{$JQ_EXPR, \"bypassPermissionsModeAccepted\": true}" "$HOME/.claude.host.json" 2>/dev/null || echo "")

# Merge with existing container file or create new one
if [ -f "$HOME/.claude.json" ]; then
  jq ". * $HOST_CONFIG" "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
else
  echo "$HOST_CONFIG" | jq . > "$HOME/.claude.json"
fi
```

### Proposed Multi-AI Authentication
- Implement secure environment variable passing for API keys
- Create a unified authentication configuration system
- Consider a credential management service within the container
- Mount separate config files for different AI services
- Use environment variables for API keys (ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.)

#### Authentication Methods for Each Service

1. **GitHub Copilot/Codex**:
   - Uses GitHub authentication via gh CLI
   - Requires GITHUB_TOKEN environment variable
   - Can authenticate through mounted ~/.config/gh/hosts.yml file
   - Alternative: OAuth token stored in environment variable

2. **Qwen Code**:
   - Uses Alibaba Cloud API key
   - Requires QWEN_API_KEY environment variable
   - May need additional configuration in ~/.qwen/ or similar directory
   - Authentication via API key in headers

3. **Google Gemini**:
   - Uses Google Cloud API key
   - Requires GEMINI_API_KEY or GOOGLE_API_KEY environment variable
   - Can also authenticate via service account key file
   - May use gcloud CLI authentication if available

4. **General Authentication Strategy**:
   - Create a centralized authentication configuration file
   - Support environment variable-based authentication
   - Mount authentication files from host system
   - Implement secure credential passing mechanism
   - Provide fallback authentication methods
   - Support both API key and OAuth-based services

#### Security Implementation
- Use Docker secrets for sensitive authentication data (when available)
- Implement proper file permissions for config files
- Support encrypted credential storage
- Enable secure credential mounting from host
- Provide authentication validation for each service

## Implementation Strategy

### Phase 1: Core Infrastructure
1. Add git, cmake, gcc, and vcpkg
2. Verify all path and environment variable configurations

### Phase 2: Rust and MCP Servers
1. Add rustup and nightly Rust
2. Add filesystem-mcp-rs, memory-mcp-rs, and fetch-mcp-rs
3. Configure MCP servers with Claude MCP system
4. Verify all path and environment variable configurations

### Phase 3: Bun and AI Services
1. Replace Node.js with Bun
2. Add GitHub Copilot/Codex
3. Add Qwen Code
4. Add Google Gemini
5. Set up authentication for each service
6. Verify all path and environment variable configurations

### Phase 4: Integration and Testing
1. Test all new tools work together
2. Verify authentication systems function correctly
3. Ensure existing Claude functionality remains intact
4. Document any new usage instructions

## Security Considerations
- Secure handling of API keys and authentication tokens
- Isolate authentication data for different services
- Ensure container security is not compromised
- Follow best practices for credential management in containers